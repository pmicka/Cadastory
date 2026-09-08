-- Scout physical-FM awardee identity reconciliation v1
-- Research-only comparison between SAM-derived awardee text and authoritative USAspending
-- recipient identity observed on verified parent/child award chains. Does not auto-create orgs.

create or replace view research.v_physical_fm_awardee_uei_reconciliation as
with federal_identity as (
  select
    f.parent_piid,
    min(f.recipient_name) as usaspending_recipient_name,
    min(f.recipient_uei) as recipient_uei,
    min(f.parent_recipient_name) as ultimate_parent_recipient_name,
    min(f.parent_recipient_uei) as ultimate_parent_recipient_uei,
    count(distinct f.child_generated_award_id) as observed_child_awards,
    count(distinct f.recipient_uei) filter(where f.recipient_uei is not null) as distinct_recipient_ueis
  from procurement.federal_task_orders f
  group by f.parent_piid
), joined as (
  select
    a.acquisition_family_key,
    a.solicitation_number,
    a.title,
    a.award_numbers,
    a.awardees,
    cardinality(a.award_numbers) as sam_award_number_count,
    cardinality(a.awardees) as sam_awardee_count,
    fi.parent_piid,
    fi.usaspending_recipient_name,
    fi.recipient_uei,
    fi.ultimate_parent_recipient_name,
    fi.ultimate_parent_recipient_uei,
    fi.observed_child_awards,
    fi.distinct_recipient_ueis,
    case when cardinality(a.awardees)=1 then a.awardees[1] end as sam_single_awardee_raw
  from procurement.v_acquisition_families a
  join federal_identity fi on fi.parent_piid=any(a.award_numbers)
), normalized as (
  select
    j.*,
    regexp_replace(lower(coalesce(j.sam_single_awardee_raw,'')),'[^a-z0-9]+',' ','g') as sam_norm,
    regexp_replace(lower(coalesce(j.usaspending_recipient_name,'')),'[^a-z0-9]+',' ','g') as usa_norm
  from joined j
)
select
  n.acquisition_family_key,
  n.solicitation_number,
  n.title,
  n.parent_piid,
  n.sam_award_numbers,
  n.sam_award_number_count,
  n.sam_awardee_count,
  n.sam_single_awardee_raw,
  n.usaspending_recipient_name,
  n.recipient_uei,
  n.ultimate_parent_recipient_name,
  n.ultimate_parent_recipient_uei,
  n.observed_child_awards,
  n.distinct_recipient_ueis,
  case
    when n.distinct_recipient_ueis > 1 then 'usaspending_recipient_conflict_requires_review'
    when n.sam_awardee_count <> 1 then 'sam_multi_award_mapping_unresolved'
    when btrim(n.sam_norm) like btrim(n.usa_norm) || '%' or btrim(n.usa_norm) like btrim(n.sam_norm) || '%' then 'sam_usaspending_identity_agree'
    else 'sam_usaspending_identity_conflict'
  end as identity_status,
  case
    when n.distinct_recipient_ueis > 1 then false
    when nullif(n.recipient_uei,'') is null then false
    else true
  end as authoritative_uei_available,
  false as auto_create_organization_authorized,
  case
    when n.distinct_recipient_ueis > 1 then 'review child-award recipient changes before canonicalization'
    when n.sam_awardee_count <> 1 then 'resolve award-number to awardee mapping from authoritative award records'
    when not (btrim(n.sam_norm) like btrim(n.usa_norm) || '%' or btrim(n.usa_norm) like btrim(n.sam_norm) || '%') then 'retain SAM provenance, quarantine conflicting SAM awardee assignment, use verified USAspending parent identity for resolution research'
    else 'use recipient UEI as stable federal identity key; resolve or create canonical organization only in a separate reviewed enrichment step'
  end as next_action
from normalized n;

comment on view research.v_physical_fm_awardee_uei_reconciliation is
  'Research-only identity bridge between SAM awardee text and USAspending recipient UEI/name on verified physical-FM parent award chains. Conflicts are surfaced explicitly; no organization creation or relationship propagation is authorized.';

create or replace view research.v_physical_fm_awardee_identity_summary as
select
  identity_status,
  count(*) as parent_awards,
  count(*) filter(where authoritative_uei_available) as with_authoritative_uei
from research.v_physical_fm_awardee_uei_reconciliation
group by identity_status;

revoke all on research.v_physical_fm_awardee_uei_reconciliation from anon,authenticated;
revoke all on research.v_physical_fm_awardee_identity_summary from anon,authenticated;
grant select on research.v_physical_fm_awardee_uei_reconciliation to service_role;
grant select on research.v_physical_fm_awardee_identity_summary to service_role;
