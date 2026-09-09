-- Mixed crop/livestock exemplar promotion and domain-safe demo seeding.
--
-- Adds a small agriculture exemplar bench without allowing the generic demo
-- surface-work seeder to create facade/cleaning jobs for farm operations.
-- Existing livestock jobs are only reprioritized; no worker is auto-run here.

-- Guard the generic demo exemplar seeder with a positive allowlist for the
-- surface-work branch. This is intentionally a narrow patch against the current
-- deployed function so future non-surface exemplar domains do not inherit
-- exterior-cleaning search terms by default.
do $patch$
declare
  v_def text;
  v_surface_old text := $needle$
  from research.v_demo_exemplar_enrichment_queue_v1 e
  on conflict(rule_pack,subject_type,subject_id) do update set
$needle$;
  v_surface_new text := $needle$
  from research.v_demo_exemplar_enrichment_queue_v1 e
  where split_part(e.candidate_key,':',1) = any(array['exterior_cleaning','funded_pain','water_tank']::text[])
  on conflict(rule_pack,subject_type,subject_id) do update set
$needle$;
  v_link_old text := $needle$
  where e.candidate_key is not null
  on conflict(job_id,candidate_key) do update set
$needle$;
  v_link_new text := $needle$
  where e.candidate_key is not null
    and split_part(e.candidate_key,':',1) = any(array['exterior_cleaning','funded_pain','water_tank']::text[])
  on conflict(job_id,candidate_key) do update set
$needle$;
begin
  select pg_get_functiondef('public.internal_seed_exemplar_document_evidence_jobs()'::regprocedure)
    into v_def;

  if position(v_surface_old in v_def)=0 then
    raise exception 'surface exemplar seeder patch target not found; refusing unsafe migration';
  end if;
  v_def := replace(v_def,v_surface_old,v_surface_new);

  if position(v_link_old in v_def)=0 then
    raise exception 'surface exemplar candidate-link patch target not found; refusing unsafe migration';
  end if;
  v_def := replace(v_def,v_link_old,v_link_new);

  execute v_def;
end
$patch$;

