-- Premium exterior facility -> building identity guard v1
--
-- Core invariant: a facility/POI geocode is not building identity. Building-specific
-- height/story/facade/glazing/footprint evidence may propagate only when the facility
-- point is inside/within 10m of the candidate footprint, or when explicit corroborating
-- identity evidence has been recorded.

begin;

create table if not exists intelligence.premium_exterior_building_link_candidates (
  target_id uuid not null,
  candidate_building_source_record_id uuid not null,
  candidate_building_source_slug text,
  source_slug text,
  prior_centroid_distance_m double precision,
  footprint_edge_distance_m double precision,
  point_inside_footprint boolean,
  match_basis text not null default 'legacy_proximity_link',
  status text not null default 'quarantined',
  confidence numeric,
  evidence jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  primary key (target_id, candidate_building_source_record_id),
  constraint premium_exterior_building_link_candidates_status_chk
    check (status in ('quarantined','verified','rejected','superseded'))
);

create index if not exists premium_exterior_building_link_candidates_status_idx
  on intelligence.premium_exterior_building_link_candidates(status, last_observed_at desc);
create index if not exists premium_exterior_building_link_candidates_target_idx
  on intelligence.premium_exterior_building_link_candidates(target_id);

revoke all on intelligence.premium_exterior_building_link_candidates from public, anon, authenticated;
grant select, insert, update, delete on intelligence.premium_exterior_building_link_candidates to service_role;

comment on table intelligence.premium_exterior_building_link_candidates is
  'Reversible quarantine and review ledger for facility/POI to canonical-building candidates. A nearby facility geocode is not sufficient building identity.';

-- Preserve already-audited flagship exceptions as explicit identity evidence.
update intelligence.premium_exterior_targets t
set evidence = coalesce(t.evidence,'{}'::jsonb) || jsonb_build_object(
      'building_identity_status','verified_documented',
      'building_identity_verified_at',now(),
      'building_identity_basis','documented_story_compatible flagship audit'
    ),
    updated_at = now()
from intelligence.v_flagship_building_link_audit_v1 a
where a.flagship_target_id=t.id
  and a.link_audit_status='documented_story_compatible'
  and t.building_source_record_id is not null;

create or replace function intelligence.guard_premium_exterior_building_link_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, intelligence, decisioning, ingest
as $$
declare
  v_source_slug text;
  v_geometry extensions.geometry;
  v_edge_distance_m double precision;
  v_inside boolean;
  v_explicit_status text;
  v_confidence numeric;
