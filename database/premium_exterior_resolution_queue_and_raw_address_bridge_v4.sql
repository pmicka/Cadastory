-- Scout by Cadastory
-- Premium exterior building-resolution queue + independent raw-address geometry bridge v4
--
-- Purpose
--   1. Keep the operational building-resolution queue current-only while retaining
--      historical quarantine rows in the durable audit ledger.
--   2. Allow a quarantined facility/POI to inherit a canonical building only when
--      an independent FEMA building record establishes the exact street address and
--      uniquely overlaps that same canonical footprint.
--
-- Guardrails
--   * Proximity alone is never building identity.
--   * The raw-address bridge is service-role only.
--   * The canonical footprint must already be the target's quarantined candidate.
--   * Independent raw geometry must overlap one canonical footprint >= 90%, with
--     second-best overlap <= 20% and uniqueness margin >= 70 percentage points.
--   * Target must be within 50 m of the corroborated canonical footprint.

create table if not exists intelligence.premium_exterior_raw_building_identity_evidence (
  target_id uuid not null references intelligence.premium_exterior_targets(id) on delete cascade,
  raw_building_record_id uuid not null references ingest.raw_records(id) on delete cascade,
  canonical_building_source_record_id uuid not null,
  raw_source_slug text,
  raw_address text,
  canonical_overlap_ratio numeric,
  canonical_second_overlap_ratio numeric,
  canonical_uniqueness_margin numeric,
  target_to_canonical_edge_m numeric,
  status text not null default 'candidate' check (status in ('candidate','verified','rejected','superseded')),
  confidence numeric,
  evidence jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  primary key (target_id,raw_building_record_id,canonical_building_source_record_id)
);

create index if not exists premium_exterior_raw_building_identity_evidence_target_idx
  on intelligence.premium_exterior_raw_building_identity_evidence(target_id,status);

revoke all on intelligence.premium_exterior_raw_building_identity_evidence from public, anon, authenticated;
grant select,insert,update,delete on intelligence.premium_exterior_raw_building_identity_evidence to service_role;

create or replace view intelligence.v_premium_exterior_building_link_resolution_queue_v1 as
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
      and nearest.edge_distance_m <= 10 then 'alternate_footprint_within_10m'
    when q.footprint_edge_distance_m <= 25 then 'corroborate_existing_candidate'
    when nearest.edge_distance_m <= 25 then 'corroborate_nearest_candidate'
    when least(coalesce(q.footprint_edge_distance_m,1000000000::double precision),
               coalesce(nearest.edge_distance_m,1000000000::double precision)) <= 50
      then 'resolve_same_site_or_campus'
    else 'resolve_source_site_geometry_or_address'
  end as remediation_lane,
  case
    when nearest.source_record_id is not null
      and nearest.source_record_id <> q.candidate_building_source_record_id
      and nearest.edge_distance_m <= 10 then 1
    when least(coalesce(q.footprint_edge_distance_m,1000000000::double precision),
               coalesce(nearest.edge_distance_m,1000000000::double precision)) <= 25 then 2
    when least(coalesce(q.footprint_edge_distance_m,1000000000::double precision),
               coalesce(nearest.edge_distance_m,1000000000::double precision)) <= 50 then 3
    when least(coalesce(q.footprint_edge_distance_m,1000000000::double precision),
               coalesce(nearest.edge_distance_m,1000000000::double precision)) <= 100 then 4
    else 5
  end as remediation_priority,
  q.evidence,
  q.first_observed_at,
  q.last_observed_at
from intelligence.premium_exterior_building_link_candidates q
join intelligence.premium_exterior_targets t on t.id=q.target_id
left join lateral (
  select
    bc.source_record_id,
    bc.source_slug,
    extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography) as edge_distance_m,
    extensions.st_covers(bc.geometry,t.location::extensions.geometry) as point_inside
  from decisioning.building_candidates bc
  where t.location is not null
    and bc.geometry operator(extensions.&&) extensions.st_expand(t.location::extensions.geometry,0.005)
  order by bc.geometry operator(extensions.<->) t.location::extensions.geometry
  limit 1
) nearest on true
where q.status='quarantined'
  and t.building_source_record_id is null;

