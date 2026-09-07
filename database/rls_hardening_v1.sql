-- Scout RLS hardening v1
--
-- Brings all current Scout application tables under RLS without introducing
-- permissive anon/authenticated policies. This matches the existing server-side
-- catalog pattern: trusted postgres/service-role execution paths bypass RLS,
-- while raw client access remains closed unless explicitly granted later.

alter table core.regions enable row level security;
alter table ingest.sources enable row level security;
alter table ingest.raw_records enable row level security;
alter table core.organizations enable row level security;
alter table core.organization_aliases enable row level security;
alter table core.people enable row level security;
alter table core.organization_people enable row level security;
alter table commerce.service_types enable row level security;
alter table commerce.delivery_methods enable row level security;
alter table commerce.provider_profiles enable row level security;
alter table commerce.provider_services enable row level security;
alter table commerce.candidate_services enable row level security;
alter table commerce.market_observations enable row level security;
alter table commerce.observed_services enable row level security;
alter table ingest.record_links enable row level security;
alter table ingest.building_import_tiles enable row level security;
alter table commerce.provider_users enable row level security;
alter table commerce.provider_service_preferences enable row level security;
alter table equipment.manufacturers enable row level security;
alter table equipment.models enable row level security;
alter table equipment.capability_types enable row level security;
alter table equipment.model_capabilities enable row level security;
alter table equipment.provider_equipment enable row level security;
alter table equipment.provider_capabilities enable row level security;
alter table commerce.service_capability_requirements enable row level security;
alter table knowledge.documents enable row level security;
alter table knowledge.claims enable row level security;
alter table knowledge.entity_links enable row level security;
alter table knowledge.claim_relations enable row level security;
alter table compliance.credential_types enable row level security;
alter table compliance.provider_credentials enable row level security;
alter table commerce.service_credential_requirements enable row level security;
alter table operability.hunting_areas enable row level security;
alter table operability.hunting_seasons enable row level security;
alter table operability.hunting_rules enable row level security;
alter table intelligence.funded_pain_signals enable row level security;
alter table intelligence.funded_pain_evidence enable row level security;
alter table intelligence.construction_projects enable row level security;
alter table intelligence.construction_events enable row level security;
alter table intelligence.construction_stage_service_rules enable row level security;
alter table intelligence.construction_service_windows enable row level security;
alter table equipment.model_relations enable row level security;
alter table intelligence.funded_pain_maturity_types enable row level security;
alter table commerce.provider_locations enable row level security;
alter table intelligence.indicator_definitions enable row level security;
alter table intelligence.service_indicator_profiles enable row level security;
alter table intelligence.service_indicator_rules enable row level security;
alter table equipment.future_gear_watch enable row level security;
alter table equipment.future_gear_evidence enable row level security;
alter table equipment.future_gear_model_links enable row level security;
alter table intelligence.weather_events enable row level security;
alter table intelligence.weather_hazard_service_rules enable row level security;
alter table intelligence.weather_asset_source_rules enable row level security;
alter table intelligence.weather_service_windows enable row level security;
alter table intelligence.weather_asset_exposures enable row level security;
alter table intelligence.weather_zones enable row level security;
alter table economics.operating_inputs enable row level security;
alter table economics.price_observations enable row level security;
alter table economics.repair_actions enable row level security;
alter table economics.repair_action_items enable row level security;
alter table economics.pricing_coverage enable row level security;
alter table ingest.collector_auth enable row level security;
alter table intelligence.operator_supply_snapshots enable row level security;
alter table scout.opportunity_lens_dimensions enable row level security;
alter table scout.opportunity_evidence_events enable row level security;
alter table scout.opportunity_facets enable row level security;
alter table scout.opportunity_relationships enable row level security;
alter table scout.property_building_links enable row level security;
alter table scout.property_management_account_evidence enable row level security;
alter table core.organization_service_areas enable row level security;
alter table agent_contract.architecture_doctrine_versions enable row level security;
alter table agent_contract.tool_evolution enable row level security;
alter table agriculture.cdl_classes enable row level security;

create or replace view agent_privacy.v_rls_posture_v1 as
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  has_table_privilege('anon', format('%I.%I', n.nspname, c.relname), 'SELECT,INSERT,UPDATE,DELETE') as anon_has_dml,
  has_table_privilege('authenticated', format('%I.%I', n.nspname, c.relname), 'SELECT,INSERT,UPDATE,DELETE') as authenticated_has_dml,
  has_table_privilege('service_role', format('%I.%I', n.nspname, c.relname), 'SELECT,INSERT,UPDATE,DELETE') as service_role_has_dml,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where c.relkind in ('r','p')
  and n.nspname not in (
    'pg_catalog','information_schema','pg_toast','auth','storage','realtime',
    'extensions','graphql','graphql_public','vault','cron','supabase_migrations','pgbouncer'
  )
  and n.nspname not like 'pg_temp_%'
  and n.nspname not like 'pg_toast_temp_%';

create or replace function agent_privacy.assert_rls_posture_v1()
returns void
language plpgsql
security definer
set search_path = pg_catalog, agent_privacy
as $$
declare
  missing text;
begin
  select string_agg(format('%I.%I',schema_name,table_name), ', ' order by schema_name,table_name)
  into missing
  from agent_privacy.v_rls_posture_v1
  where not rls_enabled;

  if missing is not null then
    raise exception using
      errcode = 'P0001',
      message = 'Scout application tables without RLS: ' || missing;
  end if;
end;
$$;

revoke all on function agent_privacy.assert_rls_posture_v1() from public;
grant execute on function agent_privacy.assert_rls_posture_v1() to service_role;

comment on view agent_privacy.v_rls_posture_v1 is
  'Machine-readable RLS posture for Scout application tables; system-managed schemas are excluded.';
comment on function agent_privacy.assert_rls_posture_v1() is
  'Fails when any Scout application table is created or left with RLS disabled.';
