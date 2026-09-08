-- Scout by Cadastory
-- Glazing extent + pure-water classification hardening.
-- Production migrations applied in order:
--   building_glazing_extent_v1
--   exterior_glazing_extent_classifier_v2
--   facade_visual_verification_glazing_extent_v1
--   exterior_service_classifier_refresh_v2
--   bulk_glass_facade_extent_inference_v1
--   facade_visual_verification_queue_v3
-- This file records the consolidated end-state definitions for review/replay.

alter table decisioning.building_attribute_observations
  add column if not exists glazing_extent text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='decisioning.building_attribute_observations'::regclass
      and conname='building_attribute_observations_glazing_extent_check'
  ) then
    alter table decisioning.building_attribute_observations
      add constraint building_attribute_observations_glazing_extent_check
      check (glazing_extent is null or glazing_extent in (
        'localized','repeated_openings','building_repeated','facade_system'
      ));
  end if;
end $$;

create index if not exists building_attribute_observations_glazing_extent_idx
  on decisioning.building_attribute_observations(glazing_extent)
  where glazing_extent is not null;

-- Evidence-specific backfill for four retained confirmed-glazing observations.
update decisioning.building_attribute_observations
set glazing_extent='building_repeated', updated_at=now()
where id in (
  '0ced8c48-e931-4307-9d25-dd089ad14124'::uuid,
  'aea10ca8-66f6-4b40-9326-9372a0b1ec9f'::uuid,
  '9a9e0a38-fbc3-47c8-930a-54e05b943ba1'::uuid,
  '22d48651-4a33-49c2-97b7-e5da7c6e501c'::uuid
);

update decisioning.building_attribute_observations o
set glazing_extent=case when o.source_feature_kind='building' then 'facade_system' else 'localized' end,
    updated_at=now()
from ingest.sources s
where s.id=o.source_id
  and s.slug in ('overture-buildings','openstreetmap-geofabrik-building-attributes')
  and o.facade_material='glass'
  and o.glazing_extent is null;

create or replace function decisioning.infer_bulk_glass_facade_extent_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_source_slug text;
begin
  if new.glazing_extent is not null or lower(coalesce(new.facade_material,''))<>'glass' then return new; end if;
  select slug into v_source_slug from ingest.sources where id=new.source_id;
  if v_source_slug in ('overture-buildings','openstreetmap-geofabrik-building-attributes') then
    new.glazing_extent:=case when new.source_feature_kind='building' then 'facade_system' else 'localized' end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_infer_bulk_glass_facade_extent_v1 on decisioning.building_attribute_observations;
create trigger trg_infer_bulk_glass_facade_extent_v1
before insert or update of facade_material,glazing_extent,source_feature_kind,source_id
on decisioning.building_attribute_observations
for each row execute function decisioning.infer_bulk_glass_facade_extent_v1();
revoke all on function decisioning.infer_bulk_glass_facade_extent_v1() from public,anon,authenticated;

create or replace view decisioning.v_building_resolved_glazing_extent_v1 as
with ranked as (
  select m.building_source_record_id,o.glazing_extent,
    least(0.99,greatest(0::numeric,coalesce(m.confidence,0)*coalesce(o.confidence,0))) glazing_extent_confidence,
    s.slug glazing_extent_source_slug,o.source_feature_kind,o.observed_at glazing_extent_observed_at,
    row_number() over (
      partition by m.building_source_record_id
      order by case o.glazing_extent when 'facade_system' then 4 when 'building_repeated' then 3 when 'repeated_openings' then 2 when 'localized' then 1 else 0 end desc,
        least(0.99,greatest(0::numeric,coalesce(m.confidence,0)*coalesce(o.confidence,0))) desc,
        case o.source_feature_kind when 'building' then 2 else 1 end desc,o.observed_at desc,o.id
    ) rn
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  join ingest.sources s on s.id=o.source_id
  where o.glazing_extent is not null
)
select building_source_record_id,glazing_extent,glazing_extent_confidence,glazing_extent_source_slug,
  source_feature_kind glazing_extent_feature_kind,glazing_extent_observed_at,
  glazing_extent in ('building_repeated','facade_system') commercially_meaningful_glazing_extent
from ranked where rn=1;
revoke all on decisioning.v_building_resolved_glazing_extent_v1 from anon,authenticated;
grant select on decisioning.v_building_resolved_glazing_extent_v1 to service_role;

