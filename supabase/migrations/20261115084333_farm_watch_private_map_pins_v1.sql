-- Creator-only annotations. Existing pins remain shared; no owner, role, geometry,
-- fixture, or evidence changes. Pin DTOs and photo authorization change atomically.
begin;
alter table farm_watch.property_map_pins_v1 add column is_private boolean not null default false;
comment on column farm_watch.property_map_pins_v1.is_private is 'Visible only to the creating account when true; false shares with authorized property users.';
drop function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer);
create or replace function public.farm_watch_map_pins_v1(
  p_property_slug text, p_action text,
  p_pin_id uuid default null, p_expected_revision integer default null,
  p_title text default null, p_notes text default null,
  p_longitude double precision default null, p_latitude double precision default null,
  p_color text default null, p_icon text default null, p_category text default null,
  p_camera_bearing_deg integer default null, p_camera_range_m double precision default null, p_camera_fov_deg integer default null,
  p_is_private boolean default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  property farm_watch.properties%rowtype;
  pin farm_watch.property_map_pins_v1%rowtype;
  point extensions.geometry;
  result jsonb;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
    or not exists (select 1 from auth.users where id = actor)
    or not public.farm_watch_authorize_user_v1_internal(actor)
    or coalesce(public.farm_watch_get_account_role_v1_internal(actor), '') not in ('owner','admin','viewer') then
    raise exception 'not found' using errcode = '42501';
  end if;
  -- Farm Watch currently has account-wide access to active properties, not a
  -- property-membership model. Reuse that exact authorization contract; all
  -- queries below additionally require this explicit selected property.
  select * into property from farm_watch.properties where slug = p_property_slug and status = 'active';
  if property.id is null then raise exception 'not found' using errcode = '42501'; end if;
  if p_action = 'list' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'photo_count',(select count(*) from farm_watch.map_pin_photos_v1 ph where ph.pin_id=m.id),
      'id', m.id, 'title', m.title, 'notes', m.notes, 'color', m.color, 'icon', m.icon, 'category', m.category, 'is_private', m.is_private,
      'camera_bearing_deg',case when m.icon='trail_camera' then m.camera_bearing_deg end,
      'camera_range_m',case when m.icon='trail_camera' then coalesce(m.camera_range_m,24.384) end,
      'camera_fov_deg',case when m.icon='trail_camera' then coalesce(m.camera_fov_deg,40) end,
      'longitude', extensions.st_x(m.geometry), 'latitude', extensions.st_y(m.geometry),
      'created_at', m.created_at, 'updated_at', m.updated_at, 'revision', m.revision,
      'can_edit', m.created_by = actor,
      'creator_label', case when m.created_by = actor then 'You' else 'Property member' end
    ) order by m.created_at, m.id), '[]'::jsonb) into result
    from farm_watch.property_map_pins_v1 m where m.property_id = property.id and (not m.is_private or m.created_by = actor);
    return jsonb_build_object('pins', result, 'capabilities', jsonb_build_object(
      'can_use_pin_icons', farm_watch.can_use_map_pin_icons_v1(actor)));
  end if;
  if p_action is null or p_action not in ('create','update','delete') then
    raise exception 'invalid action' using errcode = '22023';
  end if;
  if p_action in ('create','update') then
    if p_title is null or char_length(btrim(p_title)) not between 1 and 100 or p_title !~ '[^[:space:]]'
      or char_length(p_notes) > 2000
      or p_longitude is null or not (p_longitude between -180 and 180)
      or p_latitude is null or not (p_latitude between -90 and 90) then
      raise exception 'invalid pin' using errcode = '22023';
    end if;
    if p_color is not null and (char_length(p_color)<>7 or p_color !~ '^#[0-9A-Fa-f]{6}$') then
      raise exception 'invalid pin color' using errcode = '22023';
    end if;
    if p_icon is not null and p_icon not in ('pin','deerstand','water_pump','container','trail_camera','gate','bonfire','crop','corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand') then
      raise exception 'invalid pin icon' using errcode = '22023';
    end if;
    if p_icon is not null and p_icon <> 'pin' and not farm_watch.can_use_map_pin_icons_v1(actor) then
      raise exception 'not found' using errcode = '42501';
    end if;
    if p_category is not null and p_category not in ('auto','general','hunting','farming-orchard') then
      raise exception 'invalid pin category' using errcode = '22023';
    end if;
    if (p_camera_bearing_deg is not null and not (p_camera_bearing_deg between 0 and 359))
      or (p_camera_range_m is not null and not (p_camera_range_m between 1.524 and 91.44))
      or (p_camera_fov_deg is not null and not (p_camera_fov_deg between 10 and 120)) then
      raise exception 'invalid camera view' using errcode = '22023';
    end if;
    point := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude),4326);
  end if;
  if p_action = 'create' then
    if p_pin_id is not null or p_expected_revision is not null then
      raise exception 'invalid create' using errcode = '22023';
    end if;
    -- Serialize bounded creates for a property, including concurrent callers.
    perform 1 from farm_watch.properties where id = property.id for update;
    if (select count(*) from farm_watch.property_map_pins_v1 where property_id = property.id) >= 500 then
      raise exception 'property pin limit reached' using errcode = '54000';
    end if;
    if coalesce(p_icon,'pin')<>'trail_camera' and
      (p_camera_bearing_deg is not null or p_camera_range_m is not null or p_camera_fov_deg is not null) then
      raise exception 'camera view requires trail camera icon' using errcode = '22023';
    end if;
    if p_icon='trail_camera' and p_camera_bearing_deg is null and
      (p_camera_range_m is not null or p_camera_fov_deg is not null) then
      raise exception 'camera direction required' using errcode = '22023';
    end if;
    insert into farm_watch.property_map_pins_v1(property_id,created_by,title,notes,geometry,color,icon,category,is_private,camera_bearing_deg,camera_range_m,camera_fov_deg)
    values(property.id,actor,btrim(p_title),nullif(p_notes,''),point,lower(coalesce(p_color,'#ffd27e')),coalesce(p_icon,'pin'),coalesce(p_category,'auto'),coalesce(p_is_private,false),
      case when p_icon='trail_camera' then p_camera_bearing_deg end,
      case when p_icon='trail_camera' and p_camera_bearing_deg is not null then coalesce(p_camera_range_m,24.384) end,
      case when p_icon='trail_camera' and p_camera_bearing_deg is not null then coalesce(p_camera_fov_deg,40) end) returning * into pin;
  else
    -- Row lock plus revision comparison also protects delete from concurrent edits.
    select * into pin from farm_watch.property_map_pins_v1
    where id = p_pin_id and property_id = property.id and created_by = actor for update;
    if pin.id is null then raise exception 'not found' using errcode = '42501'; end if;
    if p_expected_revision is null or p_expected_revision <> pin.revision then
      raise exception 'pin changed; reload' using errcode = 'PT409';
    end if;
    if p_action = 'delete' then
      delete from farm_watch.property_map_pins_v1 where id = pin.id;
      return jsonb_build_object('deleted', true);
    end if;
    if coalesce(p_icon,pin.icon)<>'trail_camera' and
      (p_camera_bearing_deg is not null or p_camera_range_m is not null or p_camera_fov_deg is not null) then
      raise exception 'camera view requires trail camera icon' using errcode = '22023';
    end if;
    if coalesce(p_icon,pin.icon)='trail_camera' and coalesce(p_camera_bearing_deg,pin.camera_bearing_deg) is null and
      (p_camera_range_m is not null or p_camera_fov_deg is not null) then
      raise exception 'camera direction required' using errcode = '22023';
    end if;
    update farm_watch.property_map_pins_v1 set title = btrim(p_title),notes = nullif(p_notes,''),geometry = point,
      color = coalesce(lower(p_color),pin.color), icon = coalesce(p_icon,pin.icon), category = coalesce(p_category,pin.category), is_private = coalesce(p_is_private,pin.is_private),
      camera_bearing_deg = case when coalesce(p_icon,pin.icon)='trail_camera' then coalesce(p_camera_bearing_deg,pin.camera_bearing_deg) end,
      camera_range_m = case when coalesce(p_icon,pin.icon)='trail_camera' and coalesce(p_camera_bearing_deg,pin.camera_bearing_deg) is not null then coalesce(p_camera_range_m,pin.camera_range_m,24.384) end,
      camera_fov_deg = case when coalesce(p_icon,pin.icon)='trail_camera' and coalesce(p_camera_bearing_deg,pin.camera_bearing_deg) is not null then coalesce(p_camera_fov_deg,pin.camera_fov_deg,40) end
    where id = pin.id returning * into pin;
  end if;
  return jsonb_build_object('pin', jsonb_build_object(
    'photo_count',(select count(*) from farm_watch.map_pin_photos_v1 ph where ph.pin_id=pin.id),
    'id',pin.id, 'title',pin.title, 'notes',pin.notes, 'color',pin.color, 'icon',pin.icon, 'category',pin.category, 'is_private',pin.is_private,
    'camera_bearing_deg',pin.camera_bearing_deg,
    'camera_range_m',case when pin.icon='trail_camera' then coalesce(pin.camera_range_m,24.384) end,
    'camera_fov_deg',case when pin.icon='trail_camera' then coalesce(pin.camera_fov_deg,40) end,
    'longitude',extensions.st_x(pin.geometry), 'latitude',extensions.st_y(pin.geometry),
    'created_at',pin.created_at, 'updated_at',pin.updated_at, 'revision',pin.revision,
    'can_edit',true, 'creator_label','You'));
