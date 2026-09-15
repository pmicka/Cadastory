-- Jefferson PVA owner names can be truncated at the field-width boundary.
-- Treat the observed CHURC truncation as the organization token CHURCH while
-- leaving all other person/household classification rules unchanged.
create or replace function scout.classify_responsible_party_name_v1(p_name text)
returns text
language sql
immutable
set search_path=''
as $$
  select case
    when nullif(btrim(p_name),'') is null then 'unknown'
    when lower(p_name) ~ '(^|[^a-z])(llc|pllc|lp|llp|inc|incorporated|corp|corporation|company|co|holdings|properties|property|realty|real estate|partners|partnership|group|services|service|construction|contracting|contractors|engineering|electric|electrical|mechanical|heating|cooling|hvac|solar|energy|power|coop|cooperative|builders|building|roofing|plumbing|bank|trust|churc(h)?|ministry|temple|association|foundation|authority|district|school|university|college|city|county|government|commonwealth|municipal)([^a-z]|$)'
      then 'organization'
    else 'person_or_household'
  end
$$;

update scout.opportunity_responsible_party_evidence e
set party_kind='organization',updated_at=now()
where e.party_role='property_owner'
  and e.party_kind='person_or_household'
  and e.evidence_class='authoritative_record'
  and scout.classify_responsible_party_name_v1(e.party_name)='organization';

select scout.restore_responsible_party_buyer_candidates_v1(null);
