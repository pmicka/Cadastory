-- Scout by Cadastory
-- Materialize the small service-classification result set for search latency.
-- Keep the expensive evidence join as a build view used only during refresh.

alter view cleaning.v_exterior_opportunity_service_classification
  rename to v_exterior_opportunity_service_classification_build;

create table scout.opportunity_service_classifications(
  candidate_key text not null,
  building_source_record_id uuid,
  service_type_id uuid not null references commerce.service_types(id) on delete cascade,
  classification_state text not null check(classification_state in ('supported','investigate','insufficient_evidence')),
  classification_confidence numeric check(classification_confidence is null or classification_confidence between 0 and 1),
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  classifier_version text not null,
  evidence_refreshed_at timestamptz,
  refreshed_at timestamptz not null default now(),
  primary key(candidate_key,service_type_id)
);

create index opportunity_service_classifications_lookup_idx
  on scout.opportunity_service_classifications(service_type_id,classification_state,candidate_key);
create index opportunity_service_classifications_candidate_idx
  on scout.opportunity_service_classifications(candidate_key,classification_state);

alter table scout.opportunity_service_classifications enable row level security;
revoke all on scout.opportunity_service_classifications from anon,authenticated;
grant select,insert,update,delete on scout.opportunity_service_classifications to service_role;

create or replace view cleaning.v_exterior_opportunity_service_classification as
select
  c.candidate_key,
  c.building_source_record_id,
  st.slug as service_slug,
  c.classification_state,
  c.classification_confidence,
  c.reason,
  c.evidence,
  c.classifier_version,
  c.evidence_refreshed_at,
  c.refreshed_at
from scout.opportunity_service_classifications c
join commerce.service_types st on st.id=c.service_type_id;

alter view cleaning.v_exterior_opportunity_service_classification set (security_invoker=true);
revoke all on cleaning.v_exterior_opportunity_service_classification from anon,authenticated;
grant select on cleaning.v_exterior_opportunity_service_classification to service_role;

revoke all on cleaning.v_exterior_opportunity_service_classification_build from anon,authenticated;
grant select on cleaning.v_exterior_opportunity_service_classification_build to service_role;

create or replace function scout.refresh_exterior_opportunity_service_classifications()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_rows integer:=0;
  v_now timestamptz:=clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_exterior_opportunity_service_classifications',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  truncate scout.opportunity_service_classifications;

  insert into scout.opportunity_service_classifications(
    candidate_key,building_source_record_id,service_type_id,classification_state,
    classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at
  )
  select
    b.candidate_key,b.building_source_record_id,st.id,b.classification_state,
    b.classification_confidence,b.reason,b.evidence,b.classifier_version,b.evidence_refreshed_at,v_now
  from cleaning.v_exterior_opportunity_service_classification_build b
  join commerce.service_types st on st.slug=b.service_slug and st.active;

  get diagnostics v_rows=row_count;

  return jsonb_build_object(
    'refreshed_at',v_now,
    'rows',v_rows,
    'supported',(select count(*) from scout.opportunity_service_classifications where classification_state='supported'),
    'investigate',(select count(*) from scout.opportunity_service_classifications where classification_state='investigate'),
    'insufficient_evidence',(select count(*) from scout.opportunity_service_classifications where classification_state='insufficient_evidence'),
    'classifier_version','exterior-service-classifier-v1'
  );
end;
$$;

revoke all on function scout.refresh_exterior_opportunity_service_classifications() from public,anon,authenticated;
grant execute on function scout.refresh_exterior_opportunity_service_classifications() to service_role;