begin
  if new.building_source_record_id is null then
    return new;
  end if;

  select s.slug into v_source_slug
  from ingest.sources s
  where s.id = new.source_id;

  if v_source_slug not in ('openstreetmap-premium-exterior-facilities','scout-flagship-facility-registry') then
    return new;
  end if;

  select bc.geometry into v_geometry
  from decisioning.building_candidates bc
  where bc.source_record_id = new.building_source_record_id;

  if new.location is not null and v_geometry is not null then
    v_edge_distance_m := extensions.st_distance(new.location::extensions.geography, v_geometry::extensions.geography);
    v_inside := extensions.st_covers(v_geometry, new.location::extensions.geometry);
  else
    v_edge_distance_m := null;
    v_inside := false;
  end if;

  v_explicit_status := coalesce(new.evidence->>'building_identity_status','');

  if v_explicit_status in ('verified_geometry','verified_documented','verified_reconciled')
     or coalesce(new.evidence->>'building_link_status','')='reconciled_existing_evidence' then
    update intelligence.premium_exterior_building_link_candidates
       set status='verified', last_observed_at=now(),
           evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object('verified_at',now(),'verification_basis','explicit_corroboration')
     where target_id=new.id and candidate_building_source_record_id=new.building_source_record_id;
    return new;
  end if;

  if v_edge_distance_m is not null and v_edge_distance_m <= 10 then
    new.evidence := coalesce(new.evidence,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'building_identity_status','verified_geometry',
      'building_identity_verified_at',now(),
      'building_identity_basis',case when v_inside then 'facility_point_inside_building_footprint' else 'facility_point_within_10m_of_building_footprint' end,
      'building_identity_edge_distance_m',round(v_edge_distance_m::numeric,2)
    ));
    update intelligence.premium_exterior_building_link_candidates
       set status='verified', last_observed_at=now(),
           evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object('verified_at',now(),'verification_basis','geometry_within_10m')
     where target_id=new.id and candidate_building_source_record_id=new.building_source_record_id;
    return new;
  end if;

  v_confidence := case
    when v_edge_distance_m is null then 0.20
    when v_edge_distance_m <= 25 then 0.65
    when v_edge_distance_m <= 50 then 0.50
    when v_edge_distance_m <= 100 then 0.35
    else 0.20
  end;

  insert into intelligence.premium_exterior_building_link_candidates(
    target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,
    prior_centroid_distance_m,footprint_edge_distance_m,point_inside_footprint,
    match_basis,status,confidence,evidence,first_observed_at,last_observed_at
  ) values (
    new.id,new.building_source_record_id,new.building_source_slug,v_source_slug,
    new.building_match_distance_m,v_edge_distance_m,v_inside,
    coalesce(nullif(new.evidence->>'building_link_basis',''),'legacy_proximity_link'),
    'quarantined',v_confidence,
    jsonb_strip_nulls(jsonb_build_object(
      'target_name',new.name,
      'target_address',new.address_text,
      'source_native_id',new.source_native_id,
      'guardrail','Facility/POI proximity alone is not building identity; do not promote building-specific physical evidence until corroborated.'
    )),now(),now()
  )
  on conflict (target_id,candidate_building_source_record_id) do update set
    candidate_building_source_slug=excluded.candidate_building_source_slug,
    source_slug=excluded.source_slug,
    prior_centroid_distance_m=excluded.prior_centroid_distance_m,
    footprint_edge_distance_m=excluded.footprint_edge_distance_m,
    point_inside_footprint=excluded.point_inside_footprint,
    match_basis=excluded.match_basis,
    status='quarantined',
    confidence=excluded.confidence,
    evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb) || excluded.evidence,
    last_observed_at=now();

  new.evidence := coalesce(new.evidence,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'building_identity_status','quarantined_unverified',
    'building_identity_quarantined_at',now(),
    'building_identity_guardrail','Building-specific height/story/facade/glazing/footprint evidence is blocked until physical building identity is corroborated.',
    'quarantined_candidate_building_id',new.building_source_record_id,
    'quarantined_candidate_building_slug',new.building_source_slug,
    'quarantined_candidate_centroid_distance_m',new.building_match_distance_m,
    'quarantined_candidate_footprint_edge_distance_m',v_edge_distance_m
  ));

  new.building_source_record_id := null;
  new.building_source_slug := null;
  new.footprint_sqft := null;
  new.mapped_height_m := null;
  new.property_address := null;
  new.property_city := null;
  new.postal_code := null;
  new.building_match_distance_m := null;
  new.updated_at := now();

  return new;
end;
$$;

revoke all on function intelligence.guard_premium_exterior_building_link_v1() from public, anon, authenticated;
grant execute on function intelligence.guard_premium_exterior_building_link_v1() to service_role;

drop trigger if exists premium_exterior_building_link_guard_insert_v1 on intelligence.premium_exterior_targets;
create trigger premium_exterior_building_link_guard_insert_v1
before insert on intelligence.premium_exterior_targets
for each row execute function intelligence.guard_premium_exterior_building_link_v1();

drop trigger if exists premium_exterior_building_link_guard_update_v1 on intelligence.premium_exterior_targets;
create trigger premium_exterior_building_link_guard_update_v1
before update of building_source_record_id, location, evidence on intelligence.premium_exterior_targets
for each row execute function intelligence.guard_premium_exterior_building_link_v1();

-- Re-run current linked rows through the guard.
update intelligence.premium_exterior_targets t
set building_source_record_id=t.building_source_record_id
from ingest.sources s
where s.id=t.source_id
  and s.slug in ('openstreetmap-premium-exterior-facilities','scout-flagship-facility-registry')
  and t.building_source_record_id is not null;

