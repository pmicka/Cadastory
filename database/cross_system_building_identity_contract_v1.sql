-- Scout cross-system building identity contract v1
--
-- Purpose:
--   Keep raw building records, canonical building identities, premium facility
--   identities, and property/portfolio links in explicit namespaces.
--   Proximity is candidate discovery only; physical attributes may cross a
--   namespace boundary only through an exact ID or a verified footprint bridge.

create table if not exists scout.raw_building_canonical_crosswalks (
  raw_building_source_record_id uuid primary key references ingest.raw_records(id) on delete cascade,
  raw_source_slug text,
  canonical_building_source_record_id uuid,
  canonical_source_slug text,
  overlap_ratio numeric,
  second_overlap_ratio numeric,
  uniqueness_margin numeric,
  edge_distance_m numeric,
  status text not null check (status in ('verified','ambiguous','unmatched')),
  match_basis text not null,
  confidence numeric,
  evidence jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now()
);

create index if not exists raw_building_canonical_crosswalks_canonical_idx
  on scout.raw_building_canonical_crosswalks(canonical_building_source_record_id,status);

revoke all on table scout.raw_building_canonical_crosswalks from public, anon, authenticated;
grant select,insert,update,delete on table scout.raw_building_canonical_crosswalks to service_role;

create or replace function scout.refresh_raw_building_canonical_crosswalks_v2()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_demand integer:=0;
  v_verified integer:=0;
  v_ambiguous integer:=0;
  v_unmatched integer:=0;
