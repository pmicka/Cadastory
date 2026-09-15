-- Make responsible-party opportunity coverage provider-configured instead of
-- hard-coded in the seeder. Jefferson can safely resolve ownership for
-- construction, exterior-cleaning, and roof-lifecycle sites because all three
-- are site-address/location candidates. Ownership remains responsibility
-- evidence only; buyer/property-manager/operator authority is not implied.

update research.responsible_party_source_profiles
set attributes = jsonb_set(
      coalesce(attributes,'{}'::jsonb),
      '{eligible_source_kinds}',
      '["construction_window","exterior_cleaning","roof_lifecycle"]'::jsonb,
      true
    ),
    updated_at = now()
where profile_key='ky_jefferson_pva_lrsn';

do $$
declare
  v_def text;
  v_old text := 'q.source_kind in (''construction_window'',''exterior_cleaning'')';
  v_new text := 'pg_catalog.jsonb_exists(coalesce(pg_catalog.jsonb_extract_path(p.attributes,''eligible_source_kinds''),''[]''::jsonb),q.source_kind)';
  v_matches integer;
begin
  select pg_get_functiondef('public.internal_seed_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
  into v_def;

  v_matches := (length(v_def)-length(replace(v_def,v_old,''))) / nullif(length(v_old),0);
  if v_matches <> 2 then
    raise exception 'expected exactly two responsible-party source-kind predicates, found %',v_matches;
  end if;

  v_def := replace(v_def,v_old,v_new);
  if v_def not like '%eligible_source_kinds%' or v_def like '%q.source_kind in (''construction_window'',''exterior_cleaning'')%' then
    raise exception 'responsible-party source-kind configuration patch did not apply cleanly';
  end if;
  execute v_def;
end
$$;

do $$
declare v_kinds jsonb;
begin
  select pg_catalog.jsonb_extract_path(attributes,'eligible_source_kinds')
  into v_kinds
  from research.responsible_party_source_profiles
  where profile_key='ky_jefferson_pva_lrsn';

  if v_kinds is null
     or not pg_catalog.jsonb_exists(v_kinds,'construction_window')
     or not pg_catalog.jsonb_exists(v_kinds,'exterior_cleaning')
     or not pg_catalog.jsonb_exists(v_kinds,'roof_lifecycle') then
    raise exception 'Jefferson responsible-party source-kind configuration regression';
  end if;
end
$$;
