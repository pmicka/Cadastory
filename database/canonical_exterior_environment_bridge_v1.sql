-- Scout by Cadastory
-- Canonical exterior-environment bridge.
-- Reuses legacy FEMA-structure environmental context only when the current
-- canonical footprint match is very strong. No growth/treatment claim is made.

create table if not exists cleaning.canonical_environment_context_links (
  canonical_building_source_record_id uuid primary key references ingest.raw_records(id) on delete cascade,
  environment_source_record_id uuid references cleaning.exterior_environment_context(building_source_record_id) on delete set null,
  match_status text not null check (match_status in ('accepted','ambiguous','low_overlap','no_match')),
  candidate_match_count integer not null default 0 check (candidate_match_count >= 0),
  best_overlap_ratio numeric,
  best_iou numeric,
  second_overlap_ratio numeric,
  second_iou numeric,
  match_confidence numeric check (match_confidence is null or (match_confidence >= 0 and match_confidence <= 1)),
  evidence jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);

alter table cleaning.canonical_environment_context_links enable row level security;
revoke all on cleaning.canonical_environment_context_links from anon, authenticated;
grant select,insert,update,delete on cleaning.canonical_environment_context_links to service_role;

create index if not exists canonical_environment_context_links_status_idx
  on cleaning.canonical_environment_context_links(match_status, refreshed_at desc);
create index if not exists canonical_environment_context_links_environment_idx
  on cleaning.canonical_environment_context_links(environment_source_record_id)
  where environment_source_record_id is not null;

