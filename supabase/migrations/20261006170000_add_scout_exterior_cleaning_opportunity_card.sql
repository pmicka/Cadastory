-- Candidate-driven exterior-cleaning opportunity card hydration.
--
-- This read path starts from an exact exterior_cleaning:* candidate that Scout
-- has already surfaced, and builds one bounded production card payload from
-- lightweight opportunity-spine card/map projections.

begin;

create or replace function public.scout_get_connection_exterior_cleaning_opportunity_card_v1(
  p_connection_id uuid,
  p_candidate_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_conn commerce.provider_agent_connections%rowtype;
  v_candidate_key text := nullif(btrim(coalesce(p_candidate_key,'')),'');
  v_candidate_norm text;
  v_subject_key text;
  v_known boolean := false;
  v_row record;
  v_guard jsonb;
  v_related jsonb := '[]'::jsonb;
  v_guardrails jsonb := jsonb_build_array(
    'Scout exterior-cleaning evidence supports qualification and prospecting only.',
    'This card does not prove visible staining, actual contamination, current cleaning need, customer intent, procurement, site permission, site access, or work availability.',
    'Mapped access context is planning evidence and still requires customer authorization and current field validation.'
  );
begin
  select *
  into v_conn
  from commerce.provider_agent_connections
  where id = p_connection_id
    and status = 'active'
    and revoked_at is null
    and (expires_at is null or expires_at > now());

  if not found then
    raise exception 'active Scout connection not found';
  end if;

  if v_conn.organization_id is null then
    return jsonb_build_object(
      'allowed', false,
      'card_status', 'not_found',
      'reason', 'onboarding_required',
      'onboarding', public.scout_get_connection_onboarding_status(p_connection_id)
    );
  end if;

  if v_candidate_key is null or length(v_candidate_key) > 300 then
    raise exception 'candidate_key is required and must be 300 characters or fewer';
  end if;

  if v_candidate_key !~ '^exterior_cleaning:[0-9a-fA-F-]{36}$' then
    return jsonb_build_object(
      'allowed', false,
      'card_status', 'unsupported',
      'reason', 'unsupported_candidate_family',
      'supported_candidate_family', 'exterior_cleaning:*',
      'guardrails', jsonb_build_array(
        'This production card hydrates exact exterior_cleaning:* base candidates only.',
        'Use vertical-specific Scout tools for other opportunity families.'
      )
    );
  end if;

  v_candidate_norm := lower(v_candidate_key);
  v_subject_key := case
    when v_conn.organization_id is not null then 'org:' || v_conn.organization_id::text
    else 'connection:' || v_conn.id::text
  end;

  select exists (
    select 1
    from agent_exposure.exposures e
    where e.subject_key = v_subject_key
      and e.entity_class = 'target_identity'
      and e.entity_hash = extensions.digest(
        pg_catalog.convert_to('target_identity:' || v_candidate_norm,'UTF8'),
        'sha256'
      )
  )
  into v_known;

  if not v_known then
    return jsonb_build_object(
      'allowed', false,
      'card_status', 'not_found',
      'reason', 'unknown_or_inaccessible_candidate',
      'guardrails', jsonb_build_array(
        'Scout did not hydrate this candidate because it is not a known exposed record for this connection.',
        'Resolve a site address or use a Scout discovery result first; do not probe arbitrary candidate identifiers.'
      )
    );
  end if;

  select
    s.*,
    c.swipe_key,
    c.buyer_route_summary as card_buyer_route_summary,
    c.commercial_scale_summary as card_commercial_scale_summary,
    c.recurrence_summary as card_recurrence_summary,
    c.access_summary as card_access_summary,
    c.evidence_summary as card_evidence_summary,
    m.latitude as map_latitude,
    m.longitude as map_longitude
  into v_row
  from scout.opportunity_search_spine s
  left join scout.v_opportunity_spine_cards c using (candidate_key)
  left join scout.v_opportunity_spine_map m using (candidate_key)
  where s.candidate_key = v_candidate_key
    and s.source_kind = 'exterior_cleaning'
    and (
      s.primary_service_slug = 'exterior-cleaning'
      or 'exterior-cleaning' = any(coalesce(s.service_slugs,'{}'::text[]))
    )
    and s.derived_from_candidate_key is null
    and coalesce(s.global_suppressed,false) = false
    and (s.expires_at is null or s.expires_at >= now());

  if not found then
    return jsonb_build_object(
      'allowed', false,
      'card_status', 'not_found',
      'reason', 'unsupported_or_inaccessible_candidate',
      'guardrails', jsonb_build_array(
        'No active, unsuppressed, base exterior-cleaning opportunity was available for this known candidate.',
        'Scout did not fall back to derived timing records or unrelated nearby opportunities.'
      )
    );
  end if;

  v_guard := public.scout_guard_opportunity_request(
    p_connection_id,
    array['exterior-cleaning']::text[],
    jsonb_build_object('state_code', v_row.state_code)
  );

  if not coalesce((v_guard->>'allowed')::boolean, false) then
    return v_guard || jsonb_build_object(
      'card_status', 'not_found',
      'reason', 'opportunity_access_not_allowed',
      'guardrails', jsonb_build_array(
        'Opportunity access did not allow this exterior-cleaning card result.',
        'Scout did not reconstruct blocked opportunity details.'
      )
    );
  end if;

  with related as (
    select
      r.candidate_key,
      r.source_kind,
      r.signal_kind,
      r.event_start,
      r.event_tier,
      r.confidence,
      r.derived_from_candidate_key,
      r.derivation_kind,
      case
        when length(coalesce(btrim(r.event_title),'')) between 1 and 180
          then btrim(r.event_title)
        else null
      end as event_title,
      case
        when length(coalesce(btrim(r.event_title),'')) between 1 and 180
          then left(nullif(btrim(r.why_now),''), 700)
        else 'Related event/timing context exists for this site, but the source event title was omitted because it is not presentation-ready.'
      end as summary
    from scout.opportunity_search_spine r
    where coalesce(r.global_suppressed,false) = false
      and (r.expires_at is null or r.expires_at >= now())
      and r.source_kind = 'event_detailing'
      and r.derived_from_candidate_key = v_candidate_key
      and r.candidate_key <> v_candidate_key
    order by r.event_start nulls last, r.confidence desc nulls last, r.candidate_key
    limit 5
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'candidate_key', candidate_key,
    'candidate_role', 'related_timing_context',
    'is_derived', true,
    'source_kind', source_kind,
    'signal_kind', signal_kind,
    'event_title', event_title,
    'event_start', event_start,
    'event_tier', event_tier,
    'confidence', confidence,
    'derived_from_candidate_key', derived_from_candidate_key,
    'derivation_kind', derivation_kind,
    'summary', summary,
    'guardrail', 'Timing context is subordinate to the exterior-cleaning base opportunity and does not prove cleaning demand.'
  ) order by event_start nulls last, confidence desc nulls last, candidate_key), '[]'::jsonb)
  into v_related
  from related;

  return jsonb_build_object(
    'allowed', true,
    'card_status', 'resolved',
    'contract_version', 'exterior_cleaning_opportunity_card_v1',
    'opportunity_type', 'exterior_cleaning',
    'candidate_key', v_row.candidate_key,
    'candidate_role', 'primary_base',
    'is_derived', false,
    'service_slug', 'exterior-cleaning',
    'opportunity', jsonb_build_object(
      'candidate_key', v_row.candidate_key,
      'source_kind', v_row.source_kind,
      'signal_kind', v_row.signal_kind,
      'signal_strength', v_row.signal_strength,
      'confidence', v_row.confidence,
      'observed_at', v_row.observed_at,
      'refreshed_at', v_row.refreshed_at,
      'time_sensitive', v_row.time_sensitive,
      'window_status', v_row.window_status,
      'base_pursuit_state', v_row.base_pursuit_state,
      'freshness_status', v_row.freshness_status,
      'why_now', v_row.why_now
    ),
    'site', jsonb_build_object(
      'display_name', v_row.display_name,
      'target_name', v_row.target_name,
      'target_class', v_row.target_class,
      'target_resolution_status', v_row.target_resolution_status,
      'canonical_namespace', v_row.canonical_namespace,
      'canonical_asset_id', v_row.canonical_asset_id,
      'operational_target_type', v_row.operational_target_type,
      'operational_target_key', v_row.operational_target_key,
      'address', nullif(v_row.details->>'address',''),
      'city', nullif(v_row.details->>'city',''),
      'state_code', v_row.state_code,
      'county_name', v_row.county_name,
      'location_label', pg_catalog.concat_ws(', ', nullif(v_row.details->>'address',''), nullif(v_row.details->>'city',''), v_row.state_code),
      'occupancy', jsonb_strip_nulls(jsonb_build_object(
        'primary_occupancy', nullif(v_row.details->>'primary_occupancy',''),
        'occupancy_class', nullif(v_row.details->>'occupancy_class',''),
        'facility_classification_source', 'Scout normalized exterior-cleaning target evidence'
      ))
    ),
    'commercial_scale', jsonb_build_object(
      'status', v_row.commercial_scale_status,
      'summary', coalesce(v_row.card_commercial_scale_summary, v_row.commercial_scale_summary, '{}'::jsonb)
    ),
    'responsible_party', jsonb_build_object(
      'resolution_status', coalesce(v_row.buyer_resolution_status,'unresolved'),
      'name', v_row.buyer_name,
      'role_code', v_row.buyer_role_code,
      'confidence', v_row.buyer_confidence,
      'contact_status', coalesce(v_row.buyer_contact_status,'unresolved'),
      'procurement_status', coalesce(v_row.procurement_status,'unresolved'),
      'route_summary', coalesce(v_row.card_buyer_route_summary, v_row.buyer_route_summary, '{}'::jsonb),
      'guardrail', 'Responsible-party evidence preserves role semantics; owner, manager, operator, tenant, contact, and procurement authority are not silently equated.'
    ),
    'access_context', jsonb_build_object(
      'status', coalesce(v_row.site_access_status,'unresolved'),
      'summary', coalesce(v_row.card_access_summary, v_row.access_summary, '{}'::jsonb)
    ),
    'evidence', jsonb_strip_nulls(jsonb_build_object(
      'summary', coalesce(v_row.card_evidence_summary, v_row.evidence_summary, '{}'::jsonb),
      'positive_signal', coalesce(v_row.card_evidence_summary, v_row.evidence_summary, '{}'::jsonb)->'positive_signal',
      'counter_evidence', coalesce(v_row.card_evidence_summary, v_row.evidence_summary, '{}'::jsonb)->'counter_evidence',
      'environmental_pressure', jsonb_strip_nulls(jsonb_build_object(
        'exposure_kind', nullif(v_row.details->>'exposure_kind',''),
        'nearest_exposure_name', nullif(v_row.details->>'nearest_exposure_name',''),
        'exposure_distance_m', nullif(v_row.details->>'exposure_distance_m',''),
        'contamination_pressure', case
          when v_row.why_now ilike '%moderate%' then 'medium'
          when v_row.why_now ilike '%high%' then 'high'
          when v_row.why_now ilike '%low%' then 'low'
          else null
        end
      )),
      'appearance_context', jsonb_strip_nulls(jsonb_build_object(
        'appearance_sensitivity', nullif(v_row.details->>'appearance_sensitivity',''),
        'recent_new_construction', v_row.details->'recent_new_construction'
      ))
    )),
    'recurrence_context', jsonb_build_object(
      'status', v_row.recurrence_status,
      'next_due_at', v_row.next_due_at,
      'summary', coalesce(v_row.card_recurrence_summary, v_row.recurrence_summary, '{}'::jsonb)
    ),
    'related_timing_context', v_related,
    'map', jsonb_build_object(
      'contract_version', 'exterior_cleaning_site_map_v1',
      'map_kind', 'single_site_point',
      'candidate_key', v_row.candidate_key,
      'display_name', v_row.display_name,
      'site_point', jsonb_build_object(
        'lon', v_row.map_longitude,
        'lat', v_row.map_latitude,
        'geometry_type', 'Point',
        'semantics', 'canonical_exterior_cleaning_site_point'
      ),
      'marker_semantics', 'Exact Scout opportunity point for the canonical exterior-cleaning site; no parcel boundary, access envelope, service radius, or work authorization is implied.',
      'attribution', 'Map display should preserve the current Scout raster-map attribution semantics.'
    ),
    'unknowns', jsonb_build_array(
      'Visible staining or contamination has not been proven by this card.',
      'Customer intent, procurement route, contact route, access permission, and work availability remain separate validation steps unless explicitly resolved above.',
      'Field conditions and authorization must be checked before any job planning or dispatch.'
    ),
    'base_vs_derived_policy', jsonb_build_object(
      'primary_candidate', 'The exterior_cleaning:* base candidate is the card subject.',
      'related_timing_context', 'Derived event_detailing:* records may appear only as subordinate timing/context signals.',
      'confidence_policy', 'Derived-event confidence never replaces the base exterior-cleaning confidence.'
    ),
    'guardrails', v_guardrails
  );
