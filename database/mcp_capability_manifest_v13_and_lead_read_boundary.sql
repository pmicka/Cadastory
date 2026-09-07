-- Scout MCP capability-discovery and lead-work-package read-boundary repair.
-- Production state applied 2026-09-07.
--
-- 1) Keep the lead work-package business RPC genuinely read-only. The MCP
--    presentation boundary decorates the returned payload exactly once.
-- 2) Make scout_get_capability_manifest understand named multi-capability
--    requests without spraying adjacent capabilities based on generic summary words.

create or replace function public.scout_get_connection_lead_work_package_v2(
  p_connection_id uuid,
  p_candidate_key text,
  p_jurisdiction_code text default null::text,
  p_channel text default 'email'::text
)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select public.scout_get_connection_lead_work_package_v2_core_v1(
    p_connection_id,p_candidate_key,p_jurisdiction_code,p_channel
  )
$function$;

create or replace function public.scout_capability_query_matches_v1(
  p_query text,
  p_title text,
  p_summary text,
  p_task_cues text[],
  p_example_requests text[],
  p_primary_tools text[]
)
returns boolean
language plpgsql
immutable
set search_path to ''
as $function$
declare
  q text := nullif(btrim(regexp_replace(lower(coalesce(p_query,'')),'[^a-z0-9]+',' ','g')),'');
  t text := nullif(btrim(regexp_replace(lower(coalesce(p_title,'')),'[^a-z0-9]+',' ','g')),'');
  hay text;
  cue_hay text;
  tok text;
  significant_count int := 0;
  overlap_count int := 0;
  title_overlap_count int := 0;
  cue_overlap_count int := 0;
  pat text;
begin
  if q is null then return true; end if;

  hay := btrim(regexp_replace(lower(concat_ws(' ',
    coalesce(p_title,''), coalesce(p_summary,''),
    array_to_string(coalesce(p_task_cues,'{}'::text[]),' '),
    array_to_string(coalesce(p_example_requests,'{}'::text[]),' '),
    array_to_string(coalesce(p_primary_tools,'{}'::text[]),' ')
  )),'[^a-z0-9]+',' ','g'));
  cue_hay := btrim(regexp_replace(lower(concat_ws(' ',
    array_to_string(coalesce(p_task_cues,'{}'::text[]),' '),
    array_to_string(coalesce(p_example_requests,'{}'::text[]),' ')
  )),'[^a-z0-9]+',' ','g'));

  if t is not null and (
       position(t in q) > 0
       or (right(t,1)='s' and position(left(t,length(t)-1) in q) > 0)
       or position(q in t) > 0
     ) then return true; end if;

  if position(q in hay) > 0 then return true; end if;

  for tok in
    select distinct x
    from regexp_split_to_table(q,'\s+') x
    where length(x) >= 3
      and x not in (
        'scout','opportunity','opportunities','capability','capabilities','feature','features',
        'tool','tools','show','tell','give','what','does','can','the','and','for','with','from','this','that','about'
      )
  loop
    significant_count := significant_count + 1;
    pat := '(^| )' || regexp_replace(tok,'([\[\]().*+?^$|{}\\-])','\\\1','g') || '( |$)';
    if hay ~ pat then overlap_count := overlap_count + 1; end if;
    if cue_hay ~ pat then cue_overlap_count := cue_overlap_count + 1; end if;
    if t is not null and t ~ ('(^| )' || regexp_replace(tok,'([\[\]().*+?^$|{}\\-])','\\\1','g') || 's?( |$)') then
      title_overlap_count := title_overlap_count + 1;
    end if;
  end loop;

  if significant_count = 0 and (
    q ~ '(^| )(what can scout do|what does scout do)( |$)'
    or q ~ '(^| )(capability|capabilities|feature|features)( |$)'
  ) then return true; end if;

  if significant_count = 1 then return title_overlap_count = 1 or cue_overlap_count = 1; end if;

  return title_overlap_count >= 2 or cue_overlap_count >= 2;
end
$function$;

