-- Cleanup paired with private_trust_household_guard_v1.
-- Explicit private-trust owners are authoritative property evidence only. Any
-- stale authoritative-parcel-owner buyer projection created before the classifier
-- correction is demoted back to the generic role-only exterior-cleaning state.

update scout.opportunity_buyer_identities b
set organization_id=null,
    buyer_name=null,
    organization_type=null,
    role_code=case
      when b.source_kind='exterior_cleaning' then 'facility_owner_or_facilities'
      else b.role_code
    end,
    identity_kind='role_only',
    resolution_status='role_only',
    confidence=least(b.confidence,0.40),
    identity_basis='decision_profile_role_only',
    last_normalized_at=now()
where b.identity_basis='authoritative_parcel_owner'
  and b.organization_id is null
  and exists (
    select 1
    from scout.opportunity_responsible_party_evidence e
    where e.candidate_key=b.candidate_key
      and e.party_role='property_owner'
      and e.party_kind='person_or_household'
      and lower(e.party_name) ~ '(^|[^a-z])(family[[:space:]]+trust|revocable([[:space:]]+living)?[[:space:]]+trust|living[[:space:]]+trust|irrevocable[[:space:]]+trust|trust[[:space:]]+agreement)([^a-z]|$)'
  );

update scout.buyer_resolution_queue q
set buyer_hint=null,
    role_code=case
      when q.source_kind='exterior_cleaning' then 'facility_owner_or_facilities'
      else q.role_code
    end,
    state=case when q.state='researching' then 'researching' else 'pending' end,
    next_attempt_at=case when q.state='researching' then q.next_attempt_at else now() end,
    last_error=null,
    updated_at=now()
where exists (
  select 1
  from scout.opportunity_responsible_party_evidence e
  where e.candidate_key=q.candidate_key
    and e.party_role='property_owner'
    and e.party_kind='person_or_household'
    and lower(e.party_name) ~ '(^|[^a-z])(family[[:space:]]+trust|revocable([[:space:]]+living)?[[:space:]]+trust|living[[:space:]]+trust|irrevocable[[:space:]]+trust|trust[[:space:]]+agreement)([^a-z]|$)'
);

-- Fail closed: explicit private-trust owner evidence must not remain projected
-- as a named buyer or organization after cleanup.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from scout.opportunity_responsible_party_evidence e
  left join scout.buyer_resolution_queue q using(candidate_key)
  left join scout.opportunity_buyer_identities b using(candidate_key)
  where e.party_role='property_owner'
    and e.party_kind='person_or_household'
    and lower(e.party_name) ~ '(^|[^a-z])(family[[:space:]]+trust|revocable([[:space:]]+living)?[[:space:]]+trust|living[[:space:]]+trust|irrevocable[[:space:]]+trust|trust[[:space:]]+agreement)([^a-z]|$)'
    and (
      e.organization_id is not null
      or q.buyer_hint is not null
      or b.organization_id is not null
      or b.buyer_name is not null
      or b.resolution_status<>'role_only'
    );
  if v_bad<>0 then
    raise exception 'private trust owner remained promoted after cleanup';
  end if;
end
$$;