begin;

create or replace function farm_watch.farm_watch_resolve_deer_context_v1_internal(
  p_slug text,
  p_as_of_date date default current_date,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_seasonal jsonb;
  v_diel jsonb;
  v_biological jsonb;
  v_fields jsonb;
  v_seasonal_status text;
  v_diel_status text;
  v_biological_status text;
  v_fields_status text;
  v_status text;
begin
  if p_as_of_date is null then
    raise exception 'deer-context as-of date is required';
  end if;
  if p_at is null then
    raise exception 'deer-context timestamp is required';
  end if;

  v_seasonal := farm_watch.farm_watch_resolve_seasonal_state_v1_internal(p_slug,p_as_of_date);
  v_diel := farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(p_slug,p_as_of_date);
  v_biological := farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(
    p_slug,p_at,'unknown','unknown','unknown','unknown'
  );
  v_fields := farm_watch.farm_watch_resolve_field_phenology_v1_internal(p_slug,p_as_of_date);

  v_seasonal_status := coalesce(v_seasonal->>'status','unavailable');
  v_diel_status := coalesce(v_diel->>'status','unavailable');
  v_biological_status := coalesce(v_biological->>'status','unavailable');
  v_fields_status := coalesce(v_fields->>'status','unavailable');

  v_status := case
    when v_seasonal_status='available'
     and v_diel_status='available'
     and v_biological_status='available'
     and v_fields_status='available'
      then 'available'
    when v_seasonal_status not in ('available','partial')
     and v_diel_status not in ('available','partial')
     and v_biological_status not in ('available','partial')
     and v_fields_status not in ('available','partial')
      then 'unavailable'
    else 'partial'
  end;

  return jsonb_build_object(
    'status',v_status,
    'as_of_date',p_as_of_date,
    'at',p_at,
    'component_status',jsonb_build_object(
      'seasonal_state',v_seasonal_status,
      'diel_photoperiod',v_diel_status,
      'deer_biological_state',v_biological_status,
      'field_phenology',v_fields_status
    ),
    'seasonal_state',v_seasonal,
    'diel_photoperiod',v_diel,
    'deer_biological_state',v_biological,
    'field_phenology',v_fields,
    'interpretation_boundary',
      'Review-only deer context assembled from existing Farm Watch evidence. This response performs no deer-use, movement-rate, attraction, bedding, habitat-quality, hunting-pressure, or management scoring.'
  );
end;
$$;

revoke all on function farm_watch.farm_watch_resolve_deer_context_v1_internal(text,date,timestamptz)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_resolve_deer_context_v1_internal(text,date,timestamptz)
  to postgres,service_role;

create or replace function public.farm_watch_resolve_deer_context_v1_internal(
  p_slug text,
  p_as_of_date date default current_date,
  p_at timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_resolve_deer_context_v1_internal(p_slug,p_as_of_date,p_at);
$$;

revoke all on function public.farm_watch_resolve_deer_context_v1_internal(text,date,timestamptz)
  from public,anon,authenticated;
grant execute on function public.farm_watch_resolve_deer_context_v1_internal(text,date,timestamptz)
  to service_role;

comment on function farm_watch.farm_watch_resolve_deer_context_v1_internal(text,date,timestamptz) is
'Builds a read-only Farm Watch Deer Context review snapshot from existing seasonal, deterministic solar, explicit deer biological, and field vegetation evidence. No persistence, scoring, behavioral inference, or management recommendation is performed.';

commit;
