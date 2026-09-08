-- Premium exterior local OSM identity evidence v1
--
-- Converts the targeted local Geofabrik building cache into evidence candidates.
-- This file intentionally stops short of updating premium_exterior_targets.
-- A POI/building association must clear both independent identity corroboration
-- and canonical footprint reconciliation before it can become auto-reconcile-ready.

begin;

alter table intelligence.premium_exterior_osm_identity_candidates
  add column if not exists name_similarity numeric,
  add column if not exists address_match boolean,
  add column if not exists operator_similarity numeric,
  add column if not exists class_compatible boolean,
  add column if not exists canonical_second_overlap_ratio numeric,
  add column if not exists canonical_uniqueness_margin numeric,
  add column if not exists corroboration_basis text;

create or replace function intelligence.normalize_identity_text_v1(p_text text)
returns text
language sql
immutable
parallel safe
set search_path=''
as $$
  select btrim(regexp_replace(
    regexp_replace(
      regexp_replace(lower(coalesce(p_text,'')), '&', ' and ', 'g'),
      '^(main[[:space:]]+)?entrance([[:space:]]+(to|at))?[:[:space:]]+', '', 'g'
    ),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

create or replace view intelligence.v_premium_exterior_local_osm_reconciliation_review_v1
with (security_invoker=true) as
with base as (
  select
    c.*,
    t.name as target_name,
    t.address_text as target_address,
    t.target_class,
    t.target_subclass,
    intelligence.normalize_identity_text_v1(t.name) as target_name_norm,
    row_number() over (
      partition by c.target_id
      order by coalesce(c.confidence,0) desc,coalesce(c.canonical_overlap_ratio,0) desc,coalesce(c.distance_m,1e9),c.osm_building_iri
    ) as candidate_rank,
    lead(c.confidence) over (
      partition by c.target_id
      order by coalesce(c.confidence,0) desc,coalesce(c.canonical_overlap_ratio,0) desc,coalesce(c.distance_m,1e9),c.osm_building_iri
    ) as next_confidence
  from intelligence.premium_exterior_osm_identity_candidates c
  join intelligence.premium_exterior_targets t on t.id=c.target_id
  where c.status in ('candidate','reconciled')
    and coalesce(c.evidence->>'resolver','')='local_geofabrik_osm_building_identity_v1'
)
select
  b.*,
  (
    b.target_class in ('religious_facility','dealership_showroom','hotel','museum_performing_arts')
    and coalesce(b.target_name_norm,'') !~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)'
    and b.canonical_building_source_record_id is not null
    and coalesce(b.canonical_overlap_ratio,0)>=0.80
    and coalesce(b.canonical_uniqueness_margin,1)>=0.25
    and (
      coalesce(b.address_match,false)
      or coalesce(b.name_similarity,0)>=0.82
      or coalesce(b.operator_similarity,0)>=0.85
    )
    and coalesce(b.distance_m,1e9)<=200
    and b.candidate_rank=1
    and (b.next_confidence is null or coalesce(b.confidence,0)-coalesce(b.next_confidence,0)>=0.15)
  ) as auto_reconcile_ready
from base b;

revoke all on intelligence.v_premium_exterior_local_osm_reconciliation_review_v1 from public,anon,authenticated;
grant select on intelligence.v_premium_exterior_local_osm_reconciliation_review_v1 to service_role;

comment on view intelligence.v_premium_exterior_local_osm_reconciliation_review_v1 is
  'Evidence-only review surface for targeted local OSM node-to-building reconciliation. auto_reconcile_ready remains conservative and does not itself update premium targets.';

create or replace function intelligence.refresh_premium_exterior_local_osm_identity_candidates_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_upserted integer:=0;
  v_ready integer:=0;
begin
  with unresolved as (
    select distinct on (t.id)
      t.id as target_id,
      t.name as target_name,
      t.address_text as target_address,
      t.operator_name as target_operator,
      t.target_class,
      t.target_subclass,
      t.location
    from intelligence.premium_exterior_targets t
    join intelligence.premium_exterior_building_link_candidates q
      on q.target_id=t.id and q.status='quarantined'
    where t.source_present
      and t.location is not null
      and t.building_source_record_id is null
      and t.source_native_id like 'https://www.openstreetmap.org/node/%'
      and coalesce(t.evidence->>'source_scope','') <> 'site_area'
      and coalesce(t.evidence->>'building_identity_status','') not in ('verified_geometry','verified_documented','verified_reconciled')
    order by t.id,q.last_observed_at desc
  ), spatial as (
    select
      u.*,
      f.osm_iri,
      f.geometry as osm_geometry,
      f.building_tag,
      f.name as building_name,
      f.operator_name,
      f.brand_name,
      f.amenity_tag,
      f.addr_housenumber,
      f.addr_street,
      f.addr_city,
      f.addr_postcode,
      f.raw_tags,
      extensions.st_distance(u.location::extensions.geography,f.geometry::extensions.geography) as edge_distance_m,
      intelligence.normalize_identity_text_v1(u.target_name) as target_name_norm,
      intelligence.normalize_identity_text_v1(f.name) as building_name_norm,
      intelligence.normalize_identity_text_v1(u.target_operator) as target_operator_norm,
      intelligence.normalize_identity_text_v1(f.operator_name) as building_operator_norm,
      intelligence.normalize_identity_text_v1(f.brand_name) as building_brand_norm,
      intelligence.normalize_identity_text_v1(u.target_address) as target_address_norm,
      intelligence.normalize_identity_text_v1(f.addr_street) as building_street_norm,
      lower(coalesce(substring(btrim(coalesce(u.target_address,'')) from '^([0-9]+[A-Za-z]?)'),'')) as target_house_norm,
      lower(coalesce(f.addr_housenumber,'')) as building_house_norm
    from unresolved u
    join intelligence.osm_building_identity_features f
      on f.geometry OPERATOR(extensions.&&) extensions.st_expand(u.location::extensions.geometry,0.006)
     and extensions.st_dwithin(u.location::extensions.geography,f.geometry::extensions.geography,400)
  ), scored as (
    select s.*,
      case when s.target_name_norm<>'' and s.building_name_norm<>''
        then extensions.similarity(s.target_name_norm,s.building_name_norm)::numeric else 0::numeric end as name_sim,
      case when s.target_operator_norm<>''
        then greatest(
          case when s.building_operator_norm<>'' then extensions.similarity(s.target_operator_norm,s.building_operator_norm) else 0 end,
          case when s.building_brand_norm<>'' then extensions.similarity(s.target_operator_norm,s.building_brand_norm) else 0 end
        )::numeric else 0::numeric end as operator_sim,
      (s.target_house_norm<>'' and s.target_house_norm=s.building_house_norm
       and s.building_street_norm<>'' and strpos(s.target_address_norm,s.building_street_norm)>0) as addr_match,
      case
        when s.target_class='religious_facility' then coalesce(s.amenity_tag,'')='place_of_worship' or coalesce(s.building_tag,'') in ('church','chapel','religious')
        when s.target_class='hotel' then coalesce(s.raw_tags->>'tourism','') in ('hotel','motel','guest_house') or coalesce(s.building_tag,'') in ('hotel','motel')
        when s.target_class='dealership_showroom' then coalesce(s.raw_tags->>'shop','')='car' or coalesce(s.raw_tags->>'amenity','')='car_rental'
        when s.target_class='museum_performing_arts' then coalesce(s.raw_tags->>'tourism','')='museum' or coalesce(s.amenity_tag,'') in ('theatre','arts_centre')
        when s.target_class='hospital' then coalesce(s.amenity_tag,'')='hospital' or coalesce(s.building_tag,'')='hospital'
        else false
      end as class_ok
    from spatial s
  ), strong_osm as (
    select *,
      greatest(
        case when name_sim>=0.82 then 0.90 when name_sim>=0.72 then 0.75 else 0 end,
        case when addr_match then 0.95 else 0 end,
        case when operator_sim>=0.85 then 0.90 when operator_sim>=0.75 then 0.75 else 0 end
      ) + case when class_ok then 0.03 else 0 end as corroboration_score,
      case
        when addr_match then 'exact_house_and_street'
        when name_sim>=0.82 then 'strong_name_match'
        when operator_sim>=0.85 then 'strong_operator_or_brand_match'
        when name_sim>=0.72 then 'moderate_name_match'
        when operator_sim>=0.75 then 'moderate_operator_or_brand_match'
        else null
      end as basis
    from scored
    where addr_match or name_sim>=0.72 or operator_sim>=0.75
  ), canonical_ranked as (
    select
      s.*,
      c.source_record_id as canonical_id,
      c.source_slug as canonical_slug,
      c.overlap_ratio,
      c.canonical_edge_m,
      c.rn
    from strong_osm s
    left join lateral (
      select
        bc.source_record_id,
        bc.source_slug,
        case when extensions.st_area(s.osm_geometry::extensions.geography)>0 then
          extensions.st_area(
            extensions.st_collectionextract(
              extensions.st_intersection(extensions.st_makevalid(s.osm_geometry),extensions.st_makevalid(bc.geometry)),3
            )::extensions.geography
          ) / nullif(extensions.st_area(s.osm_geometry::extensions.geography),0)
        else 0 end as overlap_ratio,
        extensions.st_distance(s.osm_geometry::extensions.geography,bc.geometry::extensions.geography) as canonical_edge_m,
        row_number() over (
          order by
            case when extensions.st_area(s.osm_geometry::extensions.geography)>0 then
              extensions.st_area(
                extensions.st_collectionextract(
                  extensions.st_intersection(extensions.st_makevalid(s.osm_geometry),extensions.st_makevalid(bc.geometry)),3
                )::extensions.geography
              ) / nullif(extensions.st_area(s.osm_geometry::extensions.geography),0)
            else 0 end desc,
            extensions.st_distance(s.osm_geometry::extensions.geography,bc.geometry::extensions.geography),
            bc.source_record_id
        ) as rn
      from decisioning.building_candidates bc
      where bc.geometry OPERATOR(extensions.&&) extensions.st_expand(s.osm_geometry,0.0005)
        and extensions.st_dwithin(s.osm_geometry::extensions.geography,bc.geometry::extensions.geography,30)
      limit 2
    ) c on true
  ), pivoted as (
    select
      target_id,osm_iri,max(osm_geometry) as osm_geometry,
      max(edge_distance_m) as edge_distance_m,
      max(building_tag) as building_tag,
      max(building_name) as building_name,
      max(operator_name) as operator_name,
      max(brand_name) as brand_name,
      max(amenity_tag) as amenity_tag,
      max(addr_housenumber) as addr_housenumber,
      max(addr_street) as addr_street,
      max(addr_city) as addr_city,
      max(addr_postcode) as addr_postcode,
      max(name_sim) as name_sim,
      bool_or(addr_match) as addr_match,
      max(operator_sim) as operator_sim,
      bool_or(class_ok) as class_ok,
      max(corroboration_score) as corroboration_score,
      max(basis) as basis,
      max(canonical_id::text) filter(where rn=1)::uuid as canonical_id,
      max(canonical_slug) filter(where rn=1) as canonical_slug,
      max(overlap_ratio) filter(where rn=1) as top_overlap,
      max(canonical_edge_m) filter(where rn=1) as top_edge,
      max(overlap_ratio) filter(where rn=2) as second_overlap
    from canonical_ranked
    group by target_id,osm_iri
  ), up as (
    insert into intelligence.premium_exterior_osm_identity_candidates(
      target_id,osm_building_iri,osm_geometry,distance_m,building_tag,building_name,operator_name,brand_name,amenity_tag,
      addr_housenumber,addr_street,addr_city,addr_postcode,
      canonical_building_source_record_id,canonical_overlap_ratio,canonical_edge_distance_m,
      status,confidence,evidence,first_observed_at,last_observed_at,
      name_similarity,address_match,operator_similarity,class_compatible,canonical_second_overlap_ratio,canonical_uniqueness_margin,corroboration_basis
    )
    select
      p.target_id,p.osm_iri,p.osm_geometry,p.edge_distance_m,p.building_tag,p.building_name,p.operator_name,p.brand_name,p.amenity_tag,
      p.addr_housenumber,p.addr_street,p.addr_city,p.addr_postcode,
      p.canonical_id,p.top_overlap,p.top_edge,
      'candidate',
      least(0.99,p.corroboration_score * case when coalesce(p.top_overlap,0)>=0.80 then 1.0 else 0.70 end),
      jsonb_strip_nulls(jsonb_build_object(
        'resolver','local_geofabrik_osm_building_identity_v1',
        'refreshed_at',now(),
        'corroboration_score',round(p.corroboration_score::numeric,3),
        'name_similarity',round(p.name_sim::numeric,3),
        'address_match',p.addr_match,
        'operator_similarity',round(p.operator_sim::numeric,3),
        'class_compatible',p.class_ok,
        'canonical_overlap_ratio',round(p.top_overlap::numeric,3),
        'canonical_second_overlap_ratio',round(p.second_overlap::numeric,3),
        'canonical_edge_distance_m',round(p.top_edge::numeric,2),
        'guardrail','Local OSM building candidate evidence does not become building identity until canonical overlap and target corroboration are both strong and unique.'
      )),
      now(),now(),
      p.name_sim,p.addr_match,p.operator_sim,p.class_ok,p.second_overlap,
      case when p.top_overlap is null then null else p.top_overlap-coalesce(p.second_overlap,0) end,
      p.basis
    from pivoted p
    on conflict (target_id,osm_building_iri) do update set
      osm_geometry=excluded.osm_geometry,
      distance_m=excluded.distance_m,
      building_tag=excluded.building_tag,
      building_name=excluded.building_name,
      operator_name=excluded.operator_name,
      brand_name=excluded.brand_name,
      amenity_tag=excluded.amenity_tag,
      addr_housenumber=excluded.addr_housenumber,
      addr_street=excluded.addr_street,
      addr_city=excluded.addr_city,
      addr_postcode=excluded.addr_postcode,
      canonical_building_source_record_id=excluded.canonical_building_source_record_id,
      canonical_overlap_ratio=excluded.canonical_overlap_ratio,
      canonical_edge_distance_m=excluded.canonical_edge_distance_m,
      status=case when intelligence.premium_exterior_osm_identity_candidates.status='reconciled' then 'reconciled' else 'candidate' end,
      confidence=excluded.confidence,
      evidence=coalesce(intelligence.premium_exterior_osm_identity_candidates.evidence,'{}'::jsonb) || excluded.evidence,
      last_observed_at=now(),
      name_similarity=excluded.name_similarity,
      address_match=excluded.address_match,
      operator_similarity=excluded.operator_similarity,
      class_compatible=excluded.class_compatible,
      canonical_second_overlap_ratio=excluded.canonical_second_overlap_ratio,
      canonical_uniqueness_margin=excluded.canonical_uniqueness_margin,
      corroboration_basis=excluded.corroboration_basis
    returning 1
  )
  select count(*) into v_upserted from up;

  select count(*) into v_ready
  from intelligence.v_premium_exterior_local_osm_reconciliation_review_v1
  where auto_reconcile_ready;

  return jsonb_build_object('candidates_upserted',v_upserted,'auto_reconcile_ready',v_ready);
end;
$$;

revoke all on function intelligence.refresh_premium_exterior_local_osm_identity_candidates_v1() from public,anon,authenticated;
grant execute on function intelligence.refresh_premium_exterior_local_osm_identity_candidates_v1() to service_role;

commit;