create or replace view intelligence.v_premium_exterior_building_link_resolution_queue_v1
with (security_invoker=true) as
select
  q.target_id,
  t.source_native_id,
  t.name as target_name,
  t.address_text as target_address,
  t.location as target_location,
  q.source_slug,
  q.candidate_building_source_record_id as prior_candidate_building_id,
  q.candidate_building_source_slug as prior_candidate_building_slug,
  q.prior_centroid_distance_m,
  q.footprint_edge_distance_m as prior_footprint_edge_distance_m,
  q.point_inside_footprint as prior_point_inside_footprint,
  q.match_basis as prior_match_basis,
  q.confidence as prior_candidate_confidence,
  nearest.source_record_id as nearest_building_id,
  nearest.source_slug as nearest_building_slug,
  nearest.edge_distance_m as nearest_footprint_edge_distance_m,
  nearest.point_inside as nearest_point_inside_footprint,
  case
    when nearest.source_record_id is not null
      and nearest.source_record_id <> q.candidate_building_source_record_id
      and nearest.edge_distance_m <= 10
      then 'alternate_footprint_within_10m'
    when q.footprint_edge_distance_m <= 25
      then 'corroborate_existing_candidate'
    when nearest.edge_distance_m <= 25
      then 'corroborate_nearest_candidate'
    when least(coalesce(q.footprint_edge_distance_m,1e9),coalesce(nearest.edge_distance_m,1e9)) <= 50
      then 'resolve_same_site_or_campus'
    else 'resolve_source_site_geometry_or_address'
  end as remediation_lane,
  case
    when nearest.source_record_id is not null
      and nearest.source_record_id <> q.candidate_building_source_record_id
      and nearest.edge_distance_m <= 10 then 1
    when least(coalesce(q.footprint_edge_distance_m,1e9),coalesce(nearest.edge_distance_m,1e9)) <= 25 then 2
    when least(coalesce(q.footprint_edge_distance_m,1e9),coalesce(nearest.edge_distance_m,1e9)) <= 50 then 3
    when least(coalesce(q.footprint_edge_distance_m,1e9),coalesce(nearest.edge_distance_m,1e9)) <= 100 then 4
    else 5
  end as remediation_priority,
  q.evidence,
  q.first_observed_at,
  q.last_observed_at
from intelligence.premium_exterior_building_link_candidates q
join intelligence.premium_exterior_targets t on t.id=q.target_id
left join lateral (
  select bc.source_record_id,bc.source_slug,
         extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography) as edge_distance_m,
         extensions.st_covers(bc.geometry,t.location::extensions.geometry) as point_inside
  from decisioning.building_candidates bc
  where t.location is not null
    and bc.geometry && extensions.st_expand(t.location::extensions.geometry,0.005)
  order by bc.geometry <-> t.location::extensions.geometry
  limit 1
) nearest on true
where q.status='quarantined';

revoke all on intelligence.v_premium_exterior_building_link_resolution_queue_v1 from public, anon, authenticated;
grant select on intelligence.v_premium_exterior_building_link_resolution_queue_v1 to service_role;

comment on view intelligence.v_premium_exterior_building_link_resolution_queue_v1 is
  'Quarantined premium facility-to-building links with nearest-footprint diagnostics and a remediation lane. Distance is triage, not identity.';

create or replace view intelligence.v_premium_exterior_building_identity_policy_violations_v1
with (security_invoker=true) as
select
  t.id as target_id,
  s.slug as source_slug,
  t.source_native_id,
  t.name,
  t.address_text,
  t.building_source_record_id,
  t.building_match_distance_m,
  extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography) as footprint_edge_distance_m,
  t.evidence->>'building_identity_status' as building_identity_status,
  t.evidence->>'building_link_status' as building_link_status
from intelligence.premium_exterior_targets t
join ingest.sources s on s.id=t.source_id
join decisioning.building_candidates bc on bc.source_record_id=t.building_source_record_id
where s.slug in ('openstreetmap-premium-exterior-facilities','scout-flagship-facility-registry')
  and t.building_source_record_id is not null
  and coalesce(t.evidence->>'building_identity_status','') not in ('verified_geometry','verified_documented','verified_reconciled')
  and coalesce(t.evidence->>'building_link_status','') <> 'reconciled_existing_evidence'
  and extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography) > 10;

revoke all on intelligence.v_premium_exterior_building_identity_policy_violations_v1 from public, anon, authenticated;
grant select on intelligence.v_premium_exterior_building_identity_policy_violations_v1 to service_role;

comment on view intelligence.v_premium_exterior_building_identity_policy_violations_v1 is
  'Must remain empty: facility/POI links farther than 10m from a footprint cannot carry building-specific enrichment without explicit corroboration.';

commit;
