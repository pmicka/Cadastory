-- Scout Explore Growth performance repair, phase 3.
-- Call stable readiness/cost functions directly in the materialized enrichment
-- projection. The one-row CROSS JOIN LATERAL wrappers cause pathological
-- repeated evaluation inside the SQL function plan.

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

  if position('fit.j as fit_json' in v_def) = 0 then
    if position('scout.assess_service_fit(p_organization_id,b.service_slug,p_jurisdiction_code) as fit_json' in v_def) > 0 then
      return;
    end if;
    raise exception 'scout.find_growth_options enrichment shape changed; refusing unsafe rewrite';
  end if;

  v_new := replace(v_def,
    'fit.j as fit_json,\n    cost.j as cost_json,',
    'scout.assess_service_fit(p_organization_id,b.service_slug,p_jurisdiction_code) as fit_json,\n    scout.estimate_service_entry_cost(p_organization_id,b.service_slug,p_budget,5) as cost_json,');

  v_new := replace(v_new,
    '  cross join lateral (select scout.assess_service_fit(p_organization_id,b.service_slug,p_jurisdiction_code) as j) fit\n  cross join lateral (select scout.estimate_service_entry_cost(p_organization_id,b.service_slug,p_budget,5) as j) cost\n',
    '');

  if position('fit.j as fit_json' in v_new) > 0
     or position('cross join lateral (select scout.assess_service_fit' in v_new) > 0
     or position('cross join lateral (select scout.estimate_service_entry_cost' in v_new) > 0 then
    raise exception 'Scout Growth direct-enrichment rewrite did not fully apply';
  end if;

  execute v_new;
end
$$;
