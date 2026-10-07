-- Remove the full card projection call from the address resolver hot path.
-- The resolver returns bounded candidate summaries; card hydration remains a separate routed step.

begin;


create or replace function public.scout_resolve_connection_site_opportunities_v1(
  p_connection_id uuid,
  p_address text,
  p_city text,
  p_state_code text,
  p_limit integer default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_conn commerce.provider_agent_connections%rowtype;
  v_address text := nullif(btrim(coalesce(p_address,'')),'');
  v_city text := nullif(btrim(coalesce(p_city,'')),'');
  v_state_code text := upper(nullif(btrim(coalesce(p_state_code,'')),''));
  v_address_key text;
  v_city_key text;
  v_limit integer := least(greatest(coalesce(p_limit,5),1),5);
  v_site_count integer := 0;
  v_site_key text;
  v_site_options jsonb := '[]'::jsonb;
  v_service_slugs text[] := '{}';
  v_guard jsonb;
  v_results jsonb := '[]'::jsonb;
  v_primary_candidates jsonb := '[]'::jsonb;
  v_related_candidates jsonb := '[]'::jsonb;
  v_resolved_site jsonb := null;
begin
  select *
  into v_conn
  from commerce.provider_agent_connections
  where id = p_connection_id
    and status = 'active'
    and (expires_at is null or expires_at > now());

  if not found then
    raise exception 'active Scout connection not found';
  end if;

  if v_conn.organization_id is null then
    return jsonb_build_object(
      'allowed', false,
      'resolution_status', 'not_found',
      'reason', 'onboarding_required',
      'onboarding', public.scout_get_connection_onboarding_status(p_connection_id)
    );
  end if;

  if v_address is null or length(v_address) > 300 then
    raise exception 'address is required and must be 300 characters or fewer';
  end if;
  if v_city is null or length(v_city) > 120 then
    raise exception 'city is required and must be 120 characters or fewer';
  end if;
  if v_state_code is null or v_state_code !~ '^[A-Z]{2}$' then
    raise exception 'state_code must be a two-letter state code';
  end if;

  v_address_key := scout.normalize_address_key_v2(v_address);
  v_city_key := regexp_replace(lower(v_city), '[^a-z0-9]+', '', 'g');
  if v_address_key = '' or v_city_key = '' then
    raise exception 'address and city must contain searchable text';
  end if;

  with authority_matches as (
    select
      s.candidate_key,
      coalesce(s.canonical_asset_id::text, 'candidate:' || s.candidate_key) as site_key,
      s.canonical_asset_id,
      s.display_name,
      s.target_name,
      s.target_class,
      s.state_code,
      s.county_name,
      nullif(btrim(s.details->>'city'),'') as city,
      coalesce(nullif(btrim(s.details->>'address'),''), nullif(btrim(e.site_address_text),''), s.display_name) as display_address,
      e.site_address_text as matched_address,
      e.evidence_class,
      e.confidence as resolution_confidence,
      'authoritative_site_address_alias'::text as match_basis,
      1 as match_rank,
      s.service_slugs
    from scout.opportunity_responsible_party_evidence e
    join scout.opportunity_search_spine s using (candidate_key)
    where s.state_code = v_state_code
      and coalesce(s.global_suppressed,false) = false
      and (s.expires_at is null or s.expires_at >= now())
      and e.evidence_class = 'authoritative_record'
      and scout.normalize_address_key_v2(e.site_address_text) = v_address_key
      and regexp_replace(lower(coalesce(s.details->>'city','')), '[^a-z0-9]+', '', 'g') = v_city_key
  ),
  canonical_matches as (
    select
      s.candidate_key,
      coalesce(s.canonical_asset_id::text, 'candidate:' || s.candidate_key) as site_key,
      s.canonical_asset_id,
      s.display_name,
      s.target_name,
      s.target_class,
      s.state_code,
      s.county_name,
      nullif(btrim(s.details->>'city'),'') as city,
      coalesce(nullif(btrim(s.details->>'address'),''), s.display_name) as display_address,
      nullif(btrim(s.details->>'address'),'') as matched_address,
      'spine_address'::text as evidence_class,
      s.confidence as resolution_confidence,
      'canonical_spine_address'::text as match_basis,
      2 as match_rank,
      s.service_slugs
    from scout.opportunity_search_spine s
    where s.state_code = v_state_code
      and coalesce(s.global_suppressed,false) = false
      and (s.expires_at is null or s.expires_at >= now())
      and scout.normalize_address_key_v2(s.details->>'address') = v_address_key
      and regexp_replace(lower(coalesce(s.details->>'city','')), '[^a-z0-9]+', '', 'g') = v_city_key
  ),
  deduped_matches as (
    select distinct on (candidate_key)
      *
    from (
      select * from authority_matches
      union all
      select * from canonical_matches
    ) m
    order by candidate_key, match_rank, resolution_confidence desc nulls last
  ),
  site_rollup as (
    select
      site_key,
      (array_agg(canonical_asset_id) filter (where canonical_asset_id is not null))[1] as canonical_asset_id,
      min(match_rank) as best_match_rank,
      max(resolution_confidence) as resolution_confidence,
      max(display_name) as display_name,
      max(target_name) as target_name,
      max(target_class) as target_class,
      max(display_address) as display_address,
      max(city) as city,
      max(state_code) as state_code,
      max(county_name) as county_name,
      max(matched_address) as matched_address,
      (array_agg(match_basis order by match_rank, resolution_confidence desc nulls last))[1] as match_basis,
      (array_agg(evidence_class order by match_rank, resolution_confidence desc nulls last))[1] as evidence_class,
      count(*) as matched_candidate_count,
      array_agg(distinct svc) filter (where svc is not null) as service_slugs
    from deduped_matches m
    left join lateral unnest(coalesce(m.service_slugs,'{}'::text[])) svc on true
    group by site_key
  )
  select
    count(*)::integer,
    min(site_key),
    coalesce(jsonb_agg(jsonb_build_object(
      'display_address', display_address,
      'city', city,
      'state_code', state_code,
      'county_name', county_name,
      'canonical_asset_id', canonical_asset_id,
      'display_name', display_name,
      'target_name', target_name,
      'target_class', target_class,
      'match_basis', match_basis,
      'evidence_class', evidence_class,
      'resolution_confidence', resolution_confidence,
      'matched_candidate_count', matched_candidate_count,
      'service_slugs', coalesce(service_slugs,'{}'::text[])
    ) order by best_match_rank, resolution_confidence desc nulls last, display_address), '[]'::jsonb),
    coalesce((
      select array_agg(distinct svc) filter (where svc is not null)
      from site_rollup sr
      cross join lateral unnest(coalesce(sr.service_slugs,'{}'::text[])) svc
    ), '{}')
  into v_site_count, v_site_key, v_site_options, v_service_slugs
  from site_rollup;

  if v_site_count = 0 then
    return jsonb_build_object(
      'allowed', true,
      'resolution_status', 'not_found',
      'query', jsonb_build_object(
        'address', v_address,
        'city', v_city,
        'state_code', v_state_code,
        'normalized_address_key', v_address_key
      ),
      'guardrails', jsonb_build_array(
        'No exact authoritative alias or canonical Scout address matched the supplied city/state.',
        'Scout did not fall back to nearby opportunities or external geocoding.'
      )
    );
  end if;

  if cardinality(v_service_slugs) > 0 then
    v_guard := public.scout_guard_opportunity_request(
      p_connection_id,
      v_service_slugs,
      jsonb_build_object('state_code', v_state_code)
    );
    if not coalesce((v_guard->>'allowed')::boolean, false) then
      return v_guard || jsonb_build_object(
        'resolution_status', 'not_found',
        'query', jsonb_build_object(
          'address', v_address,
          'city', v_city,
          'state_code', v_state_code,
          'normalized_address_key', v_address_key
        ),
        'guardrails', jsonb_build_array(
          'Opportunity access gate did not allow this address resolution result.',
          'Scout did not reconstruct blocked opportunity sets.'
        )
      );
    end if;
  end if;

  if v_site_count > 1 then
    return jsonb_build_object(
      'allowed', true,
      'resolution_status', 'needs_confirmation',
      'query', jsonb_build_object(
        'address', v_address,
        'city', v_city,
        'state_code', v_state_code,
        'normalized_address_key', v_address_key
      ),
      'candidate_sites', v_site_options,
      'guardrails', jsonb_build_array(
        'More than one Scout site matched the supplied address key within the city/state constraint.',
        'No candidate_key was selected; ask the operator to confirm the intended site.'
      )
    );
  end if;

  v_resolved_site := v_site_options->0;

  with site_opportunities as (
    select s.*
    from scout.opportunity_search_spine s
    where coalesce(s.global_suppressed,false) = false
      and (s.expires_at is null or s.expires_at >= now())
      and (
        (left(v_site_key, 10) = 'candidate:' and s.candidate_key = substring(v_site_key from 11))
        or
        (left(v_site_key, 10) <> 'candidate:' and s.canonical_asset_id::text = v_site_key)
      )
  ),
  primary_rows as (
    select
      s.*,
      row_number() over (
        order by
          case when s.derived_from_candidate_key is null then 0 else 1 end,
          case when s.source_kind = 'exterior_cleaning' then 0 else 1 end,
          s.confidence desc nulls last,
          s.candidate_key
      ) as primary_rank
    from site_opportunities s
    where s.derived_from_candidate_key is null
  ),
  related_rows as (
    select
      s.*,
      row_number() over (
        order by
          case when s.source_kind = 'event_detailing' then 0 else 1 end,
          s.event_start nulls last,
          s.confidence desc nulls last,
          s.candidate_key
      ) as related_rank
    from site_opportunities s
    where s.derived_from_candidate_key is not null
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'candidate_key', p.candidate_key,
      'candidate_role', 'primary_base',
      'is_derived', false,
      'source_kind', p.source_kind,
      'signal_kind', p.signal_kind,
      'service_slugs', p.service_slugs,
      'primary_service_slug', p.primary_service_slug,
      'canonical_asset_id', p.canonical_asset_id,
      'display_name', p.display_name,
      'target_name', p.target_name,
      'target_class', p.target_class,
      'confidence', p.confidence,
      'time_sensitive', p.time_sensitive,
      'resolution_basis', jsonb_build_object(
        'site_match_basis', v_resolved_site->>'match_basis',
        'evidence_class', v_resolved_site->>'evidence_class',
        'resolution_confidence', v_resolved_site->'resolution_confidence'
      )
    ) order by p.primary_rank), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'candidate_key', p.candidate_key,
      'candidate_role', 'primary_base',
      'is_derived', false,
      'source_kind', p.source_kind,
      'signal_kind', p.signal_kind,
      'service_slugs', p.service_slugs,
      'primary_service_slug', p.primary_service_slug,
      'canonical_asset_id', p.canonical_asset_id,
      'display_name', p.display_name,
      'target_name', p.target_name,
      'target_class', p.target_class,
      'confidence', p.confidence,
      'time_sensitive', p.time_sensitive,
      'resolution_basis', jsonb_build_object(
        'site_match_basis', v_resolved_site->>'match_basis',
        'evidence_class', v_resolved_site->>'evidence_class',
        'resolution_confidence', v_resolved_site->'resolution_confidence'
      )
    ) order by p.primary_rank), '[]'::jsonb)
  into v_primary_candidates, v_results
  from primary_rows p
  where p.primary_rank <= v_limit;

  with site_opportunities as (
    select s.*
    from scout.opportunity_search_spine s
    where coalesce(s.global_suppressed,false) = false
      and (s.expires_at is null or s.expires_at >= now())
      and (
        (left(v_site_key, 10) = 'candidate:' and s.candidate_key = substring(v_site_key from 11))
        or
        (left(v_site_key, 10) <> 'candidate:' and s.canonical_asset_id::text = v_site_key)
      )
  ),
  related_rows as (
    select
      s.*,
      row_number() over (
        order by
          case when s.source_kind = 'event_detailing' then 0 else 1 end,
          s.event_start nulls last,
          s.confidence desc nulls last,
          s.candidate_key
      ) as related_rank
    from site_opportunities s
    where s.derived_from_candidate_key is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'candidate_key', r.candidate_key,
      'candidate_role', 'related_derived',
      'is_derived', true,
      'source_kind', r.source_kind,
      'signal_kind', r.signal_kind,
      'service_slugs', r.service_slugs,
      'primary_service_slug', r.primary_service_slug,
      'canonical_asset_id', r.canonical_asset_id,
      'derived_from_candidate_key', r.derived_from_candidate_key,
      'derivation_kind', r.derivation_kind,
      'display_name', r.display_name,
      'event_title', r.event_title,
      'event_start', r.event_start,
      'confidence', r.confidence,
      'time_sensitive', r.time_sensitive
    ) order by r.related_rank), '[]'::jsonb)
  into v_related_candidates
  from related_rows r
  where r.related_rank <= 5;

  return jsonb_build_object(
    'allowed', true,
    'resolution_status', 'resolved',
    'query', jsonb_build_object(
      'address', v_address,
      'city', v_city,
      'state_code', v_state_code,
      'normalized_address_key', v_address_key
    ),
    'resolved_site', v_resolved_site,
    'candidate_key', v_primary_candidates #>> '{0,candidate_key}',
    'primary_candidates', v_primary_candidates,
    'related_candidates', v_related_candidates,
    'results', v_results,
    'result_count', jsonb_array_length(v_results),
    'opportunity_contract_version', '2.0',
    'base_vs_derived_policy', jsonb_build_object(
      'primary_candidates', 'Only non-derived/base opportunity records are primary.',
      'related_candidates', 'Derived timing/event records remain subordinate and never replace the base opportunity.'
    ),
    'guardrails', jsonb_build_array(
      'Resolution uses exact authoritative aliases or exact canonical Scout address keys constrained by city/state.',
      'No external geocoder, nearby search, or media-matching path was used.',
      'Ambiguous address matches fail closed to needs_confirmation.'
    )
  );
end
$function$;

comment on function public.scout_resolve_connection_site_opportunities_v1(uuid,text,text,text,integer) is
  'Read-only exact site-address resolver for normal Scout MCP: street address + city + state -> one canonical Scout site -> base opportunity candidate(s), with derived records subordinate.';

revoke all on function public.scout_resolve_connection_site_opportunities_v1(uuid,text,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.scout_resolve_connection_site_opportunities_v1(uuid,text,text,text,integer)
  to service_role;

commit;


