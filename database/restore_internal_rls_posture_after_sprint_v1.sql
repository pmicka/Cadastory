-- Production migration mirror: restore_internal_rls_posture_after_sprint_v1
-- Applied to Supabase project ufpkjaadmmpmeogzhrcq on 2026-09-09.
-- These internal application tables had no anon/authenticated/PUBLIC grants,
-- but RLS itself had drifted off. Restore defense in depth without adding any
-- public policy or weakening existing authorization/exposure contracts.

alter table cleaning.citra_shield_candidate_pilot_v1 enable row level security;
alter table cleaning.field_chemistry_outcomes enable row level security;
alter table cleaning.product_regulatory_assessments enable row level security;
alter table cleaning.specialist_identity_resolutions enable row level security;
alter table cleaning.surface_condition_observations enable row level security;
alter table decisioning.building_lifecycle_observations enable row level security;
alter table decisioning.cleaning_water_enrichment_queue enable row level security;
alter table decisioning.cleaning_water_sources enable row level security;
alter table intelligence.premium_exterior_building_link_candidates enable row level security;
alter table intelligence.premium_exterior_raw_building_identity_evidence enable row level security;
alter table procurement.federal_parent_idvs enable row level security;
alter table procurement.federal_task_orders enable row level security;
alter table procurement.opportunities enable row level security;
alter table research.bridge_surface_work_evidence enable row level security;
alter table research.federal_infrastructure_aliases enable row level security;
alter table research.operator_field_hypotheses enable row level security;
alter table research.painting_signal_target_readiness enable row level security;
alter table research.usaspending_parent_vehicle_targets enable row level security;
alter table research.usaspending_physical_fm_parent_idv_targets enable row level security;
alter table scout.buyer_account_unlock_stats_v1 enable row level security;
alter table scout.farm_acute_need_stats_v1 enable row level security;
alter table scout.manual_access_displacement_stats_v1 enable row level security;
alter table scout.opportunity_property_management_rank_stats_v1 enable row level security;
alter table scout.raw_building_canonical_crosswalks enable row level security;

revoke all on table
  cleaning.citra_shield_candidate_pilot_v1,
  cleaning.field_chemistry_outcomes,
  cleaning.product_regulatory_assessments,
  cleaning.specialist_identity_resolutions,
  cleaning.surface_condition_observations,
  decisioning.building_lifecycle_observations,
  decisioning.cleaning_water_enrichment_queue,
  decisioning.cleaning_water_sources,
  intelligence.premium_exterior_building_link_candidates,
  intelligence.premium_exterior_raw_building_identity_evidence,
  procurement.federal_parent_idvs,
  procurement.federal_task_orders,
  procurement.opportunities,
  research.bridge_surface_work_evidence,
  research.federal_infrastructure_aliases,
  research.operator_field_hypotheses,
  research.painting_signal_target_readiness,
  research.usaspending_parent_vehicle_targets,
  research.usaspending_physical_fm_parent_idv_targets,
  scout.buyer_account_unlock_stats_v1,
  scout.farm_acute_need_stats_v1,
  scout.manual_access_displacement_stats_v1,
  scout.opportunity_property_management_rank_stats_v1,
  scout.raw_building_canonical_crosswalks
from anon, authenticated, public;
