-- Keep durable organization-owner evidence, buyer identity projection, and buyer
-- resolution queue synchronized when a normalized rebuild or classifier correction
-- requires restoration.
create or replace function scout.restore_responsible_party_buyer_candidates_v1(p_candidate_keys text[] default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_restored integer:=0; v_queue integer:=0;
begin
  create temporary table responsible_party_restore on commit drop as
  select * from (
    select e.candidate_key,e.party_name,e.observed_on,
      row_number() over(partition by e.candidate_key order by e.confidence desc,e.observed_on desc nulls last,e.updated_at desc) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_role='property_owner'
      and e.party_kind='organization'
      and e.evidence_class='authoritative_record'
      and e.confidence>=.95
      and (p_candidate_keys is null or e.candidate_key=any(p_candidate_keys))
  ) x where rn=1;

  update scout.opportunity_buyer_identities b set
    buyer_name=r.party_name,
    role_code='property_owner_candidate',
    identity_kind='responsible_owner',
    resolution_status='named_responsibility',
    confidence=greatest(b.confidence,.96),
    identity_basis='authoritative_parcel_owner',
    observed_at=coalesce(r.observed_on::timestamptz,b.observed_at),
    last_normalized_at=now()
  from responsible_party_restore r
  where b.candidate_key=r.candidate_key and b.organization_id is null
    and (b.buyer_name is null or b.resolution_status in ('role_only','unresolved')
      or b.identity_basis in ('decision_profile_role_only','unresolved','authoritative_parcel_owner'));
  get diagnostics v_restored=row_count;

  update scout.buyer_resolution_queue q set
    buyer_hint=r.party_name,
    role_code='property_owner_candidate',
    state=case when q.state='researching' then 'researching' else 'pending' end,
    next_attempt_at=case when q.state='researching' then q.next_attempt_at else now() end,
    last_error=null,
    updated_at=now()
  from responsible_party_restore r
  where q.candidate_key=r.candidate_key
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null;
  get diagnostics v_queue=row_count;

  return jsonb_build_object('restored',v_restored,'queue_promoted',v_queue);
end
$$;

revoke all on function scout.restore_responsible_party_buyer_candidates_v1(text[]) from public,anon,authenticated;
grant execute on function scout.restore_responsible_party_buyer_candidates_v1(text[]) to service_role;

select scout.restore_responsible_party_buyer_candidates_v1(null);
