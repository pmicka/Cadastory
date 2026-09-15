-- Let authoritative parcel-owner evidence classify organization owners even when
-- the older construction/solar source-party classifier is narrower. Also restore
-- only organization owners into the buyer-candidate projection; person/household
-- owners remain durable property evidence only.

create or replace function public.internal_materialize_authoritative_named_buyer_org_v1(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_source jsonb; v_responsible jsonb; v_status text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  v_source:=public.internal_materialize_authoritative_named_buyer_org_source_v1(p_job_id);
  v_status:=coalesce(v_source->>'status','');
  if nullif(v_source->>'organization_id','') is not null
     or v_status in ('already_resolved','ambiguous_existing_organization') then
    return v_source;
  end if;

  -- A source-party `not_business_like` result is not final here: parcel/PVA
  -- organization vocabulary is broader (trusts, property companies, churches,
  -- authorities, etc.). The responsible-party materializer owns that decision.
  v_responsible:=public.internal_materialize_responsible_party_org_v1(p_job_id);
  if nullif(v_responsible->>'organization_id','') is not null
     or coalesce(v_responsible->>'status','') in ('ambiguous_existing_organization','not_business_like') then
    return v_responsible;
  end if;
  return v_source;
end
$$;

revoke all on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) from public,anon,authenticated;
grant execute on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) to service_role;

create or replace function scout.restore_responsible_party_buyer_candidates_v1(p_candidate_keys text[] default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_restored integer:=0;
begin
  with ranked as (
    select e.*,
      row_number() over(partition by e.candidate_key order by e.confidence desc,e.observed_on desc nulls last,e.updated_at desc) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_role='property_owner'
      and e.party_kind='organization'
      and e.evidence_class='authoritative_record'
      and e.confidence>=.95
      and (p_candidate_keys is null or e.candidate_key=any(p_candidate_keys))
  )
  update scout.opportunity_buyer_identities b set
    buyer_name=r.party_name,
    role_code='property_owner_candidate',
    identity_kind='responsible_owner',
    resolution_status='named_responsibility',
    confidence=greatest(b.confidence,.96),
    identity_basis='authoritative_parcel_owner',
    observed_at=coalesce(r.observed_on::timestamptz,b.observed_at),
    last_normalized_at=now()
  from ranked r
  where r.rn=1 and b.candidate_key=r.candidate_key and b.organization_id is null
    and (b.buyer_name is null or b.resolution_status in ('role_only','unresolved')
      or b.identity_basis in ('decision_profile_role_only','unresolved'));
  get diagnostics v_restored=row_count;
  return jsonb_build_object('restored',v_restored);
end
$$;

revoke all on function scout.restore_responsible_party_buyer_candidates_v1(text[]) from public,anon,authenticated;
grant execute on function scout.restore_responsible_party_buyer_candidates_v1(text[]) to service_role;