create or replace function scout.refresh_opportunity_search_spine()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_stage integer:=0;
  v_now timestamptz:=clock_timestamp();
  v_classifier jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_opportunity_search_spine',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  truncate scout.opportunity_search_spine_stage;
  insert into scout.opportunity_search_spine_stage
  select * from scout.v_opportunity_spine_build;
  get diagnostics v_stage=row_count;

  update scout.opportunity_search_spine_stage e
  set derived_from_candidate_key=b.candidate_key,
      derivation_kind='timing_amplifier',
      organization_id=coalesce(e.organization_id,b.organization_id),
      effective_contact_available=(e.effective_contact_available or b.effective_contact_available),
      premium_priority_rank=greatest(e.premium_priority_rank,b.premium_priority_rank),
      global_counter_penalty=greatest(e.global_counter_penalty,b.global_counter_penalty),
      global_suppressed=(e.global_suppressed or b.global_suppressed),
      buyer_resolution_status=case when e.buyer_resolution_status='unresolved' then b.buyer_resolution_status else e.buyer_resolution_status end,
      buyer_organization_id=coalesce(e.buyer_organization_id,b.buyer_organization_id),
      buyer_contact_status=case when e.buyer_contact_status='unresolved' then b.buyer_contact_status else e.buyer_contact_status end,
      procurement_status=case when e.procurement_status='unresolved' then b.procurement_status else e.procurement_status end,
      site_access_status=coalesce(e.site_access_status,b.site_access_status),
      last_access_scan_at=coalesce(e.last_access_scan_at,b.last_access_scan_at),
      target_resolution_status=case when e.target_resolution_status='unresolved' then b.target_resolution_status else e.target_resolution_status end,
      target_class=coalesce(e.target_class,b.target_class),
      target_name=coalesce(e.target_name,b.target_name),
      canonical_namespace=coalesce(e.canonical_namespace,b.canonical_namespace),
      canonical_asset_id=coalesce(e.canonical_asset_id,b.canonical_asset_id),
      operational_target_key=coalesce(e.operational_target_key,b.operational_target_key),
      operational_target_type=coalesce(e.operational_target_type,b.operational_target_type),
      buyer_name=coalesce(e.buyer_name,b.buyer_name),
      buyer_organization_type=coalesce(e.buyer_organization_type,b.buyer_organization_type),
      buyer_role_code=coalesce(e.buyer_role_code,b.buyer_role_code),
      buyer_confidence=coalesce(e.buyer_confidence,b.buyer_confidence),
      buyer_route_summary=case when coalesce(e.buyer_route_summary->>'resolution_status','unresolved')='unresolved' then b.buyer_route_summary else e.buyer_route_summary end,
      commercial_scale_status=case when e.commercial_scale_status='unknown' then b.commercial_scale_status else e.commercial_scale_status end,
      scale_metric_count=greatest(coalesce(e.scale_metric_count,0),coalesce(b.scale_metric_count,0)),
      commercial_scale_summary=case when e.commercial_scale_status='unknown' then b.commercial_scale_summary else e.commercial_scale_summary end,
      recurrence_status=case when e.recurrence_status='contextual' then b.recurrence_status else e.recurrence_status end,
      next_due_at=coalesce(e.next_due_at,b.next_due_at),
      recurrence_summary=case when e.recurrence_status='contextual' then b.recurrence_summary else e.recurrence_summary end,
      access_summary=case when coalesce(e.access_summary->>'status','not_modeled')='not_modeled' then b.access_summary else e.access_summary end,
      base_pursuit_state=case
        when (e.global_suppressed or b.global_suppressed) then 'suppressed'
        when e.expires_at is not null and e.expires_at<now() then 'expired'
        when e.valid_from is not null and e.valid_from>now() then 'not_yet_open'
        when e.time_sensitive or (e.ideal_until is not null and e.ideal_until>=now()) then 'active_signal'
        when coalesce(nullif(e.buyer_resolution_status,'unresolved'),b.buyer_resolution_status)='organization_resolved'
             and (e.effective_contact_available or b.effective_contact_available) then 'route_ready_context'
        else 'investigate' end,
      evidence_summary=jsonb_set(
        coalesce(e.evidence_summary,'{}'::jsonb),
        '{derived_from}',
        jsonb_build_object('candidate_key',b.candidate_key,'derivation_kind','timing_amplifier','inheritance','target_buyer_scale_recurrence_access_counter_evidence'),
        true
      ),
      display_name=case
        when e.display_name ~ '^\{?[0-9a-fA-F-]{36}\}?$' then coalesce(nullif(b.target_name,''),nullif(b.display_name,''),e.display_name)
        else e.display_name end
  from scout.opportunity_search_spine_stage b
  where e.source_kind='event_detailing'
    and b.source_kind='exterior_cleaning'
    and b.subject_key=e.subject_key;

  truncate scout.opportunity_search_spine;
  insert into scout.opportunity_search_spine
  select * from scout.opportunity_search_spine_stage;

  v_classifier:=scout.refresh_exterior_opportunity_service_classifications();

  return jsonb_build_object(
    'refreshed_at',v_now,
    'rows',v_stage,
    'contract_version','2.0',
    'derived_event_rows',(select count(*) from scout.opportunity_search_spine_stage where source_kind='event_detailing' and derived_from_candidate_key is not null),
    'service_classifier',v_classifier
  );
end;
$$;

select scout.refresh_exterior_opportunity_service_classifications();
