begin;

-- Presentation metadata only; existing pins keep the original gold.
alter table farm_watch.property_map_pins_v1
  add column color text not null default '#ffd27e'
  constraint property_map_pins_v1_color_check check (char_length(color)=7 and color ~ '^#[0-9a-f]{6}$');

-- Replace the signature atomically, avoiding ambiguous defaulted RPC overloads.
-- Older callers omit p_color: creates use gold and updates preserve stored color.
drop function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision);

create function public.farm_watch_map_pins_v1(
  p_property_slug text, p_action text,
  p_pin_id uuid default null, p_expected_revision integer default null,
  p_title text default null, p_notes text default null,
  p_longitude double precision default null, p_latitude double precision default null,
  p_color text default null
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
      'id', m.id, 'title', m.title, 'notes', m.notes, 'color', m.color,
      'longitude', extensions.st_x(m.geometry), 'latitude', extensions.st_y(m.geometry),
      'created_at', m.created_at, 'updated_at', m.updated_at, 'revision', m.revision,
      'can_edit', m.created_by = actor,
      'creator_label', case when m.created_by = actor then 'You' else 'Property member' end
    ) order by m.created_at, m.id), '[]'::jsonb) into result
    from farm_watch.property_map_pins_v1 m where m.property_id = property.id;
    return jsonb_build_object('pins', result);
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
    insert into farm_watch.property_map_pins_v1(property_id,created_by,title,notes,geometry,color)
    values(property.id,actor,btrim(p_title),nullif(p_notes,''),point,lower(coalesce(p_color,'#ffd27e'))) returning * into pin;
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
    update farm_watch.property_map_pins_v1 set title = btrim(p_title),notes = nullif(p_notes,''),geometry = point,
      color = coalesce(lower(p_color),pin.color)
    where id = pin.id returning * into pin;
  end if;
  return jsonb_build_object('pin', jsonb_build_object(
    'id',pin.id, 'title',pin.title, 'notes',pin.notes, 'color',pin.color,
    'longitude',extensions.st_x(pin.geometry), 'latitude',extensions.st_y(pin.geometry),
    'created_at',pin.created_at, 'updated_at',pin.updated_at, 'revision',pin.revision,
    'can_edit',true, 'creator_label','You'));
end $$;
revoke all on function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text)
from public, anon, authenticated, service_role;
grant execute on function public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text)
to authenticated;

notify pgrst, 'reload schema';
commit;
