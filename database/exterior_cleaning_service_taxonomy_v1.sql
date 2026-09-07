-- Scout by Cadastory
-- Exterior-cleaning service taxonomy + workflow model.
-- Consolidated source-of-truth migration for production changes deployed 2026-09-07.
-- Commercial services describe what the customer buys; workflows describe how the service is executed.
-- Pressure washing and soft washing are workflows under Building Envelope Cleaning, not separate commercial services.

-- This file intentionally consolidates the applied production migrations:
-- exterior_cleaning_service_taxonomy_v1
-- cleaning_workflow_readiness_v1
-- cleaning_taxonomy_onboarding_catalog_v1
-- cleaning_product_kind_taxonomy_v1
-- pure_water_workflow_requirement_deduplicate_v1

-- See Supabase migration history for the exact deployment sequence. The database is authoritative for live function bodies.