end
$function$;

comment on function public.scout_get_connection_exterior_cleaning_opportunity_card_v1(uuid,text) is
  'Read-only normal Scout MCP card hydrator for one already-known exterior_cleaning:* base candidate. Uses lightweight spine card/map projections and preserves derived timing context as subordinate.';

revoke all on function public.scout_get_connection_exterior_cleaning_opportunity_card_v1(uuid,text)
  from public, anon, authenticated;
grant execute on function public.scout_get_connection_exterior_cleaning_opportunity_card_v1(uuid,text)
  to service_role;

insert into agent_contract.output_schema_families (
  slug,version,description,json_schema,updated_at
)
values (
  'exterior_cleaning_opportunity_card_v1',
  1,
  'Bounded production card payload for one known exterior_cleaning:* base opportunity candidate.',
  '{
    "type":"object",
    "properties":{
      "allowed":{"type":"boolean"},
      "card_status":{"type":"string","enum":["resolved","not_found","unsupported"]},
      "contract_version":{"type":"string","const":"exterior_cleaning_opportunity_card_v1"},
      "opportunity_type":{"type":"string","const":"exterior_cleaning"},
      "candidate_key":{"type":"string"},
      "candidate_role":{"type":"string","const":"primary_base"},
      "is_derived":{"type":"boolean","const":false},
      "service_slug":{"type":"string","const":"exterior-cleaning"},
      "opportunity":{"type":"object"},
      "site":{"type":"object"},
      "commercial_scale":{"type":"object"},
      "responsible_party":{"type":"object"},
      "access_context":{"type":"object"},
      "evidence":{"type":"object"},
      "related_timing_context":{"type":"array"},
      "map":{"type":"object"},
      "unknowns":{"type":"array"},
      "guardrails":{"type":"array"}
    },
    "additionalProperties":true
  }'::jsonb,
  now()
)
on conflict (slug) do update set
  version=excluded.version,
  description=excluded.description,
  json_schema=excluded.json_schema,
  updated_at=now();

