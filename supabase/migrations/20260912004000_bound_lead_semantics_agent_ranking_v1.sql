create or replace function public.scout_find_connection_opportunities(
  p_connection_id uuid,
  p_service_slug text,
  p_county_name text default null,
  p_state_code text default null,
  p_center_lat double precision default null,
  p_center_lon double precision default null,
  p_radius_miles numeric default null,
  p_jurisdiction_code text default null,
  p_time_sensitive boolean default false,
  p_require_contact boolean default false,
  p_fit_filter text default null,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_org uuid;
  v_guard jsonb;
  v_results jsonb;
begin
  if p_service_slug is null then
    raise exception 'service_slug is required for the external-agent opportunity surface';
  end if;

  select organization_id into v_org
  from commerce.provider_agent_connections
  where id=p_connection_id
    and status='active'
    and (expires_at is null or expires_at>now());

  if not found then raise exception 'active Scout connection not found'; end if;
  if v_org is null then
    return jsonb_build_object(
      'allowed',false,
      'reason','onboarding_required',
      'onboarding',public.scout_get_connection_onboarding_status(p_connection_id)
    );
  end if;

  v_guard:=public.scout_guard_opportunity_request(
    p_connection_id,
    array[p_service_slug],
    jsonb_build_object('state_code',p_state_code,'jurisdiction_code',p_jurisdiction_code)
  );
  if not coalesce((v_guard->>'allowed')::boolean,false) then return v_guard; end if;

  select coalesce(jsonb_agg(r.item order by r.lead_confidence_rank desc, r.buyer_readiness_rank desc, r.evidence_confidence desc nulls last, r.candidate_key),'[]'::jsonb)
  into v_results
  from (
    select
      x.candidate_key,
      l.lead_confidence_rank,
      case l.buyer_readiness
        when 'buyer_ready' then 3
        when 'organization_identified' then 2
        when 'route_or_role_only' then 1
        else 0
      end as buyer_readiness_rank,
      l.evidence_confidence,
      to_jsonb(x)
      || jsonb_build_object('opportunity',scout.get_opportunity_spine_projection_v2(x.candidate_key))
      || jsonb_build_object(
        'decision_context',
        scout.compose_opportunity_pursuit_context(
          x.candidate_key,
          jsonb_build_object(
            'overall_fit_status',x.overall_fit_status,
            'service_fits',coalesce(x.service_fits,'[]'::jsonb),
            'interpretation',coalesce(x.fit_limits,'{}'::jsonb)
          )
        )
      ) as item
    from scout.find_opportunities_for_operator(
      v_org,p_service_slug,p_county_name,p_state_code,p_center_lat,p_center_lon,p_radius_miles,
      p_jurisdiction_code,p_time_sensitive,p_require_contact,p_fit_filter,
      least(greatest(coalesce(p_limit,10),1),25)
    ) x
    join scout.v_opportunity_lead_semantics_v1 l using (candidate_key)
    order by
      l.lead_confidence_rank desc,
      case l.buyer_readiness
        when 'buyer_ready' then 3
        when 'organization_identified' then 2
        when 'route_or_role_only' then 1
        else 0
      end desc,
      l.evidence_confidence desc nulls last,
      x.candidate_key
    limit least(greatest(coalesce(p_limit,10),1),25)
  ) r;

  return jsonb_build_object(
    'allowed',true,
    'service_slug',p_service_slug,
    'results',v_results,
    'result_count',jsonb_array_length(v_results),
    'opportunity_contract_version','2.0',
    'lead_semantics_contract_version','lead_semantics_v1',
    'decision_context_contract',jsonb_build_object(
      'purpose','Explain why this target, why now, commercial scale, buyer/contactability, operator fit, premium-target context when independently supported, counter-evidence/cool-downs, pursuit friction, recurrence, unknowns, and one next move.',
      'authoritative_surface','Each result.opportunity is the normalized Scout opportunity spine projection. Its lead_assessment separates evidence reliability from lead confidence, actionability, and buyer readiness.',
      'ranking_guardrail','Do not interpret signal.confidence or signal.evidence_confidence as conversion probability. Lead confidence is categorical and must remain distinct from evidence confidence. Market-context-only records are not immediate jobs.'
    )
  );
end
$function$;
