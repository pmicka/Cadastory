-- Phase 1 cleanup/hardening.
-- Close the lone pasture-soil RLS gap and cover the FK paths surfaced by the
-- responsible-party and pasture-soil advisor audit. This migration is additive
-- and does not broaden API/table privileges.

alter table agriculture.pasture_soil_point_samples_v1 enable row level security;

create index if not exists pasture_soil_point_samples_v1_source_id_idx
  on agriculture.pasture_soil_point_samples_v1(source_id);

create index if not exists responsible_party_contact_job_candidates_evidence_idx
  on research.responsible_party_contact_job_candidates(responsible_party_evidence_id);

create index if not exists responsible_party_resolution_deferrals_profile_idx
  on research.responsible_party_resolution_deferrals(profile_key);

create index if not exists opportunity_responsible_party_evidence_organization_idx
  on scout.opportunity_responsible_party_evidence(organization_id);