insert into agent_contract.tool_contracts (
  tool_name,response_type_slug,output_schema_slug,read_only,destructive,idempotent,open_world,
  model_visible,app_visible,contract_version,active,notes,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card','opportunity_detail','exterior_cleaning_opportunity_card_v1',
  true,false,true,false,true,true,1,true,
  'Hydrates one already-known exact exterior_cleaning:* base candidate into a bounded customer-facing opportunity card. It is not discovery, not address resolution, and not a lead work package.',
  now()
)
on conflict (tool_name) do update set
  response_type_slug=excluded.response_type_slug,
  output_schema_slug=excluded.output_schema_slug,
  read_only=excluded.read_only,
  destructive=excluded.destructive,
  idempotent=excluded.idempotent,
  open_world=excluded.open_world,
  model_visible=excluded.model_visible,
  app_visible=excluded.app_visible,
  contract_version=excluded.contract_version,
  active=excluded.active,
  notes=excluded.notes,
  updated_at=now();

insert into agent_privacy.tool_policies (
  tool_name,required_scope,purpose,allowed_root_keys,raw_payload_persisted,persistence_class,
  sensitive_exception_keys,max_argument_bytes,enabled,privacy_notes,contract_version,
  agent_free_text_allowed,nested_contract,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card','opportunities:read',
  'Hydrate one known exact exterior-cleaning candidate into a bounded Scout opportunity card',
  array['candidate_key']::text[],
  false,'never',array[]::text[],2048,true,
  'Accepts only one exact candidate_key. No addresses, notes, chat history, arbitrary filters, or bulk candidate arrays are accepted.',
  'privacy-contract-v2',false,
  '{"candidate_key":"single exact exterior_cleaning:* candidate key, max 300 characters","bulk_lists":"not accepted","free_text":"not accepted"}'::jsonb,
  now()
)
on conflict (tool_name) do update set
  required_scope=excluded.required_scope,
  purpose=excluded.purpose,
  allowed_root_keys=excluded.allowed_root_keys,
  raw_payload_persisted=excluded.raw_payload_persisted,
  persistence_class=excluded.persistence_class,
  sensitive_exception_keys=excluded.sensitive_exception_keys,
  max_argument_bytes=excluded.max_argument_bytes,
  enabled=excluded.enabled,
  privacy_notes=excluded.privacy_notes,
  contract_version=excluded.contract_version,
  agent_free_text_allowed=excluded.agent_free_text_allowed,
  nested_contract=excluded.nested_contract,
  updated_at=now();

