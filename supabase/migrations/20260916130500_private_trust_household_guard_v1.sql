-- Deployment acceptance hotfix: private/family trust property owners are
-- household/private-owner evidence, not organization/buyer targets.
--
-- This is intentionally conservative. Institutional organizations that merely
-- contain the token "trust" remain organizations unless the name also carries
-- an explicit private-trust phrase such as FAMILY TRUST or REVOCABLE TRUST.

create or replace function scout.classify_responsible_party_name_v1(p_name text)
returns text
language sql
immutable
set search_path=''
as $$
  select case
    when nullif(btrim(p_name),'') is null then 'unknown'
    when lower(p_name) ~ '(^|[^a-z])(family[[:space:]]+trust|revocable([[:space:]]+living)?[[:space:]]+trust|living[[:space:]]+trust|irrevocable[[:space:]]+trust|trust[[:space:]]+agreement)([^a-z]|$)'
      then 'person_or_household'
    when lower(p_name) ~ '(^|[^a-z])(llc|pllc|lp|llp|inc|incorporated|corp|corporation|company|co|holdings|properties|property|realty|real estate|partners|partnership|group|services|service|construction|contracting|contractors|engineering|electric|electrical|mechanical|heating|cooling|hvac|solar|energy|power|coop|cooperative|builders|building|roofing|plumbing|bank|trust|churc(h)?|ministry|temple|association|foundation|authority|district|school|university|college|city|county|government|commonwealth|municipal|apartments|league)([^a-z]|$)'
      then 'organization'
    else 'person_or_household'
  end
$$;

update scout.opportunity_responsible_party_evidence
set party_kind='person_or_household',
    organization_id=null,
    updated_at=now()
where party_role='property_owner'
  and party_kind='organization'
  and scout.classify_responsible_party_name_v1(party_name)='person_or_household';

-- Fail closed: no explicit private-trust phrase may remain classified as an
-- organization in responsible-party property-owner evidence.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from scout.opportunity_responsible_party_evidence
  where party_role='property_owner'
    and party_kind='organization'
    and lower(party_name) ~ '(^|[^a-z])(family[[:space:]]+trust|revocable([[:space:]]+living)?[[:space:]]+trust|living[[:space:]]+trust|irrevocable[[:space:]]+trust|trust[[:space:]]+agreement)([^a-z]|$)';
  if v_bad<>0 then
    raise exception 'private trust property owner remained organization-classified';
  end if;
end
$$;