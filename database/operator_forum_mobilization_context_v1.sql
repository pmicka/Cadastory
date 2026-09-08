-- Scout operator-forum mobilization context v1
-- Stores field-knowledge hypotheses with provenance and exposes an internal, inspectable
-- mobilization context without changing public Scout ranking semantics.

create table if not exists research.operator_field_hypotheses (
  hypothesis_slug text primary key,
  claim text not null,
  evidence_basis text not null,
  confidence_status text not null check (confidence_status in ('anecdotal','repeated_anecdotal','corroborated','validated','rejected')),
  testability_status text not null check (testability_status in ('not_testable','proxy_testable','outcome_testable')),
  applicable_services text[] not null default '{}'::text[],
  source_urls jsonb not null default '[]'::jsonb,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into research.operator_field_hypotheses(
  hypothesis_slug, claim, evidence_basis, confidence_status, testability_status,
  applicable_services, source_urls, attributes
)
values (
  'mobilization_efficiency',
  'Travel and mobilization friction materially reduce job profitability, while nearby compatible work and same-buyer asset clusters can improve route economics.',
  'Repeated anecdotal reports from professional drone operator communities; not yet validated against Scout provider outcomes.',
  'repeated_anecdotal',
  'proxy_testable',
  array['construction-progress-imaging','construction-site-inspection','mapping-imaging','roof-inspection','bridge-inspection','water-tower-inspection','telecom-tower-inspection','industrial-asset-inspection','agricultural-imaging','agricultural-crop-scouting'],
  jsonb_build_array(
    'https://commercialdronepilots.com/threads/pricing-construction-projects.3938/',
    'https://mavicpilots.com/threads/thoughts-cold-email-w-previously-recorded-video.136286/'
  ),
  jsonb_build_object(
    'origin','professional_operator_forum_research',
    'interpretation','Use as a transparent ranking hypothesis only; do not treat as conversion truth until provider outcomes exist.',
    'first_test','distance from provider operating base plus local compatible-opportunity and same-buyer density'
  )
)
on conflict (hypothesis_slug) do update
set claim = excluded.claim,
    evidence_basis = excluded.evidence_basis,
    confidence_status = excluded.confidence_status,
    testability_status = excluded.testability_status,
    applicable_services = excluded.applicable_services,
    source_urls = excluded.source_urls,
    attributes = research.operator_field_hypotheses.attributes || excluded.attributes,
    updated_at = now();

create index if not exists opportunity_search_spine_buyer_org_idx
  on scout.opportunity_search_spine(buyer_organization_id)
  where buyer_organization_id is not null;

create or replace function scout.opportunity_mobilization_context_v1(
  p_provider_organization_id uuid,
  p_candidate_key text,
  p_cluster_radius_miles numeric default 15,
  p_account_radius_miles numeric default 50
)
returns table (
  candidate_key text,
  display_name text,
  primary_service_slug text,
  provider_organization_id uuid,
  provider_location_id uuid,
  provider_location_type text,
  provider_location_name text,
  provider_location_city text,
  provider_location_state text,
  base_distance_miles numeric,
  straight_line_roundtrip_lower_bound_miles numeric,
  max_travel_miles numeric,
  within_declared_travel_radius boolean,
  cluster_radius_miles numeric,
  nearby_pushable_count integer,
  nearby_same_service_count integer,
  account_radius_miles numeric,
  nearby_same_buyer_count integer,
  same_buyer_pushable_portfolio_count integer,
  mobilization_signal text,
  evidence_state text,
  hypothesis_slug text,
  formula_version text
)
language sql
stable
security invoker
set search_path = pg_catalog, public, extensions, scout, commerce, research
as $$
with candidate as (
  select s.*
  from scout.opportunity_search_spine s
  where s.candidate_key = p_candidate_key
),
profile as (
  select pp.organization_id, pp.max_travel_miles
  from commerce.provider_profiles pp
  where pp.organization_id = p_provider_organization_id
),
chosen_location as (
  select pl.id,
         pl.organization_id,
         pl.location_type,
         pl.location_name,
         pl.city,
         pl.state_code,
         pl.location::geography as location
  from commerce.provider_locations pl
  cross join candidate c
  where pl.organization_id = p_provider_organization_id
    and pl.location is not null
    and pl.location_type in ('base','base_approximate','shop','branch','branch_approximate','city_centroid')
  order by
    case pl.location_type
      when 'base' then 0 when 'shop' then 0 when 'branch' then 0
      when 'base_approximate' then 1 when 'branch_approximate' then 1
      when 'city_centroid' then 2 else 3 end,
    case when c.location is null then 1 else 0 end,
    case when c.location is null then null else st_distance(c.location, pl.location::geography) end nulls last,
    pl.updated_at desc,
    pl.id
  limit 1
),
metrics as (
  select c.candidate_key,
         c.display_name,
         c.primary_service_slug,
         c.buyer_organization_id,
         c.service_slugs,
         c.location,
         cl.id as provider_location_id,
         cl.location_type as provider_location_type,
         cl.location_name as provider_location_name,
         cl.city as provider_location_city,
         cl.state_code as provider_location_state,
         case when c.location is not null and cl.location is not null
              then st_distance(c.location, cl.location) / 1609.344 end as base_distance_miles,
         p.max_travel_miles
  from candidate c
  left join chosen_location cl on true
  left join profile p on true
),
counts as (
  select m.*,
         coalesce((select count(distinct coalesce(n.operational_target_key,n.display_dedupe_key,n.candidate_key))::integer
                   from scout.opportunity_search_spine n
                   where n.candidate_key <> m.candidate_key and n.pushable is true
                     and coalesce(n.global_suppressed,false) is false and n.location is not null and m.location is not null
                     and st_dwithin(n.location,m.location,greatest(coalesce(p_cluster_radius_miles,15),0)*1609.344)),0) as nearby_pushable_count,
         coalesce((select count(distinct coalesce(n.operational_target_key,n.display_dedupe_key,n.candidate_key))::integer
                   from scout.opportunity_search_spine n
                   where n.candidate_key <> m.candidate_key and n.pushable is true
                     and coalesce(n.global_suppressed,false) is false and n.location is not null and m.location is not null
                     and coalesce(array_length(n.service_slugs,1),0)>0 and coalesce(array_length(m.service_slugs,1),0)>0
                     and n.service_slugs && m.service_slugs
                     and st_dwithin(n.location,m.location,greatest(coalesce(p_cluster_radius_miles,15),0)*1609.344)),0) as nearby_same_service_count,
         case when m.buyer_organization_id is null then 0 else coalesce((select count(distinct coalesce(n.operational_target_key,n.display_dedupe_key,n.candidate_key))::integer
                   from scout.opportunity_search_spine n
                   where n.candidate_key <> m.candidate_key and n.pushable is true
                     and coalesce(n.global_suppressed,false) is false and n.buyer_organization_id=m.buyer_organization_id
                     and n.location is not null and m.location is not null
                     and st_dwithin(n.location,m.location,greatest(coalesce(p_account_radius_miles,50),0)*1609.344)),0) end as nearby_same_buyer_count,
         case when m.buyer_organization_id is null then 0 else coalesce((select count(distinct coalesce(n.operational_target_key,n.display_dedupe_key,n.candidate_key))::integer
                   from scout.opportunity_search_spine n
                   where n.pushable is true and coalesce(n.global_suppressed,false) is false
                     and n.buyer_organization_id=m.buyer_organization_id),0) end as same_buyer_pushable_portfolio_count
  from metrics m
)
select c.candidate_key,
       c.display_name,
       c.primary_service_slug,
       p_provider_organization_id,
       c.provider_location_id,
       c.provider_location_type,
       c.provider_location_name,
       c.provider_location_city,
       c.provider_location_state,
       round(c.base_distance_miles::numeric,1),
       round((c.base_distance_miles*2)::numeric,1),
       c.max_travel_miles,
       case when c.base_distance_miles is null or c.max_travel_miles is null then null else c.base_distance_miles<=c.max_travel_miles end,
       greatest(coalesce(p_cluster_radius_miles,15),0),
       c.nearby_pushable_count,
       c.nearby_same_service_count,
       greatest(coalesce(p_account_radius_miles,50),0),
       c.nearby_same_buyer_count,
       c.same_buyer_pushable_portfolio_count,
       case
         when c.nearby_same_buyer_count>=2 then 'high_leverage_account_cluster'
         when c.nearby_same_service_count>=3 then 'dense_same_service_cluster'
         when c.nearby_same_service_count>=1 then 'some_same_service_density'
         else 'isolated_same_service_destination'
       end,
       'forum_derived_hypothesis',
       'mobilization_efficiency',
       'mobilization_context_v1'
from counts c;
$$;

comment on function scout.opportunity_mobilization_context_v1(uuid,text,numeric,numeric) is
'Internal Scout mobilization context. Computes straight-line provider-base distance and distinct nearby operational-destination/account density. Generic nearby opportunity count is observational only; the qualitative signal uses same-service or same-buyer density. The signal is forum-derived and not a validated conversion predictor.';

revoke all on function scout.opportunity_mobilization_context_v1(uuid,text,numeric,numeric) from public;
revoke all on function scout.opportunity_mobilization_context_v1(uuid,text,numeric,numeric) from anon;
revoke all on function scout.opportunity_mobilization_context_v1(uuid,text,numeric,numeric) from authenticated;
grant execute on function scout.opportunity_mobilization_context_v1(uuid,text,numeric,numeric) to service_role;
