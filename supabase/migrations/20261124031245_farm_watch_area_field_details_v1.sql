begin;

alter table farm_watch.saved_map_areas_v1
  add column notes text not null default '' check (char_length(notes) <= 2000);

-- Keep the bounded image payload off the map's area list and behind the area's
-- authorization. Row deletion also deletes the attachments in the same transaction.
create table farm_watch.saved_map_area_photos_v1 (
  area_id uuid primary key references farm_watch.saved_map_areas_v1(id) on delete cascade,
  photos jsonb not null
);
alter table farm_watch.saved_map_area_photos_v1 enable row level security;
revoke all on farm_watch.saved_map_area_photos_v1 from public, anon, authenticated;

create function public.farm_watch_saved_areas_v2(
  p_property_slug text,
  p_action text,
  p_id uuid default null,
  p_revision integer default null,
  p_title text default null,
  p_outline jsonb default null,
  p_color text default null,
  p_category text default null,
  p_is_private boolean default null,
  p_notes text default null,
  p_photos jsonb default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  result jsonb;
  existing_photos jsonb;
  photo jsonb;
begin
  if p_action = 'photos' then
    -- Reuse the same membership, property and visibility checks as the area list.
    result := public.farm_watch_saved_areas_v1(p_property_slug, 'list');
    if p_id is null or not exists (
      select 1 from jsonb_array_elements(result->'areas') item
      where item->>'id' = p_id::text
    ) then
      raise exception 'not found' using errcode = '42501';
    end if;
    select coalesce(p.photos,'[]'::jsonb) into existing_photos
    from farm_watch.saved_map_areas_v1 a
    left join farm_watch.saved_map_area_photos_v1 p on p.area_id=a.id
    where a.id=p_id and (not a.is_private or a.created_by=auth.uid());
    if not found then raise exception 'not found' using errcode = '42501'; end if;
    return jsonb_build_object('photos',coalesce(existing_photos,'[]'::jsonb));
  end if;
  if p_action in ('create','update') then
    if char_length(p_notes) > 2000 then
      raise exception 'area notes exceed 2000 characters' using errcode = '22023';
    end if;
    if p_photos is not null then
      if jsonb_typeof(p_photos) <> 'array' then
        raise exception 'invalid area photos' using errcode = '22023';
      end if;
      if jsonb_array_length(p_photos) > 4 then
        raise exception 'up to four area photos are allowed' using errcode = '22023';
      end if;
      for photo in select value from jsonb_array_elements(p_photos) loop
        if jsonb_typeof(photo) <> 'string' or length(photo#>>'{}') > 349528 or length(photo#>>'{}') % 4 <> 0
          or (photo#>>'{}') !~ '^/9j/[A-Za-z0-9+/]+={0,2}$' then
          raise exception 'invalid area photo' using errcode = '22023';
        end if;
        if octet_length(decode(photo#>>'{}','base64')) > 262144 then
          raise exception 'area photo exceeds 256 KiB' using errcode = '22023';
        end if;
      end loop;
    end if;
  end if;

  result := public.farm_watch_saved_areas_v1(
    p_property_slug,p_action,p_id,p_revision,p_title,p_outline,p_color,p_category,p_is_private
  );
  if p_action not in ('create','update') then return result; end if;

  if p_action = 'create' then
    select photos into existing_photos from farm_watch.saved_map_area_photos_v1 where area_id=p_id;
    if found and (coalesce(p_notes,'') is distinct from result->'area'->>'notes'
      or coalesce(p_photos,'[]'::jsonb) is distinct from existing_photos) then
      raise exception 'area changed; reload' using errcode = 'PT409';
    end if;
  end if;
  if p_notes is not null then
    update farm_watch.saved_map_areas_v1 set notes=p_notes where id=p_id;
    result := jsonb_set(result,'{area,notes}',to_jsonb(p_notes));
  end if;
  if p_photos is not null or p_action='create' then
    insert into farm_watch.saved_map_area_photos_v1(area_id,photos)
    values(p_id,coalesce(p_photos,'[]'::jsonb))
    on conflict (area_id) do update set photos=excluded.photos;
  end if;
  return result;
end;
$$;

revoke all on function public.farm_watch_saved_areas_v2(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_saved_areas_v2(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb)
  to authenticated;

commit;