insert into agent_presentation.tool_contracts (
  tool_name,response_type_slug,max_initial_items,section_order,evidence_visibility,
  primary_action_policy,map_priority,status_hint,agent_instruction,active,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card','opportunity_detail',1,
  array['site','opportunity','commercial_scale','responsible_party','access_context','evidence','related_timing_context','unknowns','guardrails']::text[],
  'inline_when_material','one','high',null,
  'Present the site identity and exterior-cleaning base candidate first. Keep buyer/responsibility, scale, access, evidence, unknowns, and guardrails visible. Related event/timing signals are subordinate context and must not replace the base opportunity.',
  true,now()
)
on conflict (tool_name) do update set
  response_type_slug=excluded.response_type_slug,
  max_initial_items=excluded.max_initial_items,
  section_order=excluded.section_order,
  evidence_visibility=excluded.evidence_visibility,
  primary_action_policy=excluded.primary_action_policy,
  map_priority=excluded.map_priority,
  status_hint=excluded.status_hint,
  agent_instruction=excluded.agent_instruction,
  active=excluded.active,
  updated_at=now();

insert into agent_ip.tool_exposure_policies (
  tool_name,permitted_output_classes,explanation_mode,bulk_method_export_allowed,
  internal_diagnostics_allowed,active,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card',
  array['public_fact','customer_business_record','explainable_derivation']::text[],
  'evidence_explanation_only',
  false,false,true,now()
)
on conflict (tool_name) do update set
  permitted_output_classes=excluded.permitted_output_classes,
  explanation_mode=excluded.explanation_mode,
  bulk_method_export_allowed=excluded.bulk_method_export_allowed,
  internal_diagnostics_allowed=excluded.internal_diagnostics_allowed,
  active=excluded.active,
  updated_at=now();