create or replace function cleaning.refresh_canonical_exterior_environment_context()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now timestamptz:=clock_timestamp();
  v_targets integer:=0;
  v_accepted integer:=0;
  v_ambiguous integer:=0;
  v_low integer:=0;
  v_none integer:=0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('cleaning.refresh_canonical_exterior_environment_context',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  create temporary table _scout_env_bridge on commit drop as
  with target as (
    select distinct s.canonical_asset_id canonical_id,b.geometry
    from scout.opportunity_search_spine s
    join decisioning.building_candidates b on b.source_record_id=s.canonical_asset_id
    where s.service_slugs @> array['exterior-cleaning']::text[]
      and s.target_class='building'
      and s.canonical_namespace='decisioning.building_candidates'
      and s.canonical_asset_id is not null
      and b.geometry is not null
  ), legacy as (
    select e.building_source_record_id environment_id,r.geometry,e.*
    from cleaning.exterior_environment_context e
    join ingest.raw_records r on r.id=e.building_source_record_id
    join ingest.sources src on src.id=r.source_id and src.slug='fema-usa-structures-current'
    where r.geometry is not null
      and not (coalesce(e.evidence,'{}'::jsonb) ? 'canonical_bridge')
  ), matches as (
    select t.canonical_id,l.environment_id,
      extensions.ST_Area(extensions.ST_Intersection(extensions.ST_MakeValid(t.geometry),extensions.ST_MakeValid(l.geometry))) /
        nullif(least(extensions.ST_Area(extensions.ST_MakeValid(t.geometry)),extensions.ST_Area(extensions.ST_MakeValid(l.geometry))),0) overlap_ratio,
      extensions.ST_Area(extensions.ST_Intersection(extensions.ST_MakeValid(t.geometry),extensions.ST_MakeValid(l.geometry))) /
        nullif(extensions.ST_Area(extensions.ST_Union(extensions.ST_MakeValid(t.geometry),extensions.ST_MakeValid(l.geometry))),0) iou
    from target t
    join legacy l on l.geometry OPERATOR(extensions.&&) t.geometry
      and extensions.ST_Intersects(extensions.ST_MakeValid(l.geometry),extensions.ST_MakeValid(t.geometry))
  ), ranked as (
    select m.*,
      row_number() over(partition by canonical_id order by overlap_ratio desc nulls last,iou desc nulls last,environment_id) rn,
      count(*) over(partition by canonical_id) hit_count
    from matches m
  ), summary as (
    select t.canonical_id,
      max(r.hit_count) hit_count,
      (max(r.environment_id::text) filter(where r.rn=1))::uuid best_environment_id,
      max(r.overlap_ratio) filter(where r.rn=1) best_overlap,
      max(r.iou) filter(where r.rn=1) best_iou,
      max(r.overlap_ratio) filter(where r.rn=2) second_overlap,
      max(r.iou) filter(where r.rn=2) second_iou
    from target t left join ranked r on r.canonical_id=t.canonical_id
    group by t.canonical_id
  )
  select s.*,
    case
      when coalesce(s.hit_count,0)=0 then 'no_match'
      when coalesce(s.best_overlap,0)<0.90 or coalesce(s.best_iou,0)<0.80 then 'low_overlap'
      when s.second_overlap is not null
       and s.second_overlap>0.10
       and (s.best_overlap-s.second_overlap)<0.25 then 'ambiguous'
      else 'accepted'
    end match_status,
    case when s.best_overlap is null or s.best_iou is null then null
         else least(0.99,greatest(0::numeric,((s.best_overlap+s.best_iou)/2)::numeric)) end match_confidence
  from summary s;

  select count(*) into v_targets from _scout_env_bridge;

  delete from cleaning.canonical_environment_context_links l
  where l.canonical_building_source_record_id in (select canonical_id from _scout_env_bridge);

  insert into cleaning.canonical_environment_context_links(
    canonical_building_source_record_id,environment_source_record_id,match_status,candidate_match_count,
    best_overlap_ratio,best_iou,second_overlap_ratio,second_iou,match_confidence,evidence,refreshed_at
  )
  select canonical_id,
    case when match_status='accepted' then best_environment_id else null end,
    match_status,coalesce(hit_count,0),best_overlap,best_iou,second_overlap,second_iou,match_confidence,
    jsonb_strip_nulls(jsonb_build_object(
      'bridge_version','fema-overlap-v1',
      'source_population','fema-usa-structures-current',
      'target_population','current canonical exterior-cleaning opportunity buildings',
      'acceptance_rule',jsonb_build_object('min_overlap_ratio',0.90,'min_iou',0.80,'ambiguous_second_overlap_gt',0.10,'min_best_second_gap_when_ambiguous',0.25),
      'guardrail','A high-confidence footprint crosswalk transfers environmental context to the canonical building identity; it does not prove visible biological growth or treatment need.'
    )),v_now
  from _scout_env_bridge;

  delete from cleaning.exterior_environment_context e
  where coalesce(e.evidence->'canonical_bridge'->>'bridge_version','')='fema-overlap-v1'
    and e.building_source_record_id in (select canonical_id from _scout_env_bridge);

  insert into cleaning.exterior_environment_context(
    building_source_record_id,location,appearance_sensitivity,nearest_dust_source_key,nearest_dust_source_name,
    dust_source_kind,dust_distance_m,tree_canopy_pct,humidity_context,biological_growth_context,can_open_window,
    confidence,evidence,refreshed_at
  )
  select l.canonical_building_source_record_id,e.location,e.appearance_sensitivity,e.nearest_dust_source_key,e.nearest_dust_source_name,
    e.dust_source_kind,e.dust_distance_m,e.tree_canopy_pct,e.humidity_context,e.biological_growth_context,e.can_open_window,
    least(coalesce(e.confidence,1),coalesce(l.match_confidence,1)),
    coalesce(e.evidence,'{}'::jsonb) || jsonb_build_object('canonical_bridge',jsonb_build_object(
      'bridge_version','fema-overlap-v1','environment_source_record_id',l.environment_source_record_id,
      'match_confidence',l.match_confidence,'overlap_ratio',l.best_overlap_ratio,'iou',l.best_iou,
      'crosswalk_refreshed_at',l.refreshed_at,
      'guardrail','Environmental context was transferred through a high-confidence footprint crosswalk. It remains proxy evidence, not direct observation of staining or biological growth.'
    )),e.refreshed_at
  from cleaning.canonical_environment_context_links l
  join cleaning.exterior_environment_context e on e.building_source_record_id=l.environment_source_record_id
  where l.match_status='accepted'
    and l.canonical_building_source_record_id in (select canonical_id from _scout_env_bridge)
  on conflict(building_source_record_id) do update set
    location=excluded.location,appearance_sensitivity=excluded.appearance_sensitivity,
    nearest_dust_source_key=excluded.nearest_dust_source_key,nearest_dust_source_name=excluded.nearest_dust_source_name,
    dust_source_kind=excluded.dust_source_kind,dust_distance_m=excluded.dust_distance_m,
    tree_canopy_pct=excluded.tree_canopy_pct,humidity_context=excluded.humidity_context,
    biological_growth_context=excluded.biological_growth_context,can_open_window=excluded.can_open_window,
    confidence=excluded.confidence,evidence=excluded.evidence,refreshed_at=excluded.refreshed_at;

  select count(*) filter(where match_status='accepted'),count(*) filter(where match_status='ambiguous'),
         count(*) filter(where match_status='low_overlap'),count(*) filter(where match_status='no_match')
    into v_accepted,v_ambiguous,v_low,v_none
  from _scout_env_bridge;

  return jsonb_build_object('refreshed_at',v_now,'targets',v_targets,'accepted',v_accepted,'ambiguous',v_ambiguous,'low_overlap',v_low,'no_match',v_none,'bridge_version','fema-overlap-v1');
end;
$$;

revoke all on function cleaning.refresh_canonical_exterior_environment_context() from public,anon,authenticated;
grant execute on function cleaning.refresh_canonical_exterior_environment_context() to service_role;