insert into research.demo_exemplar_priorities_v1(
  exemplar_key,candidate_key,subject_type,subject_id,display_name,
  exemplar_class,priority,desired_evidence,worker_routes,source_roots,
  context,rationale,active,updated_at
)
values
(
  'farm:4196e3fd-0a8c-436f-a7c5-26b3bb4229c9',
  'farm:4196e3fd-0a8c-436f-a7c5-26b3bb4229c9',
  'farm_operation','4196e3fd-0a8c-436f-a7c5-26b3bb4229c9'::uuid,
  'Barbour''s Farm LLC','mixed_crop_livestock_anchor',-126750,
  array['farm_identity','current_crop_mix','current_livestock_mix','explicit_livestock_count','farm_scale','operator_contact','drone_reconnaissance_fit','source_freshness']::text[],
  array['livestock_inventory','buyer_document_evidence']::text[],
  '["https://www.kyagr.com/KDAPage.aspx?id=7504","https://www.kyagr.com/KDAPage.aspx?id=10112","http://www.barboursfarm.com"]'::jsonb,
  jsonb_build_object(
    'research_domain','agriculture',
    'state_code','KY','county_name','Hart County',
    'address_text','1084 HALLTOWN RD, CANMER, KY, 42722',
    'miles_from_louisville',69.6,
    'location_confidence',0.82,
    'normalized_crop_profiles',jsonb_build_array('Tobacco'),
    'directory_crop_mentions',jsonb_build_array('Tobacco','Corn','Alfalfa'),
    'known_livestock_enterprises',jsonb_build_array('beef','dairy','equine','swine'),
    'count_coverage','type_known_count_unknown',
    'mixed_operation',true,
    'source_media_retention','transient_only',
    'crop_signal_caution','Directory categories and descriptions are operation signals, not an exhaustive current crop inventory.',
    'location_caution','Address geocode is suitable for market-level localization, not assumed field, pasture, or launch-point geometry.',
    'identity_context_version','mixed_farm_exemplar_v1'
  ),
  'Highest-information-gain mixed farm: multiple livestock enterprises plus KDA evidence mentioning tobacco, corn, and alfalfa; livestock counts remain unresolved.',
  true,now()
),
(
  'farm:4ebb7d40-5f6e-4105-a01d-18289325a7ad',
  'farm:4ebb7d40-5f6e-4105-a01d-18289325a7ad',
  'farm_operation','4ebb7d40-5f6e-4105-a01d-18289325a7ad'::uuid,
  'Howe Valley Farms','mixed_crop_livestock_bench',-125750,
  array['farm_identity','current_crop_mix','current_livestock_mix','explicit_livestock_count','farm_scale','operator_contact','drone_reconnaissance_fit','source_freshness']::text[],
  array['livestock_inventory','buyer_document_evidence']::text[],
  '["https://www.kyagr.com/KDAPage.aspx?id=7130"]'::jsonb,
  jsonb_build_object(
    'research_domain','agriculture',
    'state_code','KY','county_name','Hardin County',
    'address_text','1939 SHIPLEY RD, CECILIA, KY, 42724',
    'miles_from_louisville',43.2,
    'location_confidence',0.82,
    'normalized_crop_profiles',jsonb_build_array('Tobacco'),
    'directory_crop_mentions',jsonb_build_array('tobacco','tobacco plants','vegetable plants'),
    'known_livestock_enterprises',jsonb_build_array('beef'),
    'count_coverage','type_known_count_unknown',
    'mixed_operation',true,
    'source_media_retention','transient_only',
    'crop_signal_caution','Directory descriptions are operation signals, not an exhaustive current crop inventory.',
    'location_caution','Address geocode is suitable for market-level localization, not assumed field, pasture, or launch-point geometry.',
    'identity_context_version','mixed_farm_exemplar_v1'
  ),
  'Strong nearby mixed-operation benchmark: beef plus tobacco and plant/vegetable production signals, with high-quality location evidence and unresolved livestock count.',
  true,now()
),
(
  'farm:fc1c3d8d-71d8-4d4f-bcc5-d59d82f0281e',
  'farm:fc1c3d8d-71d8-4d4f-bcc5-d59d82f0281e',
  'farm_operation','fc1c3d8d-71d8-4d4f-bcc5-d59d82f0281e'::uuid,
  'Tingle Farms','mixed_crop_livestock_bench',-124750,
  array['farm_identity','current_crop_mix','current_livestock_mix','explicit_livestock_count','farm_scale','operator_contact','drone_reconnaissance_fit','source_freshness']::text[],
  array['livestock_inventory','buyer_document_evidence']::text[],
  '["https://www.kyagr.com/KDAPage.aspx?id=9731","http://www.tinglefarms.com"]'::jsonb,
  jsonb_build_object(
    'research_domain','agriculture',
    'state_code','KY','county_name','Henry County',
    'address_text','722 DRENNON RD, NEW CASTLE, KY, 40050',
    'miles_from_louisville',35.2,
    'location_confidence',0.72,
    'normalized_crop_profiles',jsonb_build_array('Tobacco'),
    'known_livestock_enterprises',jsonb_build_array('beef'),
    'count_coverage','type_known_count_unknown',
    'mixed_operation',true,
    'public_website_available',true,
    'source_media_retention','transient_only',
    'crop_signal_caution','Directory categories are operation signals, not an exhaustive current crop inventory.',
    'location_caution','Address geocode is suitable for market-level localization, not assumed field, pasture, or launch-point geometry.',
    'identity_context_version','mixed_farm_exemplar_v1'
  ),
  'Close-to-Louisville mixed-operation benchmark with both KDA evidence and a public farm website, useful for testing bounded web enrichment.',
  true,now()
)
on conflict(exemplar_key) do update set
  candidate_key=excluded.candidate_key,
  subject_type=excluded.subject_type,
  subject_id=excluded.subject_id,
  display_name=excluded.display_name,
  exemplar_class=excluded.exemplar_class,
  priority=excluded.priority,
  desired_evidence=excluded.desired_evidence,
  worker_routes=excluded.worker_routes,
  source_roots=excluded.source_roots,
  context=excluded.context,
  rationale=excluded.rationale,
  active=true,
  updated_at=now();

-- Promote only the already-existing livestock evidence jobs for these exemplars.
-- This does not create a crop-specific worker or trigger execution.
update research.document_evidence_jobs j
set priority=least(j.priority,e.priority),
    context=j.context || jsonb_build_object(
      'demo_exemplar',true,
      'demo_exemplar_class',e.exemplar_class,
      'demo_exemplar_priority',e.priority,
      'mixed_crop_livestock',true,
      'desired_evidence',to_jsonb(e.desired_evidence),
      'worker_routes',to_jsonb(e.worker_routes),
      'source_media_retention','transient_only'
    ),
    updated_at=now()
from research.demo_exemplar_priorities_v1 e
where e.active=true
  and e.subject_type='farm_operation'
  and e.subject_id=j.subject_id
  and j.rule_pack='livestock_inventory_v1'
  and split_part(e.candidate_key,':',1)='farm';

comment on function public.internal_seed_exemplar_document_evidence_jobs() is
  'Seeds/boosts demo exemplar document evidence. Surface-work seeding is positively allowlisted to established surface candidate prefixes so agriculture and future non-surface exemplar domains cannot inherit facade-cleaning jobs by default.';