insert into agent_exposure.tool_rules (
  tool_name,track_entities,deep_sensitive,discovery_batch,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card',
  true,true,false,now()
)
on conflict (tool_name) do update set
  track_entities=excluded.track_entities,
  deep_sensitive=excluded.deep_sensitive,
  discovery_batch=excluded.discovery_batch,
  updated_at=now();

insert into agent_contract.tool_evolution (
  tool_name,lifecycle_state,compatibility_policy,side_effect_scope,reversibility,
  compensation_tool,result_envelope_version,provenance_policy,notes,legacy_doctrine_v1_debt,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card','stable','additive_only','none','not_applicable',
  null,1,'preserve_if_present',
  'New read-only production exterior-cleaning card hydrator. Candidate-driven only; no discovery, media matching, full projection, lead package, or mutation.',
  false,now()
)
on conflict (tool_name) do update set
  lifecycle_state=excluded.lifecycle_state,
  compatibility_policy=excluded.compatibility_policy,
  side_effect_scope=excluded.side_effect_scope,
  reversibility=excluded.reversibility,
  compensation_tool=excluded.compensation_tool,
  result_envelope_version=excluded.result_envelope_version,
  provenance_policy=excluded.provenance_policy,
  notes=excluded.notes,
  legacy_doctrine_v1_debt=excluded.legacy_doctrine_v1_debt,
  updated_at=now();

insert into agent_contract.tool_capability_links(tool_name,capability_slug)
values ('scout_get_exterior_cleaning_opportunity_card','opportunities.discovery')
on conflict do nothing;

