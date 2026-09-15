-- A parcel can authoritatively identify a person/household owner without identifying
-- an organization that Scout should contact. Preserve the owner as property evidence,
-- but do not promote that personal name into the autonomous buyer web-research lane.

create or replace function research.guard_person_responsible_party_identity_promotion_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_person boolean:=false;
begin
  if new.identity_basis <> 'authoritative_parcel_owner' then return new; end if;
  select exists(
    select 1 from scout.opportunity_responsible_party_evidence e
    where e.candidate_key=new.candidate_key
      and e.party_role='property_owner'
      and e.party_kind='person_or_household'
      and e.evidence_class='authoritative_record'
      and e.confidence>=.95
      and e.party_name_normalized=public.scout_normalize_business_name(new.buyer_name)
  ) into v_person;
  if not v_person then return new; end if;

  -- Retain the pre-resolution buyer state. The authoritative person/household
  -- remains available in opportunity_responsible_party_evidence for future
  -- manager/operator research, but is not treated as a buyer organization.
  new.organization_id:=old.organization_id;
  new.buyer_name:=old.buyer_name;
  new.organization_type:=old.organization_type;
  new.role_code:=old.role_code;
  new.identity_kind:=old.identity_kind;
  new.resolution_status:=old.resolution_status;
  new.confidence:=old.confidence;
  new.identity_basis:=old.identity_basis;
  new.observed_at:=old.observed_at;
  return new;
end
$$;

revoke all on function research.guard_person_responsible_party_identity_promotion_v1() from public,anon,authenticated,service_role;
drop trigger if exists trg_guard_person_responsible_party_identity_promotion_v1 on scout.opportunity_buyer_identities;
create trigger trg_guard_person_responsible_party_identity_promotion_v1
before update on scout.opportunity_buyer_identities
for each row execute function research.guard_person_responsible_party_identity_promotion_v1();

create or replace function research.guard_person_responsible_party_queue_promotion_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_person boolean:=false;
begin
  if new.role_code is distinct from 'property_owner_candidate' or nullif(btrim(new.buyer_hint),'') is null then
    return new;
  end if;
  select exists(
    select 1 from scout.opportunity_responsible_party_evidence e
    where e.candidate_key=new.candidate_key
      and e.party_role='property_owner'
      and e.party_kind='person_or_household'
      and e.evidence_class='authoritative_record'
      and e.confidence>=.95
      and e.party_name_normalized=public.scout_normalize_business_name(new.buyer_hint)
  ) into v_person;
  if not v_person then return new; end if;

  new.buyer_hint:=old.buyer_hint;
  new.role_code:=old.role_code;
  new.state:='pending';
  new.next_attempt_at:=greatest(coalesce(old.next_attempt_at,now()),now()+interval '7 days');
  new.last_error:='authoritative property owner is a person/household; organization buyer remains unresolved and requires manager/operator evidence';
  return new;
end
$$;

revoke all on function research.guard_person_responsible_party_queue_promotion_v1() from public,anon,authenticated,service_role;
drop trigger if exists trg_guard_person_responsible_party_queue_promotion_v1 on scout.buyer_resolution_queue;
create trigger trg_guard_person_responsible_party_queue_promotion_v1
before update on scout.buyer_resolution_queue
for each row execute function research.guard_person_responsible_party_queue_promotion_v1();
