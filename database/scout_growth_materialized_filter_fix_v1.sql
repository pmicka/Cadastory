-- Scout external-agent Explore Growth performance repair.
-- The filtered business-need signal set is referenced by both aggregation and
-- per-service sample extraction. Force one bounded materialization so the
-- county spatial filter is not re-executed for each downstream service.

do $$
declare
  v_oid oid;
  v_def text;
  v_new text;
begin
  select p.oid, pg_get_functiondef(p.oid)
    into v_oid, v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'scout'
    and p.proname = 'find_growth_options'
    and pg_get_function_identity_arguments(p.oid) = 'p_organization_id uuid, p_budget numeric, p_county_name text, p_state_code text, p_center_lat double precision, p_center_lon double precision, p_radius_miles numeric, p_jurisdiction_code text, p_include_existing boolean, p_limit integer';

  if v_oid is null then
    raise exception 'scout.find_growth_options target function not found';
  end if;

  if position('filtered as (' in v_def) = 0 then
    if position('filtered as materialized (' in v_def) > 0 then
      return;
    end if;
    raise exception 'scout.find_growth_options source shape changed; refusing unsafe rewrite';
  end if;

  v_new := replace(v_def, 'filtered as (', 'filtered as materialized (');
  execute v_new;
end
$$;