insert into agent_contract.tool_routing (
  tool_name,summary,when_cues,not_when_cues,prefer_over,prerequisites,
  usually_preceded_by,usually_followed_by,confirmation,failure_policy,result_rules,
  instruction_group,instruction_priority,active,routing_version,updated_at
)
values (
  'scout_get_exterior_cleaning_opportunity_card',
  'Hydrate one already-known exterior_cleaning:* base candidate into a bounded production opportunity card.',
  array[
    'the previous Scout step returned an exterior_cleaning:* candidate_key for a known site',
    'the operator asks what Scout knows about an exterior-cleaning candidate',
    'an address-resolution result needs to become an exterior-cleaning opportunity card'
  ]::text[],
  array[
    'the operator supplied an address rather than a candidate_key',
    'the candidate is not exterior_cleaning:*',
    'the candidate is a derived event_detailing:* timing record',
    'the request asks for a lead work package, proposal, document bundle, outreach, or operator-fit analysis',
    'the request contains multiple candidate keys or broad filters'
  ]::text[],
  array[
    'scout_get_lead_work_package is deeper pursuit/work preparation, not lightweight property intelligence',
    'scout_match_media_asset is for photo/GPS/signage identification, not known address-to-card routing',
    'scout_find_opportunities is discovery, not exact known-candidate hydration'
  ]::text[],
  '["one exact exterior_cleaning:* candidate_key already returned by Scout"]'::jsonb,
  array['scout_resolve_site_opportunities','scout_find_opportunities']::text[],
  array['scout_prepare_outreach','scout_get_lead_work_package','scout_plan_job']::text[],
  'none',
  '{"retry":"Safe read: retry once only for a genuinely transient retryable error.","on_unknown":"Do not probe nearby candidate identifiers or switch to broad discovery unless the operator explicitly asks for discovery."}'::jsonb,
  '{"boundary":"Single known exterior-cleaning candidate only. Base opportunity remains primary; related event/timing candidates are subordinate. Uses lightweight spine card/map data; no full projection or lead work package."}'::jsonb,
  'opportunities',10,true,1,now()
)
on conflict (tool_name) do update set
  summary=excluded.summary,
  when_cues=excluded.when_cues,
  not_when_cues=excluded.not_when_cues,
  prefer_over=excluded.prefer_over,
  prerequisites=excluded.prerequisites,
  usually_preceded_by=excluded.usually_preceded_by,
  usually_followed_by=excluded.usually_followed_by,
  confirmation=excluded.confirmation,
  failure_policy=excluded.failure_policy,
  result_rules=excluded.result_rules,
  instruction_group=excluded.instruction_group,
  instruction_priority=excluded.instruction_priority,
  active=excluded.active,
  routing_version=excluded.routing_version,
  updated_at=now();

insert into agent_contract.routing_eval_fixtures (
  fixture_key,fixture_source,prompt,expected_first_tool,forbidden_first_tools,
  expected_sequence,assertions,active,updated_at
)
values
  (
    'exterior_cleaning_card.witherspoon_address_flow',
    'catalog_task_cue',
    'What can Scout tell me about 100 Witherspoon St, Louisville, KY?',
    'scout_resolve_site_opportunities',
    array['scout_match_media_asset','scout_find_opportunities','scout_get_lead_work_package']::text[],
    array['scout_resolve_site_opportunities','scout_get_exterior_cleaning_opportunity_card']::text[],
    '{"address_first":true,"base_exterior_cleaning_candidate_handoff":true,"media_matcher_forbidden":true,"lead_work_package_forbidden":true}'::jsonb,
    true,now()
  ),
  (
    'exterior_cleaning_card.exact_candidate',
    'catalog_task_cue',
    'Show the Scout exterior-cleaning card for exterior_cleaning:b6c401a0-97da-4a9d-bbf6-b06d7b745e3b',
    'scout_get_exterior_cleaning_opportunity_card',
    array['scout_match_media_asset','scout_find_opportunities','scout_get_lead_work_package']::text[],
    array['scout_get_exterior_cleaning_opportunity_card']::text[],
    '{"exact_candidate_key":true,"candidate_family_required":"exterior_cleaning"}'::jsonb,
    true,now()
  )
on conflict (fixture_key) do update set
  fixture_source=excluded.fixture_source,
  prompt=excluded.prompt,
  expected_first_tool=excluded.expected_first_tool,
  forbidden_first_tools=excluded.forbidden_first_tools,
  expected_sequence=excluded.expected_sequence,
  assertions=excluded.assertions,
  active=excluded.active,
  updated_at=now();

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
select agent_contract.assert_tool_routing_integrity();
select agent_contract.assert_routing_eval_fixtures();

commit;
