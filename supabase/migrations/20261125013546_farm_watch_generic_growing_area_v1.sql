begin;

-- Let a Farming & Orchard area qualify as a planting group without inferring a crop type.
create or replace function farm_watch.valid_agriculture(metadata jsonb, is_area boolean)
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
      ('growing_area','food_plot','cover_crop','orchard','garden','crop_field','pasture','habitat_management','turkey_exclusion','other')
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

create or replace function farm_watch.is_growing_area(metadata jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(metadata->>'type' in ('growing_area','food_plot','cover_crop','orchard','garden','crop_field','pasture'),false)
$$;

commit;