create or replace view cleaning.v_exterior_opportunity_service_classification_build_v2 as
select c.candidate_key,c.building_source_record_id,c.service_slug,
  case when c.service_slug<>'pure-water-window-cleaning' then c.classification_state
       when g.glazing_extent in ('building_repeated','facade_system') and coalesce(g.glazing_extent_confidence,0)>=0.70 then 'supported'
       when g.glazing_extent is not null or nullif(c.evidence->>'resolved_glazing_signal','') is not null
            or coalesce((c.evidence->>'premium_confirmed_glazed')::boolean,false)
            or coalesce((c.evidence->>'premium_high_glazing_likelihood')::boolean,false) then 'investigate'
       else 'insufficient_evidence' end classification_state,
  case when c.service_slug='pure-water-window-cleaning' and g.glazing_extent is not null then g.glazing_extent_confidence else c.classification_confidence end classification_confidence,
  case when c.service_slug<>'pure-water-window-cleaning' then c.reason
       when g.glazing_extent in ('building_repeated','facade_system') and coalesce(g.glazing_extent_confidence,0)>=0.70
         then 'Resolved glazing evidence shows building-scale repeated glazing or a facade glazing system, supporting investigation for pure-water exterior glass cleaning.'
       when g.glazing_extent in ('localized','repeated_openings')
         then 'Glazing is documented, but its resolved extent is not yet strong enough to establish a building-scale pure-water exterior glass opportunity.'
       when nullif(c.evidence->>'resolved_glazing_signal','') is not null
            or coalesce((c.evidence->>'premium_confirmed_glazed')::boolean,false)
            or coalesce((c.evidence->>'premium_high_glazing_likelihood')::boolean,false)
         then 'Glazing presence or likelihood is documented, but glazing extent is unresolved; verify whether exterior glass is commercially meaningful before specializing this opportunity.'
       else 'Scout does not currently have enough glazing evidence to specialize this exterior-cleaning opportunity as pure-water glass work.' end reason,
  case when c.service_slug='pure-water-window-cleaning' then coalesce(c.evidence,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
       'resolved_glazing_extent',g.glazing_extent,'resolved_glazing_extent_confidence',g.glazing_extent_confidence,
       'resolved_glazing_extent_source_slug',g.glazing_extent_source_slug,'resolved_glazing_extent_feature_kind',g.glazing_extent_feature_kind,
       'commercially_meaningful_glazing_extent',g.commercially_meaningful_glazing_extent,
       'glazing_extent_guardrail','Glazing presence alone is not sufficient. Only building_repeated or facade_system extent can automatically support a pure-water exterior glass specialization; localized or ordinary repeated openings remain verification cues.')) else c.evidence end evidence,
  case when c.service_slug='pure-water-window-cleaning' then 'exterior-service-classifier-v2' else c.classifier_version end classifier_version,
  case when c.service_slug='pure-water-window-cleaning' and g.glazing_extent_observed_at is not null
       then greatest(coalesce(c.evidence_refreshed_at,'1970-01-01'::timestamptz),g.glazing_extent_observed_at) else c.evidence_refreshed_at end evidence_refreshed_at
from cleaning.v_exterior_opportunity_service_classification_build c
left join decisioning.v_building_resolved_glazing_extent_v1 g on g.building_source_record_id=c.building_source_record_id;
revoke all on cleaning.v_exterior_opportunity_service_classification_build_v2 from anon,authenticated;
grant select on cleaning.v_exterior_opportunity_service_classification_build_v2 to service_role;