begin
  drop table if exists pg_temp._raw_building_identity_demand;
  create temporary table _raw_building_identity_demand on commit drop as
  select distinct x.raw_id
  from (
    select l.building_source_record_id as raw_id
    from scout.property_building_links l
    where l.match_status='resolved'
    union all
    select f.source_record_id
    from core.organization_facilities f
    join ingest.raw_records r on r.id=f.source_record_id
    where r.provisional_entity_type='building'
       or (r.raw_payload#>>'{properties,OCC_CLS}') is not null
    union all
    select c.building_source_record_id
    from cleaning.v_exterior_cleaning_push_candidates c
    join intelligence.premium_exterior_targets p
      on c.location is not null and p.location is not null
     and p.building_source_record_id is not null
     and coalesce(p.evidence->>'building_identity_status','') in ('verified_geometry','verified_documented','verified_reconciled')
     and extensions.st_dwithin(c.location::extensions.geography,p.location::extensions.geography,50)
  ) x
  join ingest.raw_records rr on rr.id=x.raw_id and rr.geometry is not null
  left join decisioning.building_candidates already on already.source_record_id=x.raw_id
  where x.raw_id is not null and already.source_record_id is null;
  get diagnostics v_demand=row_count;

  drop table if exists pg_temp._raw_building_identity_scored;
  create temporary table _raw_building_identity_scored on commit drop as
  with shortlisted as (
    select d.raw_id,rs.slug as raw_source_slug,c.canonical_id,c.canonical_source_slug,c.edge_m,c.overlap_ratio
    from _raw_building_identity_demand d
    join ingest.raw_records rr on rr.id=d.raw_id
    join ingest.sources rs on rs.id=rr.source_id
    left join lateral (
      select bc.source_record_id as canonical_id,bc.source_slug as canonical_source_slug,
             extensions.st_distance(rr.geometry::extensions.geography,bc.geometry::extensions.geography) as edge_m,
             case when extensions.st_area(rr.geometry::extensions.geography)>0 then
               extensions.st_area(
                 extensions.st_collectionextract(
                   extensions.st_intersection(extensions.st_makevalid(rr.geometry),extensions.st_makevalid(bc.geometry)),3
                 )::extensions.geography
               )/nullif(extensions.st_area(rr.geometry::extensions.geography),0)
             else 0 end as overlap_ratio
      from decisioning.building_candidates bc
      where bc.geometry operator(extensions.&&) extensions.st_expand(rr.geometry,0.0007)
        and extensions.st_dwithin(rr.geometry::extensions.geography,bc.geometry::extensions.geography,50)
      order by bc.geometry operator(extensions.<->) rr.geometry
      limit 6
    ) c on true
  ), ranked as (
    select s.*,row_number() over(partition by s.raw_id order by s.overlap_ratio desc nulls last,s.edge_m,s.canonical_id) as rn
    from shortlisted s
  )
  select d.raw_id,
         max(r.raw_source_slug) filter(where r.rn=1) as raw_source_slug,
         max(r.canonical_id::text) filter(where r.rn=1)::uuid as canonical_id,
         max(r.canonical_source_slug) filter(where r.rn=1) as canonical_source_slug,
         max(r.overlap_ratio) filter(where r.rn=1) as top_overlap,
         coalesce(max(r.overlap_ratio) filter(where r.rn=2),0) as second_overlap,
         max(r.edge_m) filter(where r.rn=1) as top_edge_m
  from _raw_building_identity_demand d
  left join ranked r on r.raw_id=d.raw_id
  group by d.raw_id;

  insert into scout.raw_building_canonical_crosswalks(
    raw_building_source_record_id,raw_source_slug,canonical_building_source_record_id,canonical_source_slug,
    overlap_ratio,second_overlap_ratio,uniqueness_margin,edge_distance_m,status,match_basis,confidence,evidence,
    first_observed_at,last_observed_at
  )
  select s.raw_id,s.raw_source_slug,
         case when s.top_overlap>=0.90 and s.second_overlap<=0.20 and s.top_overlap-s.second_overlap>=0.70 then s.canonical_id else null end,
         case when s.top_overlap>=0.90 and s.second_overlap<=0.20 and s.top_overlap-s.second_overlap>=0.70 then s.canonical_source_slug else null end,
         s.top_overlap,s.second_overlap,coalesce(s.top_overlap,0)-coalesce(s.second_overlap,0),s.top_edge_m,
         case when s.canonical_id is null then 'unmatched'
              when s.top_overlap>=0.90 and s.second_overlap<=0.20 and s.top_overlap-s.second_overlap>=0.70 then 'verified'
              else 'ambiguous' end,
         'raw_geometry_unique_canonical_overlap_v2',
         case when s.top_overlap>=0.90 and s.second_overlap<=0.20 and s.top_overlap-s.second_overlap>=0.70 then 0.98 else 0.40 end,
         jsonb_build_object('top_overlap_ratio',s.top_overlap,'second_overlap_ratio',s.second_overlap,
           'uniqueness_margin',coalesce(s.top_overlap,0)-coalesce(s.second_overlap,0),'top_edge_distance_m',s.top_edge_m,
           'guardrail','Raw building IDs cross into the canonical building namespace only after >=90% raw-footprint overlap, <=20% second-best overlap, and >=70 percentage-point uniqueness margin. Proximity is candidate discovery only.'),
         now(),now()
  from _raw_building_identity_scored s
  on conflict(raw_building_source_record_id) do update set
    raw_source_slug=excluded.raw_source_slug,canonical_building_source_record_id=excluded.canonical_building_source_record_id,
    canonical_source_slug=excluded.canonical_source_slug,overlap_ratio=excluded.overlap_ratio,
    second_overlap_ratio=excluded.second_overlap_ratio,uniqueness_margin=excluded.uniqueness_margin,
    edge_distance_m=excluded.edge_distance_m,status=excluded.status,match_basis=excluded.match_basis,
    confidence=excluded.confidence,evidence=excluded.evidence,last_observed_at=now();

  select count(*) filter(where status='verified'),count(*) filter(where status='ambiguous'),count(*) filter(where status='unmatched')
    into v_verified,v_ambiguous,v_unmatched
  from scout.raw_building_canonical_crosswalks
  where raw_building_source_record_id in (select raw_id from _raw_building_identity_demand);

  return jsonb_build_object('demand_raw_buildings',v_demand,'verified',v_verified,'ambiguous',v_ambiguous,'unmatched',v_unmatched);
end
$function$;

create or replace function scout.refresh_raw_building_canonical_crosswalks_v1()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select scout.refresh_raw_building_canonical_crosswalks_v2()
$function$;

revoke all on function scout.refresh_raw_building_canonical_crosswalks_v1() from public, anon, authenticated;
revoke all on function scout.refresh_raw_building_canonical_crosswalks_v2() from public, anon, authenticated;
grant execute on function scout.refresh_raw_building_canonical_crosswalks_v1() to service_role;
grant execute on function scout.refresh_raw_building_canonical_crosswalks_v2() to service_role;

create or replace view cleaning.v_exterior_cleaning_premium_context as
with premium_by_building as (
  select distinct on (p0.building_source_record_id)
    p0.id,p0.building_source_record_id,p0.name,p0.target_class,p0.target_subclass,p0.opportunity_tier,
    p0.glazing_status,p0.vertical_feature_status,p0.effective_height_m,p0.footprint_sqft,
    p0.public_image_sensitivity,p0.management_budget_proxy,p0.buyer_resolvability,p0.confidence,p0.raw_score
  from intelligence.v_premium_exterior_opportunities p0
  where p0.rankable
    and p0.building_source_record_id is not null
    and coalesce(p0.evidence->>'building_identity_status','') in ('verified_geometry','verified_documented','verified_reconciled')
  order by p0.building_source_record_id,p0.raw_score desc,p0.confidence desc nulls last,p0.id
), cleaning_identity as (
  select c.*,
    coalesce(bc.source_record_id,x.canonical_building_source_record_id) as canonical_building_source_record_id,
    case when bc.source_record_id is not null then 0::double precision else x.edge_distance_m::double precision end as canonical_match_distance_m,
    case when bc.source_record_id is not null then 'exact_building_source_record'
         when x.status='verified' then 'verified_raw_to_canonical_building_crosswalk_v1'
         else null end as canonical_match_basis
  from cleaning.v_exterior_cleaning_push_candidates c
  left join decisioning.building_candidates bc on bc.source_record_id=c.building_source_record_id
  left join scout.raw_building_canonical_crosswalks x
    on x.raw_building_source_record_id=c.building_source_record_id and x.status='verified'
)
select c.building_source_record_id,c.source_native_id,c.occupancy_class,c.primary_occupancy,c.square_feet,c.address,c.city,c.state,c.location,
       c.appearance_sensitivity,c.nearest_exposure_key,c.nearest_exposure_name,c.exposure_kind,c.exposure_distance_m,
       c.contamination_pressure,c.recent_new_construction,c.can_open_window,c.confidence,c.reason,c.evidence,c.refreshed_at,
       p.id as premium_target_id,p.name as premium_target_name,p.target_class as premium_target_class,p.target_subclass as premium_target_subclass,
       p.opportunity_tier as premium_target_tier,p.glazing_status as premium_glazing_status,
       p.vertical_feature_status as premium_vertical_feature_status,p.effective_height_m as premium_effective_height_m,
       p.footprint_sqft as premium_footprint_sqft,p.public_image_sensitivity as premium_public_image_sensitivity,
       p.management_budget_proxy as premium_management_budget_proxy,p.buyer_resolvability as premium_buyer_resolvability,
       p.confidence as premium_target_confidence,
       case when p.id is not null then c.canonical_match_distance_m end as premium_match_distance_m,
       case when p.id is not null then c.canonical_match_basis end as premium_match_basis,
       case p.opportunity_tier when 'very_high' then 3 when 'high' then 2 when 'medium' then 1 else 0 end as premium_priority_rank,
       case when p.id is null then 'independent_need_only' else 'independent_need_plus_premium_qualifier' end as ranking_basis
from cleaning_identity c
left join premium_by_building p on p.building_source_record_id=c.canonical_building_source_record_id;

create or replace view scout.v_opportunity_property_manager_links as
with managed_buildings as (
  select f.organization_id,f.management_company_name,f.management_company_type,
         f.source_record_id as property_source_record_id,f.site_name as managed_property_name,
         l.building_source_record_id,
         coalesce(case when bc.source_record_id is not null then l.building_source_record_id end,x.canonical_building_source_record_id) as canonical_building_source_record_id,
         least(f.confidence,l.confidence) as link_confidence,f.source_url,f.source_authority
  from scout.v_property_management_facilities f
  join scout.property_building_links l on l.property_source_record_id=f.source_record_id and l.match_status='resolved'
  left join decisioning.building_candidates bc on bc.source_record_id=l.building_source_record_id
  left join scout.raw_building_canonical_crosswalks x on x.raw_building_source_record_id=l.building_source_record_id and x.status='verified'
  where f.facility_scope='property' and f.portfolio_asset_status in ('operating','lease_up')
  union all
  select f.organization_id,f.management_company_name,f.management_company_type,f.source_record_id,f.site_name,f.source_record_id,
         coalesce(case when bc.source_record_id is not null then f.source_record_id end,x.canonical_building_source_record_id),
         f.confidence,f.source_url,f.source_authority
  from scout.v_property_management_facilities f
  left join decisioning.building_candidates bc on bc.source_record_id=f.source_record_id
  left join scout.raw_building_canonical_crosswalks x on x.raw_building_source_record_id=f.source_record_id and x.status='verified'
  where f.facility_scope='building'
)
select distinct s.candidate_key,mb.organization_id,mb.management_company_name,mb.management_company_type,
       mb.property_source_record_id,mb.managed_property_name,mb.building_source_record_id,mb.link_confidence,mb.source_url,mb.source_authority
from scout.opportunity_search_spine s
join managed_buildings mb
  on s.source_id=mb.building_source_record_id
  or s.canonical_asset_id=mb.building_source_record_id
  or (mb.canonical_building_source_record_id is not null and s.canonical_asset_id=mb.canonical_building_source_record_id);

create or replace view scout.v_opportunity_portfolio_account_links as
with account_buildings as (
  select f.organization_id,f.account_name,f.organization_type,f.portfolio_archetype,
         f.source_record_id as site_source_record_id,f.site_name,f.site_address_text,f.relationship_type,f.business_unit_count,f.brands,
         l.building_source_record_id,
         coalesce(case when bc.source_record_id is not null then l.building_source_record_id end,x.canonical_building_source_record_id) as canonical_building_source_record_id,
         least(f.confidence,l.confidence) as link_confidence,f.source_url,f.source_authority
  from scout.v_portfolio_account_facilities f
  join scout.property_building_links l on l.property_source_record_id=f.source_record_id and l.match_status='resolved'
  left join decisioning.building_candidates bc on bc.source_record_id=l.building_source_record_id
  left join scout.raw_building_canonical_crosswalks x on x.raw_building_source_record_id=l.building_source_record_id and x.status='verified'
  where f.portfolio_asset_status in ('operating','lease_up')
)
select distinct s.candidate_key,ab.organization_id,ab.account_name,ab.organization_type,ab.portfolio_archetype,
       ab.site_source_record_id,ab.site_name,ab.site_address_text,ab.relationship_type,ab.business_unit_count,ab.brands,
       ab.building_source_record_id,ab.link_confidence,ab.source_url,ab.source_authority
from scout.opportunity_search_spine s
join account_buildings ab
  on s.source_id=ab.building_source_record_id
  or s.canonical_asset_id=ab.building_source_record_id
  or (ab.canonical_building_source_record_id is not null and s.canonical_asset_id=ab.canonical_building_source_record_id);

create or replace view scout.v_cross_system_building_identity_policy_violations_v1 as
select 'premium_exterior_identity_policy'::text as violation_type,
       v.target_id::text as entity_key,
       jsonb_build_object('source_slug',v.source_slug,'source_native_id',v.source_native_id,'name',v.name,
         'building_source_record_id',v.building_source_record_id,'footprint_edge_distance_m',v.footprint_edge_distance_m,
         'building_identity_status',v.building_identity_status,'building_link_status',v.building_link_status) as details
from intelligence.v_premium_exterior_building_identity_policy_violations_v1 v
union all
select 'cleaning_premium_context_without_verified_building_crosswalk',c.building_source_record_id::text,
       jsonb_build_object('premium_target_id',c.premium_target_id,'premium_target_name',c.premium_target_name,
         'premium_match_basis',c.premium_match_basis,'premium_match_distance_m',c.premium_match_distance_m,
         'premium_building_source_record_id',p.building_source_record_id)
from cleaning.v_exterior_cleaning_premium_context c
join intelligence.premium_exterior_targets p on p.id=c.premium_target_id
left join scout.raw_building_canonical_crosswalks x on x.raw_building_source_record_id=c.building_source_record_id and x.status='verified'
where c.premium_target_id is not null
  and p.building_source_record_id<>c.building_source_record_id
  and p.building_source_record_id is distinct from x.canonical_building_source_record_id
union all
select 'opportunity_spine_canonical_building_missing',s.candidate_key,
       jsonb_build_object('canonical_asset_id',s.canonical_asset_id,'canonical_namespace',s.canonical_namespace,
         'source_kind',s.source_kind,'source_id',s.source_id,'display_name',s.display_name)
from scout.opportunity_search_spine s
left join decisioning.building_candidates b on b.source_record_id=s.canonical_asset_id
where s.target_class='building'
  and s.canonical_namespace='decisioning.building_candidates'
  and s.canonical_asset_id is not null
  and b.source_record_id is null;

create or replace function scout.get_opportunity_presentation_name(p_candidate_key text)
returns text
language sql
stable
set search_path to ''
as $function$
  select p.name
  from scout.opportunity_search_spine s
  join intelligence.premium_exterior_targets p
    on p.building_source_record_id=s.canonical_asset_id
   and p.name is not null
   and coalesce(p.evidence->>'building_identity_status','') in ('verified_geometry','verified_documented','verified_reconciled')
  where s.candidate_key=p_candidate_key
  order by case coalesce(p.evidence->>'building_identity_status','')
      when 'verified_documented' then 0 when 'verified_reconciled' then 1 when 'verified_geometry' then 2 else 9 end,
    p.confidence desc nulls last,p.updated_at desc
  limit 1
$function$;

create or replace function scout.get_opportunity_public_facility_route(p_candidate_key text)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'status','public_facility_route','name',p.name,'website_url',p.website_url,'address_text',p.address_text,
    'buyer_resolvability',p.buyer_resolvability,'match_distance_m',p.building_match_distance_m,
    'building_identity_status',p.evidence->>'building_identity_status','building_identity_basis',p.evidence->>'building_identity_basis',
    'match_basis','verified_building_identity_contract',
    'guardrail','This public facility/site route is exposed only after the facility-to-building identity is verified or explicitly reconciled. It can help resolve the responsible buyer, but it is not a verified durable department contact, procurement route, or permission to send outreach.'
  ))
  from scout.opportunity_search_spine s
  join intelligence.premium_exterior_targets p
    on p.building_source_record_id=s.canonical_asset_id
   and p.name is not null and p.website_url is not null
   and coalesce(p.evidence->>'building_identity_status','') in ('verified_geometry','verified_documented','verified_reconciled')
  where s.candidate_key=p_candidate_key
  order by case when p.buyer_resolvability='public_operator_or_site_route' then 0 else 1 end,
    case coalesce(p.evidence->>'building_identity_status','')
      when 'verified_documented' then 0 when 'verified_reconciled' then 1 when 'verified_geometry' then 2 else 9 end,
    p.confidence desc nulls last
  limit 1
$function$;
