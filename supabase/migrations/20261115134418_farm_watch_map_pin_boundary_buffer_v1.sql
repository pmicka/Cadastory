begin;

-- Change only the annotation placement guard. Existing pins, privacy, roles,
-- grants, RPC signatures, property geometry and evidence products are untouched.
create or replace function farm_watch.guard_map_pin_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
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

commit;