end $$;
revoke all on function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)
from public, anon, authenticated, service_role;
grant execute on function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)
to authenticated;

create or replace function public.farm_watch_pin_photos_v1(p_property_slug text,p_pin_id uuid,p_action text,
 p_photo_id uuid default null,p_expected_revision integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); property farm_watch.properties%rowtype; pin farm_watch.property_map_pins_v1%rowtype;
 photo farm_watch.map_pin_photos_v1%rowtype; object storage.objects%rowtype; path text; result jsonb;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  or not exists(select 1 from auth.users where id=actor)
  or not public.farm_watch_authorize_user_v1_internal(actor)
  or coalesce(public.farm_watch_get_account_role_v1_internal(actor),'') not in ('owner','admin','viewer') then
  raise exception 'not found' using errcode='42501';
 end if;
 select * into property from farm_watch.properties where slug=p_property_slug and status='active';
 if property.id is null then raise exception 'not found' using errcode='42501'; end if;
 if p_action in ('prepare','attach','delete') then
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id and created_by=actor for update;
 else
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id and (not is_private or created_by=actor);
 end if;
 if pin.id is null then raise exception 'not found' using errcode='42501'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'width',width,'height',height,'bytes',bytes) order by created_at,id),'[]') into result
   from farm_watch.map_pin_photos_v1 where pin_id=pin.id;
  return jsonb_build_object('photos',result,'revision',pin.revision);
 elsif p_action='read' then
  select * into photo from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
  return jsonb_build_object('object_path',photo.object_path,'bytes',photo.bytes);
 elsif p_action not in ('prepare','attach','delete') or p_action is null then
  raise exception 'invalid action' using errcode='22023';
 end if;
 if pin.icon<>'pin' and not farm_watch.can_use_map_pin_icons_v1(actor) then raise exception 'not found' using errcode='42501'; end if;
 if p_expected_revision is null or pin.revision<>p_expected_revision then raise exception 'pin changed; reload' using errcode='PT409'; end if;
 if p_photo_id is null then raise exception 'invalid photo' using errcode='22023'; end if;
 path:=property.id::text||'/'||pin.id::text||'/'||p_photo_id::text||'.webp';
 if p_action in ('prepare','attach') and (select count(*) from farm_watch.map_pin_photos_v1 where pin_id=pin.id)>=4 then
  raise exception 'four photos maximum' using errcode='PT409';
 end if;
 if p_action='prepare' then return jsonb_build_object('object_path',path); end if;
 if p_action='attach' then
  -- Only server-processed objects in this pin's own namespace can be attached.
  -- Clients cannot upload/read objects directly or forge these Storage fields.
  if exists(select 1 from farm_watch.map_pin_photo_deletions_v1 where object_path=path)
   or exists(select 1 from farm_watch.map_pin_photos_v1 where id=p_photo_id) then
   raise exception 'invalid photo' using errcode='22023';
  end if;
  select * into object from storage.objects where bucket_id='farm-watch-pin-photos' and name=path;
  if object.id is null or object.created_at<now()-interval '15 minutes' or object.metadata->>'mimetype' is distinct from 'image/webp'
   or object.user_metadata->>'pin_id' is distinct from pin.id::text
   or object.user_metadata->>'photo_id' is distinct from p_photo_id::text
   or coalesce(object.metadata->>'size','')!~'^[0-9]{1,7}$'
   or coalesce(object.user_metadata->>'width','')!~'^[0-9]{1,4}$'
   or coalesce(object.user_metadata->>'height','')!~'^[0-9]{1,4}$' then
   raise exception 'invalid processed photo' using errcode='22023';
  end if;
  insert into farm_watch.map_pin_photos_v1(id,pin_id,object_path,width,height,bytes)
   values(p_photo_id,pin.id,path,(object.user_metadata->>'width')::integer,(object.user_metadata->>'height')::integer,(object.metadata->>'size')::integer)
   returning * into photo;
 else
  delete from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id returning * into photo;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
 end if;
 -- Serialize attachment changes with normal edits/deletion and the same guard.
 update farm_watch.property_map_pins_v1 set title=title where id=pin.id returning * into pin;
 return jsonb_build_object('revision',pin.revision,'photo',jsonb_build_object('id',photo.id,'width',photo.width,'height',photo.height,'bytes',photo.bytes));
end $$;
revoke all on function public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer) to authenticated;

notify pgrst, 'reload schema';
commit;
