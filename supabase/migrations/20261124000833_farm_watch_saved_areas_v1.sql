begin;

create table farm_watch.saved_map_areas_v1 (
  id uuid primary key,
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 100),
  outline jsonb not null,
  color text not null check (color ~ '^#[0-9a-f]{6}$'),
  category text not null check (category in ('general','hunting','farming-orchard')),
  is_private boolean not null,
  revision integer not null default 1
);
create index saved_map_areas_property_idx on farm_watch.saved_map_areas_v1(property_id);
create index saved_map_areas_creator_idx on farm_watch.saved_map_areas_v1(created_by);
alter table farm_watch.saved_map_areas_v1 enable row level security;
revoke all on farm_watch.saved_map_areas_v1 from public, anon, authenticated;

-- Mirror the property map pin authorization contract. This RPC is the sole
-- browser entry point to the private table and checks the actor on every call.
create function public.farm_watch_saved_areas_v1(
  p_property_slug text,
  p_action text,
  p_id uuid default null,
  p_revision integer default null,
  p_title text default null,
  p_outline jsonb default null,
  p_color text default null,
  p_category text default null,
  p_is_private boolean default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  selected_property uuid;
  area farm_watch.saved_map_areas_v1%rowtype;
  vertex jsonb;
  boundary extensions.geometry;
  result jsonb;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists (select 1 from auth.users where id = actor)
    or not public.farm_watch_authorize_user_v1_internal(actor)
    or coalesce(public.farm_watch_get_account_role_v1_internal(actor),'') not in ('owner','admin','viewer') then
    raise exception 'not found' using errcode = '42501';
  end if;
  select id into selected_property from farm_watch.properties where slug=p_property_slug and status='active';
  if selected_property is null then raise exception 'not found' using errcode = '42501'; end if;

  if p_action = 'list' then
    select coalesce(jsonb_agg(
      (to_jsonb(m) - 'created_by' - 'property_id') || jsonb_build_object('can_edit',m.created_by=actor)
      order by lower(m.title), m.id
    ),'[]'::jsonb) into result
    from farm_watch.saved_map_areas_v1 m
    where m.property_id=selected_property and (not m.is_private or m.created_by=actor);
    return jsonb_build_object('areas',result);
  end if;
  if p_action is null or p_action not in ('create','update','delete') or p_id is null then
    raise exception 'invalid action or area ID' using errcode = '22023';
  end if;
  if p_action <> 'delete' then
    if p_title is null or char_length(btrim(p_title)) not between 1 and 100 or p_title !~ '[^[:space:]]'
      or p_color is null or char_length(p_color)<>7 or p_color !~ '^#[0-9A-Fa-f]{6}$'
      or p_category is null or p_category not in ('general','hunting','farming-orchard')
      or p_is_private is null or jsonb_typeof(p_outline) is distinct from 'array' then
      raise exception 'invalid area settings' using errcode = '22023';
    end if;
    if jsonb_array_length(p_outline) not between 3 and 200 then
      raise exception 'invalid outline size' using errcode = '22023';
    end if;
    for vertex in select value from jsonb_array_elements(p_outline) loop
      if jsonb_typeof(vertex) is distinct from 'array' then
        raise exception 'invalid outline point' using errcode = '22023';
      end if;
      if jsonb_array_length(vertex)<>2 or jsonb_typeof(vertex->0)<>'number' or jsonb_typeof(vertex->1)<>'number'
        or (vertex->>0)::numeric not between -180 and 180 or (vertex->>1)::numeric not between -90 and 90 then
        raise exception 'invalid outline point' using errcode = '22023';
      end if;
    end loop;
    boundary := extensions.st_geomfromgeojson(jsonb_build_object('type','Polygon',
      'coordinates',jsonb_build_array(p_outline || jsonb_build_array(p_outline->0))));
    if not extensions.st_isvalid(boundary) or extensions.st_area(boundary)<=0 then
      raise exception 'invalid outline' using errcode = '22023';
    end if;
  end if;

  if p_action = 'create' then
    perform 1 from farm_watch.properties where id=selected_property for update;
    select * into area from farm_watch.saved_map_areas_v1 where id=p_id;
    if found then
      if area.created_by<>actor or area.property_id<>selected_property then
        raise exception 'not found' using errcode = '42501';
      end if;
      if area.revision<>1 or area.title<>btrim(p_title) or area.outline<>p_outline or area.color<>lower(p_color)
        or area.category<>p_category or area.is_private<>p_is_private then
        raise exception 'area changed; reload' using errcode = 'PT409';
      end if;
    else
      if (select count(*) from farm_watch.saved_map_areas_v1 where property_id=selected_property)>=500 then
        raise exception 'property area limit reached' using errcode = '54000';
      end if;
      insert into farm_watch.saved_map_areas_v1(id,property_id,created_by,title,outline,color,category,is_private)
      values(p_id,selected_property,actor,btrim(p_title),p_outline,lower(p_color),p_category,p_is_private)
      returning * into area;
    end if;
  else
    select * into area from farm_watch.saved_map_areas_v1
    where id=p_id and property_id=selected_property and created_by=actor for update;
    if not found then raise exception 'not found' using errcode = '42501'; end if;
    if p_revision is distinct from area.revision then raise exception 'area changed; reload' using errcode = 'PT409'; end if;
    if p_action='delete' then
      delete from farm_watch.saved_map_areas_v1 where id=area.id;
      return jsonb_build_object('deleted',true);
    end if;
    update farm_watch.saved_map_areas_v1
    set title=btrim(p_title),outline=p_outline,color=lower(p_color),category=p_category,is_private=p_is_private,revision=revision+1
    where id=area.id returning * into area;
  end if;
  return jsonb_build_object('area',(to_jsonb(area) - 'created_by' - 'property_id') || jsonb_build_object('can_edit',true));
end;
$$;
revoke all on function public.farm_watch_saved_areas_v1(text,text,uuid,integer,text,jsonb,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_saved_areas_v1(text,text,uuid,integer,text,jsonb,text,text,boolean) to authenticated;

commit;
