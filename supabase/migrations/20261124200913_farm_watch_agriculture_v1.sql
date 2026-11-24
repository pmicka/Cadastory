begin;

-- NULL keeps the legacy category (including automatic pin categories).
-- An empty array explicitly selects the general layer only.
create function farm_watch.valid_specialized_views(views text[])
returns boolean language sql immutable set search_path = '' as $$
  select views is null or (
    coalesce(array_ndims(views),1) = 1
    and cardinality(views) <= 2
    and array_position(views,null) is null
    and views <@ array['hunting','farming-orchard']
    and (cardinality(views) < 2 or views @> array['hunting','farming-orchard'])
  )
$$;

create function farm_watch.valid_agriculture(metadata jsonb, is_area boolean)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  item record;
  allowed_keys text[];
begin
  if metadata is null then return true; end if;
  if jsonb_typeof(metadata) <> 'object' or not (metadata ? 'type') then return false; end if;
  if is_area then
    allowed_keys := array['type','status','season','crop_mix','target_date','planted_date','soil_test_date'];
    if coalesce(metadata->>'type','') not in
      ('food_plot','cover_crop','orchard','garden','crop_field','pasture','habitat_management','turkey_exclusion','other')
      or coalesce(metadata->>'status','planned') not in ('planned','in_preparation','active','inactive') then
      return false;
    end if;
  else
    allowed_keys := array['type','status','species','cultivar','rootstock','planted_date','planned_date','condition','protection'];
    if coalesce(metadata->>'type','') not in ('fruit_tree','nut_tree','perennial','planting_location')
      or coalesce(metadata->>'status','planned') not in ('planned','established','removed','failed') then
      return false;
    end if;
  end if;
  for item in select key,value from jsonb_each(metadata) loop
    if not (item.key = any(allowed_keys)) or jsonb_typeof(item.value) <> 'string'
      or char_length(btrim(item.value#>>'{}')) not between 1 and 500 then return false; end if;
    if item.key in ('target_date','planted_date','planned_date','soil_test_date') then
      if (item.value#>>'{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
      perform (item.value#>>'{}')::date;
    end if;
  end loop;
  return true;
exception when datetime_field_overflow or invalid_datetime_format then
  return false;
end
$$;

create function farm_watch.is_growing_area(metadata jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(metadata->>'type' in ('food_plot','cover_crop','orchard','garden','crop_field','pasture'),false)
$$;

alter table farm_watch.saved_map_areas_v1
  add column specialized_views text[] check (farm_watch.valid_specialized_views(specialized_views)),
  add column agriculture jsonb check (farm_watch.valid_agriculture(agriculture,true)),
  add constraint farm_watch_area_property_identity unique (property_id,id);

alter table farm_watch.property_map_pins_v1
  add column specialized_views text[] check (farm_watch.valid_specialized_views(specialized_views)),
  add column agriculture jsonb check (farm_watch.valid_agriculture(agriculture,false)),
  add column planting_group_id uuid check (planting_group_id is null or agriculture is not null),
  add constraint farm_watch_planting_group_fk foreign key (property_id,planting_group_id)
    references farm_watch.saved_map_areas_v1(property_id,id) on delete set null (planting_group_id);

create index farm_watch_planting_group_idx on farm_watch.property_map_pins_v1(property_id,planting_group_id)
  where planting_group_id is not null;

create function farm_watch.can_manage_agriculture()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.farm_watch_get_account_role_v1_internal(auth.uid()) in ('owner','admin'),false)
$$;

-- Protect existing agricultural records on legacy RPCs, including pin photo writes.
-- The original creator and active-property checks still run on all public entry points.
create function farm_watch.guard_agricultural_annotation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not farm_watch.can_manage_agriculture() then
    if tg_op <> 'INSERT' and (old.agriculture is not null or old.specialized_views is not null) then
      raise exception 'not found' using errcode = '42501';
    end if;
    if tg_op <> 'DELETE' and (new.agriculture is not null or new.specialized_views is not null) then
      raise exception 'not found' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

create trigger guard_agricultural_area before insert or update or delete on farm_watch.saved_map_areas_v1
  for each row execute function farm_watch.guard_agricultural_annotation();
create trigger guard_agricultural_pin before insert or update or delete on farm_watch.property_map_pins_v1
  for each row execute function farm_watch.guard_agricultural_annotation();

create or replace function farm_watch.guard_map_pin_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- A group can be deleted by its creator even when another member owns an
  -- associated pin or its existing location no longer fits the current parcel.
  if tg_op='UPDATE' and pg_trigger_depth() > 1 and old.planting_group_id is not null and new.planting_group_id is null
    and (to_jsonb(old)-'planting_group_id') = (to_jsonb(new)-'planting_group_id') then
    new.updated_at := clock_timestamp();
    new.revision := old.revision + 1;
    return new;
  end if;
  if new.icon <> 'pin' and not farm_watch.can_use_map_pin_icons_v1(auth.uid()) then
    raise exception 'not found' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' then
    if (new.id, new.property_id, new.created_by, new.created_at) is distinct from
       (old.id, old.property_id, old.created_by, old.created_at) then
      raise exception 'immutable pin identity' using errcode = '42501';
    end if;
    new.updated_at := clock_timestamp();
    new.revision := old.revision + 1;
  end if;
  -- Annotations may sit up to 100 ft (30.48 m) beyond the selected property.
  -- Geography measures metres on the spheroid, including near interior rings.
  -- This placement allowance does not alter the stored property geometry.
  if not exists (select 1 from farm_watch.properties p
    where p.id = new.property_id and p.status = 'active' and p.boundary is not null
      and case when extensions.st_isvalid(p.boundary) then
        extensions.st_covers(p.boundary, new.geometry) or
        extensions.st_dwithin(p.boundary::extensions.geography, new.geometry::extensions.geography, 30.48)
      else false end) then
    raise exception 'pin must be on the property or within 100 ft of its boundary' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function farm_watch.guard_map_pin_v1() from public, anon, authenticated, service_role;


create function farm_watch.detach_declassified_plantings()
returns trigger language plpgsql set search_path = '' as $$
begin
  update farm_watch.property_map_pins_v1 set planting_group_id=null
    where property_id=new.property_id and planting_group_id=new.id;
  return null;
end
$$;

create trigger detach_declassified_plantings after update of agriculture on farm_watch.saved_map_areas_v1
  for each row when (farm_watch.is_growing_area(old.agriculture) and not farm_watch.is_growing_area(new.agriculture))
  execute function farm_watch.detach_declassified_plantings();

create function public.farm_watch_saved_areas_v3(
  p_property_slug text, p_action text, p_id uuid default null, p_revision integer default null,
  p_title text default null, p_outline jsonb default null, p_color text default null,
  p_category text default null, p_is_private boolean default null,
  p_notes text default null, p_photos jsonb default null,
  p_specialized_views text[] default null, p_agriculture jsonb default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  result jsonb;
  existing farm_watch.saved_map_areas_v1%rowtype;
  acreage jsonb;
  can_manage boolean := farm_watch.can_manage_agriculture();
begin
  if (p_specialized_views is not null or p_agriculture is not null) and not can_manage then
    raise exception 'not found' using errcode = '42501';
  end if;
  if p_action='create' and (p_specialized_views is not null or p_agriculture is not null) then
    -- Serialize retries with v1/v2 before comparing the add-on fields.
    perform 1 from farm_watch.properties where slug=p_property_slug and status='active' for update;
    select * into existing from farm_watch.saved_map_areas_v1
      where id=p_id and created_by=auth.uid();
  end if;
  result := public.farm_watch_saved_areas_v2(
    p_property_slug,p_action,p_id,p_revision,p_title,p_outline,p_color,p_category,p_is_private,p_notes,p_photos
  );
  if p_action='list' then
    select coalesce(jsonb_agg(case
      when not can_manage and (item->'agriculture' <> 'null'::jsonb or item->'specialized_views' <> 'null'::jsonb)
      then item || '{"can_edit":false}'::jsonb else item end),'[]'::jsonb)
    into result from jsonb_array_elements(result->'areas') item;
    -- All acreage uses the same spheroidal measure and the same authorized snapshot.
    -- Union within each type and across types. Inactive and non-growing areas are excluded.
    with outlines as (
      select item->'agriculture'->>'type' as kind,
        extensions.st_geomfromgeojson(jsonb_build_object('type','Polygon','coordinates',
          jsonb_build_array((item->'outline') || jsonb_build_array(item->'outline'->0)))) as geom
      from jsonb_array_elements(result) item
      where farm_watch.is_growing_area(item->'agriculture')
        and coalesce(item->'agriculture'->>'status','') <> 'inactive'
    ), unions as (
      select kind, extensions.st_area(extensions.st_union(geom)::extensions.geography) / 4046.8564224 as acres
      from outlines group by grouping sets ((kind),())
    )
    select jsonb_build_object(
      'unique_acres',coalesce(max(acres) filter (where kind is null),0),
      'by_type',coalesce(jsonb_object_agg(coalesce(kind,''),acres) filter (where kind is not null),'{}'::jsonb)
    ) into acreage from unions;
    return jsonb_build_object('areas',result,'managed_acreage',acreage,'can_manage_agriculture',can_manage);
  end if;
  if p_action in ('create','update') and (p_specialized_views is not null or p_agriculture is not null) then
    if p_action = 'create' and existing.id is not null and
      ((p_specialized_views is not null and p_specialized_views is distinct from existing.specialized_views)
        or (p_agriculture is not null and nullif(p_agriculture,'{}'::jsonb) is distinct from existing.agriculture)) then
      raise exception 'area changed; reload' using errcode='PT409';
    end if;
    update farm_watch.saved_map_areas_v1 set
      specialized_views=coalesce(p_specialized_views,specialized_views),
      agriculture=case when p_agriculture is null then agriculture else nullif(p_agriculture,'{}'::jsonb) end
    where id=p_id returning * into existing;
    result := jsonb_set(result,'{area}',(to_jsonb(existing)-'created_by'-'property_id') || '{"can_edit":true}'::jsonb);
  end if;
  return result;
end
$$;

revoke all on function public.farm_watch_saved_areas_v3(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb,text[],jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_saved_areas_v3(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb,text[],jsonb)
  to authenticated;

create function public.farm_watch_map_pins_v2(
  p_property_slug text, p_action text,
  p_pin_id uuid default null, p_expected_revision integer default null,
  p_title text default null, p_notes text default null,
  p_longitude double precision default null, p_latitude double precision default null,
  p_color text default null, p_icon text default null, p_category text default null,
  p_camera_bearing_deg integer default null, p_camera_range_m double precision default null, p_camera_fov_deg integer default null,
  p_is_private boolean default null
,
  p_specialized_views text[] default null, p_agriculture jsonb default null,
  p_group_id uuid default null, p_set_group boolean default false
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  property farm_watch.properties%rowtype;
  pin farm_watch.property_map_pins_v1%rowtype;
  point extensions.geometry;
  result jsonb;
  can_manage boolean := farm_watch.can_manage_agriculture();
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
      'specialized_views',m.specialized_views,'agriculture',m.agriculture,
      'planting_group_id',g.id,
      'can_edit', m.created_by = actor and (can_manage or (m.agriculture is null and m.specialized_views is null)),
      'creator_label', case when m.created_by = actor then 'You' else 'Property member' end
    ) order by m.created_at, m.id), '[]'::jsonb) into result
    from farm_watch.property_map_pins_v1 m
    left join farm_watch.saved_map_areas_v1 g on g.id=m.planting_group_id and (not g.is_private or g.created_by=actor)
    where m.property_id = property.id and (not m.is_private or m.created_by = actor);
    return jsonb_build_object('pins', result, 'capabilities', jsonb_build_object(
      'can_use_pin_icons', farm_watch.can_use_map_pin_icons_v1(actor), 'can_manage_agriculture',can_manage));
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
    if p_icon is not null and p_icon not in ('pin','dot','deerstand','water_pump','container','trail_camera','gate','bonfire','crop','corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand','sprout','sapling','ear_of_corn','wheat','blackberry','acorn') then
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
  if not can_manage and (p_specialized_views is not null or p_agriculture is not null or p_set_group or p_group_id is not null) then
    raise exception 'not found' using errcode = '42501';
  end if;
  if p_action in ('create','update') and p_set_group and p_group_id is not null then
    -- Lock before the pin write so declassification/privacy updates cannot race the check.
    perform 1 from farm_watch.saved_map_areas_v1 g
      where g.id=p_group_id and g.property_id=property.id and farm_watch.is_growing_area(g.agriculture)
        and (not g.is_private or g.created_by=actor) for share;
    if not found then raise exception 'invalid planting group' using errcode = '22023'; end if;
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
    insert into farm_watch.property_map_pins_v1(property_id,created_by,title,notes,geometry,color,icon,category,is_private,camera_bearing_deg,camera_range_m,camera_fov_deg,specialized_views,agriculture,planting_group_id)
    values(property.id,actor,btrim(p_title),nullif(p_notes,''),point,lower(coalesce(p_color,'#ffd27e')),coalesce(p_icon,'pin'),coalesce(p_category,'auto'),coalesce(p_is_private,false),
      case when p_icon='trail_camera' then p_camera_bearing_deg end,
      case when p_icon='trail_camera' and p_camera_bearing_deg is not null then coalesce(p_camera_range_m,24.384) end,
      case when p_icon='trail_camera' and p_camera_bearing_deg is not null then coalesce(p_camera_fov_deg,40) end,
      p_specialized_views,nullif(p_agriculture,'{}'::jsonb),case when p_set_group then p_group_id end) returning * into pin;
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
      ,specialized_views=coalesce(p_specialized_views,pin.specialized_views)
      ,agriculture=case when p_agriculture is null then pin.agriculture else nullif(p_agriculture,'{}'::jsonb) end
      ,planting_group_id=case when p_set_group then p_group_id when p_agriculture='{}'::jsonb then null else pin.planting_group_id end
    where id = pin.id returning * into pin;
  end if;
  return jsonb_build_object('pin', jsonb_build_object(
    'photo_count',(select count(*) from farm_watch.map_pin_photos_v1 ph where ph.pin_id=pin.id),
    'specialized_views',pin.specialized_views,'agriculture',pin.agriculture,
    'planting_group_id',(select g.id from farm_watch.saved_map_areas_v1 g
      where g.id=pin.planting_group_id and (not g.is_private or g.created_by=actor)),
    'id',pin.id, 'title',pin.title, 'notes',pin.notes, 'color',pin.color, 'icon',pin.icon, 'category',pin.category, 'is_private',pin.is_private,
    'camera_bearing_deg',pin.camera_bearing_deg,
    'camera_range_m',case when pin.icon='trail_camera' then coalesce(pin.camera_range_m,24.384) end,
    'camera_fov_deg',case when pin.icon='trail_camera' then coalesce(pin.camera_fov_deg,40) end,
    'longitude',extensions.st_x(pin.geometry), 'latitude',extensions.st_y(pin.geometry),
    'created_at',pin.created_at, 'updated_at',pin.updated_at, 'revision',pin.revision,
    'can_edit',true, 'creator_label','You'));
end $$;

create or replace function public.farm_watch_map_pins_v1(
  p_property_slug text, p_action text,
  p_pin_id uuid default null, p_expected_revision integer default null,
  p_title text default null, p_notes text default null,
  p_longitude double precision default null, p_latitude double precision default null,
  p_color text default null, p_icon text default null, p_category text default null,
  p_camera_bearing_deg integer default null, p_camera_range_m double precision default null, p_camera_fov_deg integer default null,
  p_is_private boolean default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select public.farm_watch_map_pins_v2(p_property_slug,p_action,p_pin_id,p_expected_revision,
    p_title,p_notes,p_longitude,p_latitude,p_color,p_icon,p_category,
    p_camera_bearing_deg,p_camera_range_m,p_camera_fov_deg,p_is_private)
$$;

revoke all on function public.farm_watch_map_pins_v2(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean,text[],jsonb,uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_map_pins_v2(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean,text[],jsonb,uuid,boolean)
  to authenticated;

-- Check agricultural edit access before preparing or mutating a photo.
create or replace function public.farm_watch_pin_photos_v1(p_property_slug text,p_pin_id uuid,p_action text,
 p_photo_id uuid default null,p_expected_revision integer default null,
 p_focal_x integer default null,p_focal_y integer default null)
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
 if p_action in ('prepare','attach','delete','frame') then
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id and created_by=actor
    and (farm_watch.can_manage_agriculture() or (agriculture is null and specialized_views is null)) for update;
 else
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id and (not is_private or created_by=actor);
 end if;
 if pin.id is null then raise exception 'not found' using errcode='42501'; end if;
 if (p_focal_x is null) <> (p_focal_y is null)
  or p_focal_x not between 0 and 100 or p_focal_y not between 0 and 100
  or (p_action='frame' and p_focal_x is null)
  or (p_focal_x is not null and p_action not in ('attach','frame')) then
  raise exception 'invalid photo framing' using errcode='22023';
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'width',width,'height',height,'bytes',bytes,'focal_x',focal_x,'focal_y',focal_y) order by created_at,id),'[]') into result
   from farm_watch.map_pin_photos_v1 where pin_id=pin.id;
  return jsonb_build_object('photos',result,'revision',pin.revision);
 elsif p_action='read' then
  select * into photo from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
  return jsonb_build_object('object_path',photo.object_path,'bytes',photo.bytes);
 elsif p_action not in ('prepare','attach','delete','frame') or p_action is null then
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
  insert into farm_watch.map_pin_photos_v1(id,pin_id,object_path,width,height,bytes,focal_x,focal_y)
   values(p_photo_id,pin.id,path,(object.user_metadata->>'width')::integer,(object.user_metadata->>'height')::integer,(object.metadata->>'size')::integer,coalesce(p_focal_x,50),coalesce(p_focal_y,50))
   returning * into photo;
 elsif p_action='frame' then
  update farm_watch.map_pin_photos_v1 set focal_x=p_focal_x,focal_y=p_focal_y
   where id=p_photo_id and pin_id=pin.id returning * into photo;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
 else
  delete from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id returning * into photo;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
 end if;
 -- Serialize attachment changes with normal edits/deletion and the same guard.
 update farm_watch.property_map_pins_v1 set title=title where id=pin.id returning * into pin;
 return jsonb_build_object('revision',pin.revision,'photo',jsonb_build_object('id',photo.id,'width',photo.width,'height',photo.height,'bytes',photo.bytes,'focal_x',photo.focal_x,'focal_y',photo.focal_y));
end $$;

revoke all on function farm_watch.valid_specialized_views(text[]), farm_watch.valid_agriculture(jsonb,boolean),
  farm_watch.is_growing_area(jsonb), farm_watch.can_manage_agriculture(),
  farm_watch.guard_agricultural_annotation(), farm_watch.detach_declassified_plantings()
  from public,anon,authenticated,service_role;

notify pgrst, 'reload schema';
commit;