-- Individual facade verification writes use this bounded delta. Full classifier
-- rebuilds remain authoritative during canonical opportunity-spine refreshes.
create or replace function scout.apply_facade_verification_classification_delta(
  p_building_source_record_id uuid,p_facade_material text,p_glazing_signal text,p_confidence numeric,
  p_source_slug text default 'scout-facade-visual-verification'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_masonry_id uuid; v_glass_id uuid;
  v_effective_conf numeric:=least(0.99,greatest(0::numeric,coalesce(p_confidence,0)*0.99));
  v_masonry_rows integer:=0; v_glass_rows integer:=0;
  v_glazing_extent text; v_glazing_extent_conf numeric; v_glazing_extent_source text;
  v_glass_state text; v_glass_reason text;
begin
  select id into v_masonry_id from commerce.service_types where slug='masonry-restoration-cleaning' and active limit 1;
  select id into v_glass_id from commerce.service_types where slug='pure-water-window-cleaning' and active limit 1;

  if v_masonry_id is not null and lower(coalesce(p_facade_material,'')) in ('brick','stone','masonry','limestone') then
    insert into scout.opportunity_service_classifications(candidate_key,building_source_record_id,service_type_id,classification_state,classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at)
    select s.candidate_key,p_building_source_record_id,v_masonry_id,'supported',v_effective_conf,
      'Resolved facade/material evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.',
      jsonb_strip_nulls(jsonb_build_object('resolved_facade_material',p_facade_material,'resolved_facade_evidence_confidence',v_effective_conf,'resolved_facade_evidence_source_slug',p_source_slug,
        'guardrail','Verified masonry material supports service investigation; it does not establish treatment compatibility, cleaning need, customer demand, or suitability of any specific restoration chemical.')),
      'exterior-service-classifier-v1',now(),now()
    from scout.opportunity_search_spine s
    where s.canonical_asset_id=p_building_source_record_id and s.target_class='building' and s.canonical_namespace='decisioning.building_candidates' and s.service_slugs @> array['exterior-cleaning']::text[]
    on conflict(candidate_key,service_type_id) do update set building_source_record_id=excluded.building_source_record_id,classification_state=excluded.classification_state,
      classification_confidence=excluded.classification_confidence,reason=excluded.reason,evidence=coalesce(scout.opportunity_service_classifications.evidence,'{}'::jsonb)||excluded.evidence,
      classifier_version=excluded.classifier_version,evidence_refreshed_at=excluded.evidence_refreshed_at,refreshed_at=excluded.refreshed_at;
    get diagnostics v_masonry_rows=row_count;
  end if;

  if v_glass_id is not null and (lower(coalesce(p_facade_material,''))='glass' or lower(coalesce(p_glazing_signal,'')) in ('glass_facade_present','confirmed_glazed')) then
    select glazing_extent,glazing_extent_confidence,glazing_extent_source_slug into v_glazing_extent,v_glazing_extent_conf,v_glazing_extent_source
    from decisioning.v_building_resolved_glazing_extent_v1 where building_source_record_id=p_building_source_record_id;
    if v_glazing_extent in ('building_repeated','facade_system') and coalesce(v_glazing_extent_conf,0)>=0.70 then
      v_glass_state:='supported'; v_glass_reason:='Resolved glazing evidence shows building-scale repeated glazing or a facade glazing system, supporting investigation for pure-water exterior glass cleaning.';
    else
      v_glass_state:='investigate'; v_glass_reason:='Glazing is documented, but building-scale glazing extent is not yet resolved strongly enough to support a pure-water exterior glass specialization.';
    end if;
    insert into scout.opportunity_service_classifications(candidate_key,building_source_record_id,service_type_id,classification_state,classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at)
    select s.candidate_key,p_building_source_record_id,v_glass_id,v_glass_state,coalesce(v_glazing_extent_conf,v_effective_conf),v_glass_reason,
      jsonb_strip_nulls(jsonb_build_object('resolved_glazing_signal',coalesce(p_glazing_signal,case when lower(coalesce(p_facade_material,''))='glass' then 'glass_facade_present' end),
        'resolved_glazing_confidence',v_effective_conf,'resolved_glazing_extent',v_glazing_extent,'resolved_glazing_extent_confidence',v_glazing_extent_conf,
        'resolved_glazing_extent_source_slug',v_glazing_extent_source,'commercially_meaningful_glazing_extent',(v_glazing_extent in ('building_repeated','facade_system')),
        'guardrail','Verified glazing presence does not establish exterior glass area, cleanability, access, or customer demand. Only building_repeated or facade_system extent can automatically support the pure-water specialization.')),
      'exterior-service-classifier-v2',now(),now()
    from scout.opportunity_search_spine s
    where s.canonical_asset_id=p_building_source_record_id and s.target_class='building' and s.canonical_namespace='decisioning.building_candidates' and s.service_slugs @> array['exterior-cleaning']::text[]
    on conflict(candidate_key,service_type_id) do update set building_source_record_id=excluded.building_source_record_id,classification_state=excluded.classification_state,
      classification_confidence=excluded.classification_confidence,reason=excluded.reason,evidence=coalesce(scout.opportunity_service_classifications.evidence,'{}'::jsonb)||excluded.evidence,
      classifier_version=excluded.classifier_version,evidence_refreshed_at=excluded.evidence_refreshed_at,refreshed_at=excluded.refreshed_at;
    get diagnostics v_glass_rows=row_count;
  end if;
  return jsonb_build_object('building_source_record_id',p_building_source_record_id,'masonry_rows',v_masonry_rows,'glass_rows',v_glass_rows,
    'effective_confidence',v_effective_conf,'glazing_extent',v_glazing_extent,'glazing_extent_confidence',v_glazing_extent_conf,'mode','incremental_facade_delta_v2');
end; $$;
revoke all on function scout.apply_facade_verification_classification_delta(uuid,text,text,numeric,text) from public,anon,authenticated;
grant execute on function scout.apply_facade_verification_classification_delta(uuid,text,text,numeric,text) to service_role;

create or replace view decisioning.v_facade_visual_verification_queue_v3 as
select q.*,g.glazing_extent,g.glazing_extent_confidence,g.glazing_extent_source_slug,g.glazing_extent_feature_kind,g.commercially_meaningful_glazing_extent,
  case when g.glazing_extent in ('building_repeated','facade_system') then 'extent_resolved_meaningful'
       when g.glazing_extent in ('localized','repeated_openings') then 'extent_needs_upgrade_verification'
       when q.glazing_signal is not null then 'presence_known_extent_unresolved'
       else 'presence_and_extent_unresolved' end glazing_verification_status
from decisioning.v_facade_visual_verification_queue_v2 q
left join decisioning.v_building_resolved_glazing_extent_v1 g on g.building_source_record_id=q.building_source_record_id;
revoke all on decisioning.v_facade_visual_verification_queue_v3 from anon,authenticated;
grant select on decisioning.v_facade_visual_verification_queue_v3 to service_role;