create or replace function public.scout_get_capability_manifest(
  p_connection_id uuid,
  p_query text default null::text,
  p_category text default null::text,
  p_include_services boolean default false,
  p_include_external boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_conn commerce.provider_agent_connections%rowtype;
  v_status jsonb;
  v_onboarding_required boolean := false;
  v_caps jsonb;
  v_services jsonb := null;
  v_matched_services jsonb := '[]'::jsonb;
  v_external jsonb := null;
  v_query text := nullif(btrim(coalesce(p_query,'')),'');
  v_query_norm text;
  v_category text := nullif(lower(btrim(coalesce(p_category,''))),'');
  v_service_match boolean := false;
  v_setup_intent boolean := false;
  v_service_count integer;
  v_wired integer;
  v_partial integer;
  v_parent integer;
  v_gap integer;
  v_standard_count integer;
  v_external_vocab_count integer;
  v_known_integration_count integer;
begin
  select * into v_conn
  from commerce.provider_agent_connections
  where id=p_connection_id and status='active' and (expires_at is null or expires_at>now());
  if not found then raise exception 'active Scout connection not found'; end if;
  if v_query is not null and length(v_query)>200 then raise exception 'capability query exceeds 200 characters'; end if;
  if v_category is not null and v_category !~ '^[a-z][a-z0-9_.-]{1,79}$' then raise exception 'invalid capability category'; end if;

  v_query_norm := nullif(btrim(regexp_replace(lower(coalesce(v_query,'')),'[^a-z0-9]+',' ','g')),'');
  v_setup_intent := coalesce(v_query_norm ~ '(^| )(set up|setup|configure|add|offer|offering|now offer|update|change|profile|service area|credential|operating state)( |$)',false);

  if v_query_norm is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'service_slug',s.service_slug,
      'service_name',s.service_name,
      'indicator_coverage',s.indicator_coverage,
      'push_strategy',s.push_strategy,
      'target_mode',s.target_mode
    ) order by
      case when regexp_replace(lower(s.service_name),'[^a-z0-9]+',' ','g')=v_query_norm then 0
           when regexp_replace(lower(s.service_slug),'[^a-z0-9]+',' ','g')=v_query_norm then 0 else 1 end,
      s.service_name),'[]'::jsonb)
    into v_matched_services
    from scout.v_opportunity_service_coverage s
    where regexp_replace(lower(s.service_name),'[^a-z0-9]+',' ','g')=v_query_norm
       or regexp_replace(lower(s.service_slug),'[^a-z0-9]+',' ','g')=v_query_norm
       or regexp_replace(lower(s.service_name),'[^a-z0-9]+',' ','g') like '%'||v_query_norm||'%'
       or regexp_replace(lower(s.service_slug),'[^a-z0-9]+',' ','g') like '%'||v_query_norm||'%'
       or v_query_norm like '%'||regexp_replace(lower(s.service_name),'[^a-z0-9]+',' ','g')||'%'
       or v_query_norm like '%'||regexp_replace(lower(s.service_slug),'[^a-z0-9]+',' ','g')||'%';
    v_service_match := jsonb_array_length(v_matched_services)>0;
  end if;

  v_status := public.scout_get_connection_onboarding_status(p_connection_id);
  v_onboarding_required := coalesce((v_status->>'onboarding_required')::boolean,false);

  select coalesce(jsonb_agg(jsonb_build_object(
    'slug',c.slug,
    'title',c.title,
    'category',c.category,
    'kind',c.capability_kind,
    'summary',c.summary,
    'status',c.status,
    'entitlement',jsonb_build_object('key',c.entitlement_key,'status',c.entitlement_status,'currently_included',c.entitlement_status='included','future_tierable',c.future_tierable),
    'connection_state',case
      when c.status<>'available' then c.status
      when not (c.required_scopes <@ coalesce(v_conn.scopes,'{}'::text[])) then 'connection_scope_missing'
      when c.requires_critical_setup and v_onboarding_required then 'setup_required'
      when c.requires_external_capability and not exists(
        select 1 from commerce.agent_connection_capabilities ac
        where ac.connection_id=p_connection_id and ac.availability='available' and ac.valid_until>now() and ac.confidence in ('declared','mapped','inferred')
      ) then 'available_when_connected'
      else 'available'
    end,
    'requires_critical_setup',c.requires_critical_setup,
    'requires_external_capability',c.requires_external_capability,
    'first_use_opt_in',c.first_use_opt_in,
    'task_cues',to_jsonb(c.task_cues),
    'example_requests',to_jsonb(c.example_requests),
    'primary_tools',to_jsonb(c.primary_tools),
    'suggestion_policy',c.suggestion_policy,
    'surface_during_onboarding',c.surface_during_onboarding,
    'privacy_note',c.privacy_note
  ) order by
    case
      when v_service_match and v_setup_intent and c.slug='profile.business_setup' then 0
      when v_service_match and c.slug='opportunities.discovery' then 1
      when v_service_match and c.slug='opportunities.readiness_check' then 2
      when v_service_match and c.slug='jobs.plan_preflight' then 3
      when v_service_match and c.slug='documents.service_suite' then 4
      else 10
    end,
    c.sort_order,c.slug),'[]'::jsonb)
  into v_caps
  from commerce.scout_capability_catalog c
  where c.active
    and (v_category is null or c.category=v_category)
    and (
      v_query is null
      or (
        public.scout_capability_query_matches_v1(v_query,c.title,c.summary,c.task_cues,c.example_requests,c.primary_tools)
        and not (v_service_match and c.slug='profile.business_setup' and not v_setup_intent)
      )
      or (v_service_match and v_setup_intent and c.slug='profile.business_setup')
      or (
        v_service_match and c.slug in (
          'opportunities.discovery',
          'opportunities.readiness_check',
          'jobs.plan_preflight',
          'documents.service_suite'
        )
      )
    );

  select count(*),
         count(*) filter(where indicator_coverage='wired'),
         count(*) filter(where indicator_coverage='partial'),
         count(*) filter(where indicator_coverage='parent_only'),
         count(*) filter(where indicator_coverage='gap')
  into v_service_count,v_wired,v_partial,v_parent,v_gap
  from scout.v_opportunity_service_coverage;

  select count(*) into v_standard_count from knowledge.document_standards where status='active';
  select count(*) into v_external_vocab_count from commerce.agent_capability_catalog where active;
  select count(*) into v_known_integration_count from commerce.agent_integration_registry where active;

  if p_include_services then
    select coalesce(jsonb_agg(jsonb_build_object(
      'service_slug',s.service_slug,
      'service_name',s.service_name,
      'push_strategy',s.push_strategy,
      'target_mode',s.target_mode,
      'indicator_coverage',s.indicator_coverage,
      'notes',s.notes
    ) order by s.service_name),'[]'::jsonb)
    into v_services
    from scout.v_opportunity_service_coverage s;
  end if;

  if p_include_external then
    v_external := public.scout_get_connection_external_capabilities(p_connection_id,false);
  end if;

  return jsonb_build_object(
    'manifest_version','1.3',
    'catalog_policy',jsonb_build_object(
      'all_current_capabilities_included',true,
      'future_tiering_supported',true,
      'signup_feature_dump',false,
      'onboarding_feature_dump',false,
      'full_catalog_on_explicit_request',true,
      'host_may_suggest_when_task_relevant',true,
      'suggestions_block_workflow',false,
      'external_first_use_opt_in',true,
      'service_aware_routing',true,
      'service_change_intent_routing',true,
      'multi_capability_query_matching',true,
      'guidance','Use the full manifest when the operator explicitly asks what Scout can do. Otherwise route against task cues, explicit service-change intent, recognized service coverage, and meaningful capability-name/topic overlap; surface only capabilities that materially help the current task.'
    ),
    'query',v_query,
    'category',v_category,
    'matched_services',v_matched_services,
    'capabilities',v_caps,
    'coverage_summary',jsonb_build_object(
      'service_types_documented',v_service_count,
      'service_indicator_coverage',jsonb_build_object('wired',v_wired,'partial',v_partial,'parent_only',v_parent,'gap',v_gap),
      'document_standards_active',v_standard_count,
      'external_capability_vocabulary',v_external_vocab_count,
      'known_external_integration_mappings',v_known_integration_count,
      'anti_circumvention_note','Service coverage describes Scout capability maturity only. This manifest intentionally does not disclose current opportunity counts or whether blocked opportunities exist.'
    ),
    'service_coverage',v_services,
    'reported_external_capabilities',v_external,
    'onboarding_required',v_onboarding_required
  );
end;
$function$;

-- Expected smoke outcomes:
-- * scout_get_connection_lead_work_package_v2(...) returns allowed=true for a known surfaced candidate without SQLSTATE 25006.
-- * capability query "Scout Lens Evidence Time Machine Opportunity Constellation" returns exactly:
--   opportunities.scout_lens, opportunities.evidence_time_machine, opportunities.constellations.
-- * capability query "what can Scout do?" still returns the full active catalog.
