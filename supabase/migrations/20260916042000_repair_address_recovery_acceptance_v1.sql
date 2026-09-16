-- Repair bounded Phase 4 acceptance artifacts after worker v5 added paginated
-- LOJIC address queries and corrected Jefferson PVA property-address parsing.

update research.responsible_party_resolution_jobs j
set state='queued',
    completed_at=null,
    exhaustion_reason=null,
    requery_after=null,
    next_attempt_at=now(),
    updated_at=now()
where j.profile_key='ky_jefferson_pva_address_lrsn'
  and j.state='needs_review'
  and j.attempt_count<j.max_attempts
  and j.exhaustion_reason='bounded LOJIC address-point query exceeded result limit';

update scout.opportunity_responsible_party_evidence e
set attributes=e.attributes-'pva_primary_site_address',
    updated_at=now()
where e.attributes->>'resolution_mode'='address_point_lrsn_recovery'
  and e.attributes->>'pva_primary_site_address'='Jefferson County PVA';

-- No repaired job may bypass the isolated acceptance lane.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from research.responsible_party_source_profiles p
  where p.profile_key='ky_jefferson_pva_address_lrsn'
    and coalesce((p.attributes->>'automated_dispatch')::boolean,true)<>false;
  if v_bad<>0 then raise exception 'Jefferson address recovery automated before acceptance'; end if;
end
$$;