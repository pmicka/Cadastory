-- Retract the two development-acceptance false positives and require a verified
-- first-party domain match for all household-owner fallback operator evidence.

create or replace function research.guard_household_operator_first_party_v1()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if new.party_role='operator'
     and coalesce(new.attributes->>'resolution_scope','')='household_owner_fallback'
     and coalesce((new.attributes->>'first_party_domain_match')::boolean,false)=false then
    raise exception 'household fallback operator evidence requires first-party domain match';
  end if;
  return new;
end
$$;
revoke all on function research.guard_household_operator_first_party_v1() from public,anon,authenticated;

do $$
begin
  if not exists(
    select 1 from pg_trigger
    where tgname='trg_guard_household_operator_first_party_v1'
      and tgrelid='scout.opportunity_responsible_party_evidence'::regclass
  ) then
    execute 'create trigger trg_guard_household_operator_first_party_v1
      before insert or update on scout.opportunity_responsible_party_evidence
      for each row execute function research.guard_household_operator_first_party_v1()';
  end if;
end
$$;

create temporary table bad_household_operator_acceptance on commit drop as
select e.id evidence_id,e.candidate_key,e.organization_id,
       nullif(e.attributes->>'document_evidence_job_id','')::uuid job_id
from scout.opportunity_responsible_party_evidence e
where e.party_role='operator'
  and e.attributes->>'resolution_scope'='household_owner_fallback'
  and lower(regexp_replace(split_part(regexp_replace(e.source_url,'^https?://','','i'),'/',1),'^www\.','','i'))
      in ('greatschools.org','usnews.com');

-- These rows never projected into buyer identity or contact research. Fail closed if that changed.
do $$ declare v_bad integer; begin
  select count(*) into v_bad
  from bad_household_operator_acceptance x
  where exists(select 1 from scout.opportunity_buyer_identities b where b.candidate_key=x.candidate_key and b.organization_id=x.organization_id)
     or exists(select 1 from research.responsible_party_contact_job_candidates l where l.candidate_key=x.candidate_key and l.responsible_organization_id=x.organization_id);
  if v_bad<>0 then raise exception 'cannot auto-retract household acceptance rows after downstream projection'; end if;
end $$;

delete from scout.opportunity_responsible_party_evidence e
using bad_household_operator_acceptance x
where e.id=x.evidence_id;

update research.document_evidence_jobs j
set state='queued',next_attempt_at=now(),claimed_at=null,lease_until=null,completed_at=null,last_error=null,exhaustion_reason=null,
    organization_name=null,
    context=(coalesce(j.context,'{}'::jsonb)-'organization_id'-'organization_name'),
    outcome_metadata=(coalesce(j.outcome_metadata,'{}'::jsonb)-'organization_id')||jsonb_build_object(
      'phase3_acceptance_retracted',true,
      'retraction_reason','third_party_structured_address_is_not_first_party_identity',
      'identity_projection','suppressed','outbound_contact_performed',false),
    updated_at=now()
from bad_household_operator_acceptance x
where j.id=x.job_id;

delete from core.organizations o
using (select distinct organization_id from bad_household_operator_acceptance where organization_id is not null) x
where o.id=x.organization_id
  and o.attributes->>'identity_source'='household_site_exact_address_first_party'
  and not exists(select 1 from scout.opportunity_responsible_party_evidence e where e.organization_id=o.id)
  and not exists(select 1 from core.organization_contact_points c where c.organization_id=o.id)
  and not exists(select 1 from scout.opportunity_buyer_identities b where b.organization_id=o.id);

do $$ declare v_bad integer; begin
  select count(*) into v_bad
  from scout.opportunity_responsible_party_evidence e
  where e.party_role='operator' and e.attributes->>'resolution_scope'='household_owner_fallback'
    and coalesce((e.attributes->>'first_party_domain_match')::boolean,false)=false;
  if v_bad<>0 then raise exception 'unguarded household operator evidence remains: %',v_bad; end if;
end $$;