create or replace function intelligence.promote_premium_exterior_raw_address_geometry_bridge_v1(
  p_target_id uuid,
  p_raw_building_record_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, intelligence, decisioning, ingest, cleaning
as $$
declare
  v_t intelligence.premium_exterior_targets%rowtype;
  v_r ingest.raw_records%rowtype;
  v_bc decisioning.building_candidates%rowtype;
  v_raw_source_slug text;
  v_raw_address text;
  v_raw_city text;
  v_target_norm text;
  v_raw_addr_norm text;
  v_raw_city_norm text;
  v_top_id uuid;
  v_top_overlap double precision;
  v_second_overlap double precision:=0;
  v_top_edge double precision;
  v_target_edge double precision;
  v_uniqueness double precision;
  v_confidence numeric:=0.98;
  v_basis text:='independent_raw_exact_address_plus_unique_geometry_overlap_v1';
begin
  select * into v_t
  from intelligence.premium_exterior_targets
  where id=p_target_id
  for update;
  if not found then raise exception 'premium exterior target not found'; end if;
  if v_t.building_source_record_id is not null then raise exception 'target already has building identity'; end if;
  if v_t.address_text is null or v_t.location is null then raise exception 'target lacks address or location'; end if;

  select * into v_r from ingest.raw_records where id=p_raw_building_record_id;
  if not found or v_r.geometry is null then raise exception 'raw building record missing geometry'; end if;
  if coalesce(v_r.provisional_entity_type,'')<>'building' then raise exception 'raw record is not typed as building'; end if;

  select s.slug into v_raw_source_slug from ingest.sources s where s.id=v_r.source_id;
  if v_raw_source_slug<>'fema-usa-structures-current' then
    raise exception 'raw source is not approved for this bridge: %',v_raw_source_slug;
  end if;

  select c.address,c.city into v_raw_address,v_raw_city
  from cleaning.exterior_need_candidates c
  where c.building_source_record_id=p_raw_building_record_id
    and c.address is not null
  order by c.confidence desc nulls last
  limit 1;
  if v_raw_address is null then raise exception 'no address-bearing cleaning building record for raw building'; end if;

  v_target_norm:=intelligence.normalize_identity_text_v1(v_t.address_text);
  v_raw_addr_norm:=intelligence.normalize_identity_text_v1(v_raw_address);
  v_raw_city_norm:=intelligence.normalize_identity_text_v1(coalesce(v_raw_city,''));
  if v_raw_addr_norm='' or v_target_norm not like v_raw_addr_norm||'%' then
    raise exception 'raw building address does not exactly prefix target address';
  end if;
  if v_raw_city_norm<>'' and v_target_norm not like '%'||v_raw_city_norm||'%' then
    raise exception 'raw building city does not match target address';
  end if;

  select x.source_record_id,x.overlap_ratio,x.edge_m
  into v_top_id,v_top_overlap,v_top_edge
  from (
    select
      bc.source_record_id,
      extensions.st_distance(v_r.geometry::extensions.geography,bc.geometry::extensions.geography) as edge_m,
      case when extensions.st_area(v_r.geometry::extensions.geography)>0 then
        extensions.st_area(
          extensions.st_collectionextract(
            extensions.st_intersection(extensions.st_makevalid(v_r.geometry),extensions.st_makevalid(bc.geometry)),3
          )::extensions.geography
        )/nullif(extensions.st_area(v_r.geometry::extensions.geography),0)
      else 0 end as overlap_ratio
    from decisioning.building_candidates bc
    where bc.geometry operator(extensions.&&) extensions.st_expand(v_r.geometry,0.0005)
      and extensions.st_dwithin(v_r.geometry::extensions.geography,bc.geometry::extensions.geography,30)
    order by overlap_ratio desc,edge_m,bc.source_record_id
    limit 1
  ) x;
  if v_top_id is null then raise exception 'no canonical building near raw building'; end if;

  select coalesce(x.overlap_ratio,0)
  into v_second_overlap
  from (
    select
      case when extensions.st_area(v_r.geometry::extensions.geography)>0 then
        extensions.st_area(
          extensions.st_collectionextract(
            extensions.st_intersection(extensions.st_makevalid(v_r.geometry),extensions.st_makevalid(bc.geometry)),3
          )::extensions.geography
        )/nullif(extensions.st_area(v_r.geometry::extensions.geography),0)
      else 0 end as overlap_ratio,
      extensions.st_distance(v_r.geometry::extensions.geography,bc.geometry::extensions.geography) as edge_m,
      bc.source_record_id
    from decisioning.building_candidates bc
    where bc.source_record_id<>v_top_id
      and bc.geometry operator(extensions.&&) extensions.st_expand(v_r.geometry,0.0005)
      and extensions.st_dwithin(v_r.geometry::extensions.geography,bc.geometry::extensions.geography,30)
    order by overlap_ratio desc,edge_m,bc.source_record_id
    limit 1
  ) x;
  v_second_overlap:=coalesce(v_second_overlap,0);
  v_uniqueness:=coalesce(v_top_overlap,0)-v_second_overlap;

  if coalesce(v_top_overlap,0)<0.90 or v_second_overlap>0.20 or v_uniqueness<0.70 then
    raise exception 'raw building geometry does not uniquely map to one canonical footprint';
  end if;

  if not exists(
    select 1
    from intelligence.premium_exterior_building_link_candidates q
    where q.target_id=p_target_id
      and q.candidate_building_source_record_id=v_top_id
      and q.status='quarantined'
  ) then
    raise exception 'top canonical footprint is not the target''s quarantined candidate';
  end if;

  select * into v_bc from decisioning.building_candidates where source_record_id=v_top_id;
  if not found then raise exception 'canonical building candidate not found'; end if;
  v_target_edge:=extensions.st_distance(v_t.location::extensions.geography,v_bc.geometry::extensions.geography);
  if v_target_edge>50 then raise exception 'target is too far from canonical footprint for address bridge: %',v_target_edge; end if;

  insert into intelligence.premium_exterior_raw_building_identity_evidence(
    target_id,raw_building_record_id,canonical_building_source_record_id,raw_source_slug,raw_address,
    canonical_overlap_ratio,canonical_second_overlap_ratio,canonical_uniqueness_margin,target_to_canonical_edge_m,
    status,confidence,evidence,first_observed_at,last_observed_at
  ) values(
    p_target_id,p_raw_building_record_id,v_top_id,v_raw_source_slug,v_raw_address,
    v_top_overlap,v_second_overlap,v_uniqueness,v_target_edge,
    'verified',v_confidence,
    jsonb_build_object(
      'verification_basis',v_basis,
      'target_address',v_t.address_text,
      'raw_building_address',v_raw_address,
      'raw_building_city',v_raw_city,
      'raw_source_slug',v_raw_source_slug,
      'canonical_source_slug',v_bc.source_slug,
      'guardrail','Independent exact address and uniquely overlapping raw building geometry are required; proximity alone is insufficient.'
    ),now(),now()
  ) on conflict(target_id,raw_building_record_id,canonical_building_source_record_id) do update set
    status='verified',
    confidence=excluded.confidence,
    canonical_overlap_ratio=excluded.canonical_overlap_ratio,
    canonical_second_overlap_ratio=excluded.canonical_second_overlap_ratio,
    canonical_uniqueness_margin=excluded.canonical_uniqueness_margin,
    target_to_canonical_edge_m=excluded.target_to_canonical_edge_m,
    evidence=coalesce(intelligence.premium_exterior_raw_building_identity_evidence.evidence,'{}'::jsonb)||excluded.evidence,
    last_observed_at=now();

  update intelligence.premium_exterior_targets
  set building_source_record_id=v_bc.source_record_id,
      building_source_slug=v_bc.source_slug,
      footprint_sqft=v_bc.footprint_sqft,
      mapped_height_m=v_bc.height_m,
      property_address=v_bc.property_address,
      property_city=v_bc.property_city,
      state_code=coalesce(state_code,v_bc.state_code),
      postal_code=v_bc.postal_code,
      building_match_distance_m=v_target_edge,
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
        'building_identity_status','verified_reconciled',
        'building_identity_verified_at',now(),
        'building_identity_basis',v_basis,
        'building_identity_raw_building_record_id',p_raw_building_record_id,
        'building_identity_raw_source_slug',v_raw_source_slug,
        'building_identity_raw_address',v_raw_address,
        'building_identity_canonical_overlap_ratio',round(v_top_overlap::numeric,3),
        'building_identity_canonical_second_overlap_ratio',round(v_second_overlap::numeric,3),
        'building_identity_canonical_uniqueness_margin',round(v_uniqueness::numeric,3),
        'building_identity_edge_distance_m',round(v_target_edge::numeric,2),
        'building_identity_confidence',v_confidence,
        'building_identity_guardrail','Promoted only after independent exact address and uniquely overlapping raw-building geometry corroborated the quarantined canonical footprint.'
      ),
      updated_at=now()
  where id=p_target_id;

  update intelligence.premium_exterior_building_link_candidates
  set status=case when candidate_building_source_record_id=v_top_id then 'verified' else 'superseded' end,
      confidence=case when candidate_building_source_record_id=v_top_id then v_confidence else confidence end,
      match_basis=case when candidate_building_source_record_id=v_top_id then v_basis else match_basis end,
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
        case when candidate_building_source_record_id=v_top_id then 'verified_at' else 'superseded_at' end,now(),
        'resolution_basis',v_basis,
        'raw_building_record_id',p_raw_building_record_id,
        'canonical_overlap_ratio',v_top_overlap,
        'canonical_uniqueness_margin',v_uniqueness
      ),
      last_observed_at=now()
  where target_id=p_target_id and status='quarantined';

  return jsonb_build_object(
    'target_id',p_target_id,
    'raw_building_record_id',p_raw_building_record_id,
    'canonical_building_source_record_id',v_top_id,
    'canonical_overlap_ratio',v_top_overlap,
    'canonical_second_overlap_ratio',v_second_overlap,
    'canonical_uniqueness_margin',v_uniqueness,
    'target_to_canonical_edge_m',v_target_edge,
    'confidence',v_confidence,
    'building_identity_status','verified_reconciled',
    'building_identity_basis',v_basis
  );
end;
$$;

revoke all on function intelligence.promote_premium_exterior_raw_address_geometry_bridge_v1(uuid,text) from public, anon, authenticated;
-- The live function signature is (uuid, uuid); revoke/grant it explicitly below.
revoke all on function intelligence.promote_premium_exterior_raw_address_geometry_bridge_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function intelligence.promote_premium_exterior_raw_address_geometry_bridge_v1(uuid,uuid) to service_role;
