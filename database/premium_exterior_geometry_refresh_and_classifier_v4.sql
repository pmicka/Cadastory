-- Premium exterior geometry refresh and classifier v4
--
-- The scheduled matcher remains geometry-first, but resolves height only for the current
-- workset instead of joining the full resolved-attributes view. Reporting counts are also
-- scoped to the workset. The active exterior classifier no longer suppresses premium
-- glazing context solely because a verified facility POI is >25m from its canonical building.

create or replace function intelligence.refresh_premium_exterior_building_matches()
returns jsonb
language plpgsql
set search_path to 'pg_catalog','intelligence','decisioning','ingest','extensions'
as $function$
declare
  v_proposed integer := 0;
  v_cleared integer := 0;
  v_verified integer := 0;
  v_quarantined integer := 0;
begin
  update intelligence.premium_exterior_targets t
  set building_source_record_id=null,
      building_source_slug=null,
      footprint_sqft=null,
      mapped_height_m=null,
      property_address=null,
      property_city=null,
      postal_code=null,
      building_match_distance_m=null,
      evidence=(coalesce(t.evidence,'{}'::jsonb)
        - 'building_identity_status'
        - 'building_identity_verified_at'
        - 'building_identity_basis'
        - 'building_identity_edge_distance_m')
        || jsonb_build_object(
          'building_identity_status','site_only_unresolved',
          'building_identity_basis','non_exact_flagship_geocode_not_building_identity',
          'building_match_method','footprint_geometry_required'
        ),
      updated_at=now()
  from ingest.sources ts
  where ts.id=t.source_id
    and ts.slug='scout-flagship-facility-registry'
    and coalesce(t.evidence->>'geocode_method','') <> 'US Census exact address match'
    and coalesce(t.evidence->>'building_identity_status','') not in ('verified_documented','verified_reconciled')
    and coalesce(t.evidence->>'building_link_status','') <> 'reconciled_existing_evidence'
    and coalesce(t.evidence->>'building_link_status','') <> 'unresolved_merged_footprint'
    and t.building_source_record_id is not null;
  get diagnostics v_cleared=row_count;

  drop table if exists pg_temp._premium_exterior_refresh_best;
  create temporary table _premium_exterior_refresh_best on commit drop as
  select t.id as target_id,t.location as target_location,
         b.source_record_id,b.source_slug,b.footprint_sqft,b.source_height_m,b.location as building_location,
         b.property_address,b.property_city,b.state_code,b.postal_code,b.edge_distance_m
  from intelligence.premium_exterior_targets t
  join ingest.sources ts on ts.id=t.source_id
  left join lateral (
    select bc.source_record_id,bc.source_slug,bc.footprint_sqft,bc.height_m as source_height_m,bc.location,
           bc.property_address,bc.property_city,bc.state_code,bc.postal_code,
           extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography) as edge_distance_m
    from decisioning.building_candidates bc
    where bc.geometry is not null
      and bc.geometry && extensions.st_expand(t.location::extensions.geometry,0.003)
      and extensions.st_dwithin(t.location::extensions.geography,bc.geometry::extensions.geography,200)
    order by bc.geometry <-> t.location::extensions.geometry,
             extensions.st_distance(t.location::extensions.geography,bc.geometry::extensions.geography),
             coalesce(bc.footprint_sqft,0) desc
    limit 1
  ) b on true
  where t.source_present and t.location is not null
    and (ts.slug='openstreetmap-premium-exterior-facilities'
      or (ts.slug='scout-flagship-facility-registry'
        and coalesce(t.evidence->>'geocode_method','')='US Census exact address match'))
    and coalesce(t.evidence->>'building_identity_status','') not in ('verified_documented','verified_reconciled')
    and coalesce(t.evidence->>'building_link_status','') <> 'reconciled_existing_evidence'
    and coalesce(t.evidence->>'building_link_status','') <> 'unresolved_merged_footprint';

  create index on _premium_exterior_refresh_best(target_id);
  create index on _premium_exterior_refresh_best(source_record_id);

  drop table if exists pg_temp._premium_exterior_refresh_height;
  create temporary table _premium_exterior_refresh_height on commit drop as
  select b.target_id,
         coalesce(h.height_m::double precision,b.source_height_m) as resolved_height_m
  from _premium_exterior_refresh_best b
  left join lateral (
    select o.height_m
    from decisioning.building_attribute_matches m
    join decisioning.building_attribute_observations o on o.id=m.observation_id
    where m.building_source_record_id=b.source_record_id
      and o.height_m is not null
    order by case o.height_status when 'documented' then 4 when 'derived_lidar' then 3 when 'source_reported' then 3 when 'automated' then 2 else 1 end desc,
             case o.source_feature_kind when 'building' then 2 else 1 end desc,
             m.confidence desc,o.confidence desc,o.observed_at desc
    limit 1
  ) h on true
  where b.source_record_id is not null;
  create index on _premium_exterior_refresh_height(target_id);

  update intelligence.premium_exterior_building_link_candidates q
     set status='superseded',
         evidence=coalesce(q.evidence,'{}'::jsonb) || jsonb_build_object(
           'superseded_at',now(),
           'supersession_basis','geometry_first_refresh_selected_different_candidate'
         ),
         last_observed_at=now()
  from _premium_exterior_refresh_best b
  where q.target_id=b.target_id
    and q.status='quarantined'
    and b.source_record_id is not null
    and q.candidate_building_source_record_id<>b.source_record_id;

  update intelligence.premium_exterior_targets t
  set building_source_record_id=b.source_record_id,
      building_source_slug=b.source_slug,
      footprint_sqft=b.footprint_sqft,
      mapped_height_m=rh.resolved_height_m,
      property_address=b.property_address,
      property_city=b.property_city,
      state_code=coalesce(b.state_code,t.state_code),
      postal_code=b.postal_code,
      building_match_distance_m=case when t.location is not null and b.building_location is not null
        then extensions.st_distance(t.location::extensions.geography,b.building_location::extensions.geography)
        else null end,
      evidence=(coalesce(t.evidence,'{}'::jsonb)
        - 'building_identity_status'
        - 'building_identity_verified_at'
        - 'building_identity_basis'
        - 'building_identity_edge_distance_m')
        || jsonb_strip_nulls(jsonb_build_object(
          'building_match_method','nearest_canonical_footprint_edge_distance',
          'building_match_proposed_at',now(),
          'building_match_proposed_edge_distance_m',round(b.edge_distance_m::numeric,2)
        )),
      updated_at=now()
  from _premium_exterior_refresh_best b
  left join _premium_exterior_refresh_height rh on rh.target_id=b.target_id
  where t.id=b.target_id and b.source_record_id is not null;
  get diagnostics v_proposed=row_count;

  update intelligence.premium_exterior_targets t
  set building_source_record_id=null,building_source_slug=null,footprint_sqft=null,mapped_height_m=null,
      property_address=null,property_city=null,postal_code=null,building_match_distance_m=null,
      evidence=(coalesce(t.evidence,'{}'::jsonb)
        - 'building_identity_status'
        - 'building_identity_verified_at'
        - 'building_identity_basis'
        - 'building_identity_edge_distance_m')
        || jsonb_build_object(
          'building_identity_status','unresolved_no_canonical_footprint_within_200m',
          'building_identity_basis','geometry_first_refresh_no_candidate',
          'building_match_method','nearest_canonical_footprint_edge_distance'
        ),
      updated_at=now()
  from _premium_exterior_refresh_best b
  where t.id=b.target_id and b.source_record_id is null;

  select count(*) into v_verified
  from intelligence.premium_exterior_targets t
  join _premium_exterior_refresh_best b on b.target_id=t.id
  where coalesce(t.evidence->>'building_identity_status','')='verified_geometry';

  select count(*) into v_quarantined
  from intelligence.premium_exterior_building_link_candidates q
  join _premium_exterior_refresh_best b on b.target_id=q.target_id
  where q.status='quarantined';

  return jsonb_build_object(
    'match_method','nearest_canonical_footprint_edge_distance',
    'proposals_evaluated',v_proposed,
    'non_exact_flagship_links_cleared',v_cleared,
    'verified_geometry_targets',v_verified,
    'quarantined_candidates',v_quarantined,
    'height_resolution_scope','current_refresh_workset',
    'report_scope','current_refresh_workset'
  );
end
$function$;

-- The underlying v1 classifier already joins premium evidence by the exact canonical
-- building_source_record_id. Remove only the obsolete POI-distance suppression.
do $do$
declare
  v_def text;
  v_old text := 'WHERE px.building_match_distance_m IS NULL OR px.building_match_distance_m <= 25::double precision';
begin
  select pg_get_viewdef('cleaning.v_exterior_opportunity_service_classification_build'::regclass,true) into v_def;
  if position(v_old in v_def)>0 then
    v_def := replace(v_def,v_old,'WHERE true');
    execute 'create or replace view cleaning.v_exterior_opportunity_service_classification_build as '||v_def;
  end if;
end
$do$;
