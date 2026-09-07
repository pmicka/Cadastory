-- Scout cleaning setup onboarding integration v1
-- Wires operator cleaning products/fluid routes into the existing profile flow.

create or replace function public.scout_update_provider_profile_pre_research(p_organization_id uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  k text;
  v_legacy jsonb;
  v_rigs_clean jsonb;
  v_allowed text[]:=array['home_base','operating_states','preferred_radius_miles','max_travel_miles','crew_size','willing_to_subcontract','services','services_confirmed','equipment','equipment_confirmed','credentials','credentials_confirmed','rigs','rigs_confirmed','readiness','cleaning_products_confirmed'];
  v_now timestamptz:=clock_timestamp();
begin
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then raise exception 'patch must be a JSON object'; end if;
  if public.scout_json_has_forbidden_profile_keys(p_patch) then raise exception 'sensitive identifier fields are not accepted by Scout onboarding'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if not (k=any(v_allowed)) then raise exception 'unsupported profile field: %',k; end if;
  end loop;

  v_legacy:=p_patch-'rigs'-'rigs_confirmed'-'readiness'-'cleaning_products_confirmed';
  if v_legacy<>'{}'::jsonb then perform public.scout_update_provider_onboarding(p_organization_id,v_legacy); end if;

  if p_patch ? 'rigs' then
    select jsonb_agg(value-'capabilities'-'products'-'fluid_routes') into v_rigs_clean from jsonb_array_elements(p_patch->'rigs');
    perform public.scout_update_provider_rigs(p_organization_id,coalesce(v_rigs_clean,'[]'::jsonb));
    perform public.scout_update_provider_rig_cleaning_setup(p_organization_id,p_patch->'rigs');
    perform public.scout_update_provider_rig_capabilities(p_organization_id,p_patch->'rigs');
  end if;

  if p_patch->>'rigs_confirmed'='true' and not (p_patch ? 'rigs') then
    if not exists(
      select 1 from equipment.provider_rigs r
      where r.organization_id=p_organization_id and r.status='active'
        and exists(select 1 from equipment.provider_rig_members rm where rm.rig_id=r.id)
    ) then raise exception 'cannot confirm equipment setup without at least one active rig containing equipment'; end if;
    insert into commerce.provider_onboarding_state(organization_id,equipment_confirmed_at,updated_at)
    values(p_organization_id,v_now,v_now)
    on conflict(organization_id) do update set equipment_confirmed_at=v_now,completed_at=null,updated_at=v_now;
  end if;

  if p_patch ? 'cleaning_products_confirmed' then
    if jsonb_typeof(p_patch->'cleaning_products_confirmed')<>'boolean' then raise exception 'cleaning_products_confirmed must be boolean'; end if;
    insert into commerce.provider_onboarding_state(organization_id,cleaning_products_confirmed_at,updated_at)
    values(p_organization_id,case when (p_patch->>'cleaning_products_confirmed')::boolean then v_now else null end,v_now)
    on conflict(organization_id) do update
      set cleaning_products_confirmed_at=excluded.cleaning_products_confirmed_at,completed_at=null,updated_at=v_now;
  end if;

  if p_patch ? 'readiness' then perform public.scout_update_provider_readiness(p_organization_id,p_patch->'readiness'); end if;
  return public.scout_get_provider_onboarding_status(p_organization_id);
end;
$$;

create or replace function public.scout_update_connection_profile(p_connection_id uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  k text;
  v_identity_patch jsonb:='{}'::jsonb;
  v_profile_patch jsonb;
  v_org uuid;
  v_allowed text[]:=array['business_name','dba_name','sector','home_base','operating_states','preferred_radius_miles','max_travel_miles','crew_size','willing_to_subcontract','services','services_confirmed','equipment','equipment_confirmed','credentials','credentials_confirmed','rigs','rigs_confirmed','readiness','cleaning_products_confirmed'];
begin
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then raise exception 'patch must be a JSON object'; end if;
  if public.scout_json_has_forbidden_profile_keys(p_patch) then raise exception 'sensitive identifier fields are not accepted by Scout onboarding'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if not (k=any(v_allowed)) then raise exception 'unsupported profile field: %',k; end if;
  end loop;

  if p_patch ? 'business_name' then v_identity_patch:=v_identity_patch||jsonb_build_object('business_name',p_patch->'business_name'); end if;
  if p_patch ? 'dba_name' then v_identity_patch:=v_identity_patch||jsonb_build_object('dba_name',p_patch->'dba_name'); end if;
  if p_patch ? 'sector' then v_identity_patch:=v_identity_patch||jsonb_build_object('sector',p_patch->'sector'); end if;
  if v_identity_patch<>'{}'::jsonb then perform public.scout_update_connection_onboarding(p_connection_id,v_identity_patch); end if;

  select organization_id into v_org
  from commerce.provider_agent_connections
  where id=p_connection_id and status='active' and (expires_at is null or expires_at>now());
  if not found then raise exception 'active Scout connection not found'; end if;

  v_profile_patch:=p_patch-'business_name'-'dba_name'-'sector';
  if v_profile_patch<>'{}'::jsonb then
    if v_org is null then return public.scout_get_connection_onboarding_status(p_connection_id); end if;
    perform public.scout_update_provider_profile(v_org,v_profile_patch);
  end if;
  return public.scout_get_connection_onboarding_status(p_connection_id);
end;
$$;

create or replace function public.scout_get_provider_onboarding_status_pre_research(p_organization_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_status jsonb;
  v_tech_missing jsonb;
  v_readiness_required jsonb;
  v_readiness_missing jsonb;
  v_critical text[]:='{}'::text[];
  v_semi text[]:='{}'::text[];
  v_progressive text[]:='{}'::text[];
  v_required_profile jsonb;
  v_missing_answers jsonb;
  v_prompt jsonb;
  v_semi_prompt jsonb;
  v_operating_states text[]:='{}'::text[];
  v_critical_complete boolean;
  v_semi_complete boolean;
  v_profile_complete boolean;
  v_cleaning_selected boolean:=false;
  v_cleaning_confirmed boolean:=false;
  v_cleaning_setup jsonb;
begin
  v_status:=public.scout_clean_provider_onboarding_status(public.scout_get_provider_onboarding_status_raw(p_organization_id));
  select coalesce(array_agg(value),'{}'::text[]) into v_critical from jsonb_array_elements_text(coalesce(v_status->'critical_missing_sections','[]'::jsonb));
  select coalesce(array_agg(value),'{}'::text[]) into v_semi from jsonb_array_elements_text(coalesce(v_status->'semi_critical_missing_sections','[]'::jsonb));
  select coalesce(array_agg(value),'{}'::text[]) into v_progressive from jsonb_array_elements_text(coalesce(v_status->'progressive_missing_sections','[]'::jsonb));
  select coalesce(operating_states,'{}'::text[]), cleaning_products_confirmed_at is not null
    into v_operating_states,v_cleaning_confirmed
  from commerce.provider_onboarding_state where organization_id=p_organization_id;

  select exists(
    select 1
    from commerce.provider_services ps
    join commerce.service_types st on st.id=ps.service_type_id
    left join commerce.service_types parent on parent.id=st.parent_id
    where ps.organization_id=p_organization_id and ps.capability_status='self_attested'
      and (st.slug='exterior-cleaning' or parent.slug='exterior-cleaning')
  ) into v_cleaning_selected;
  v_cleaning_setup:=public.scout_get_provider_cleaning_setup(p_organization_id);

  with selected as (
    select distinct st.id,st.slug,st.name
    from commerce.provider_services ps join commerce.service_types st on st.id=ps.service_type_id
    where ps.organization_id=p_organization_id and ps.capability_status='self_attested'
  ), paths as (
    select s.id service_id,s.slug,s.name,r.id rig_id,r.name rig_name,
           public.scout_get_rig_service_capability_access(p_organization_id,r.id,s.slug) access
    from selected s
    join equipment.provider_rig_services rs on rs.service_type_id=s.id and rs.status='active'
    join equipment.provider_rigs r on r.id=rs.rig_id and r.organization_id=p_organization_id and r.status in ('active','seasonal')
  ), by_service as (
    select service_id,slug,name,coalesce(bool_or((access->>'ready')::boolean),false) ready,
      jsonb_agg(jsonb_build_object('rig_id',rig_id,'rig_name',rig_name,'ready',(access->>'ready')::boolean,'missing_requirements',access->'missing_requirements') order by rig_name) paths
    from paths group by service_id,slug,name
  ), selected_with_empty as (
    select s.id service_id,s.slug,s.name,coalesce(b.ready,false) ready,coalesce(b.paths,'[]'::jsonb) paths
    from selected s left join by_service b on b.service_id=s.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('service_slug',slug,'service_name',name,'paths',paths) order by name) filter(where not ready),'[]'::jsonb)
  into v_tech_missing from selected_with_empty;

  if jsonb_array_length(v_tech_missing)>0 and not ('rig_capabilities'=any(v_critical)) then v_critical:=array_append(v_critical,'rig_capabilities'); end if;
  if v_cleaning_selected and not v_cleaning_confirmed and not ('cleaning_products'=any(v_semi)) then v_semi:=array_prepend('cleaning_products',v_semi); end if;

  with active_paths as (
    select distinct rs.service_type_id,coalesce(rs.delivery_method_id,r.default_delivery_method_id) delivery_method_id
    from equipment.provider_rig_services rs join equipment.provider_rigs r on r.id=rs.rig_id
    where r.organization_id=p_organization_id and r.status in ('active','seasonal') and rs.status='active'
  ), req as (
    select distinct rr.requirement_key,rr.requirement_class,rr.display_name,rr.gate_mode,
      case when rr.jurisdiction_code='STATE' then null else rr.jurisdiction_code end jurisdiction_code,rr.condition
    from active_paths ap
    join commerce.service_readiness_requirements rr on rr.service_type_id=ap.service_type_id
      and rr.requirement_kind='required' and (rr.delivery_method_id is null or rr.delivery_method_id=ap.delivery_method_id)
    where rr.jurisdiction_code is null or rr.jurisdiction_code='US' or rr.jurisdiction_code=any(v_operating_states)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key',requirement_key,'name',display_name,'class',requirement_class,'gate_mode',gate_mode,
    'jurisdiction',jurisdiction_code,'basis','service_readiness_requirement','type','readiness','condition',condition
  ) order by requirement_class,display_name),'[]'::jsonb)
  into v_readiness_required from req;

  select coalesce(jsonb_agg(item),'[]'::jsonb) into v_readiness_missing
  from jsonb_array_elements(v_readiness_required) item
  where not exists(
    select 1 from commerce.provider_readiness_declarations d
    where d.organization_id=p_organization_id and d.requirement_key=item->>'key'
      and ((item->>'jurisdiction') is null or d.jurisdiction_code is null or d.jurisdiction_code=item->>'jurisdiction')
  );

  v_required_profile:=coalesce(v_status->'semi_critical_required_profile','[]'::jsonb)||v_readiness_required;
  v_missing_answers:=coalesce(v_status->'semi_critical_missing_answers','[]'::jsonb)||v_readiness_missing;
  if jsonb_array_length(v_readiness_missing)>0 and not ('readiness_profile'=any(v_semi)) then v_semi:=array_append(v_semi,'readiness_profile'); end if;

  v_critical_complete:=cardinality(v_critical)=0;
  v_semi_complete:=cardinality(v_semi)=0;
  v_profile_complete:=v_critical_complete and v_semi_complete and cardinality(v_progressive)=0;

  v_prompt:=v_status->'next_question';
  if not v_critical_complete and (v_prompt is null or v_prompt='null'::jsonb) and 'rig_capabilities'=any(v_critical) then
    v_prompt:=jsonb_build_object(
      'section','rigs','input','rig_capability_confirmation',
      'prompt','Scout has the rig structure, but it still needs enough technical detail to confirm that at least one configured rig can perform each selected service. Confirm only the missing capability shown below or update the relevant equipment model. Do not provide serial numbers.',
      'technical_missing',v_tech_missing
    );
  end if;

  v_semi_prompt:=v_status->'semi_critical_prompt';
  if v_critical_complete and v_cleaning_selected and not v_cleaning_confirmed then
    v_semi_prompt:=jsonb_build_object(
      'section','cleaning_products','tier','semi_critical','input','rig_cleaning_setup','blocking_for_affected_work',true,
      'prompt','For each cleaning rig, list the cleaners, chemicals, restoration products, surfactants, or process fluids you actually use and, when known, which fluid route/service they use. A water-only or no-cleaner setup is a valid answer. Use a catalog product when it matches; otherwise preserve the exact operator-entered product name and optional manufacturer/product kind. Do not ask the operator to guess wetted-material compatibility or chemistry safety—Scout researches that separately.',
      'update_contract',jsonb_build_object(
        'tool','scout_update_profile','rig_fields',jsonb_build_array('products','fluid_routes'),'confirmation_field','cleaning_products_confirmed'
      ),
      'current_setup',v_cleaning_setup
    );
  elsif v_critical_complete and jsonb_array_length(v_readiness_missing)>0 then
    if v_semi_prompt is null then
      v_semi_prompt:=jsonb_build_object(
        'section','prerequisites','tier','semi_critical','input','credential_or_readiness_declarations','blocking_for_affected_work',true,
        'prompt','Before Scout surfaces work that depends on a required insurance, calibration, plan, training, documentation, license, or certificate, confirm the type/status of the relevant prerequisite below. This is a Scout profile-fit check unless explicitly marked hard_gate; no identifier numbers are needed.',
        'required_profile',v_required_profile,'missing_answers',v_missing_answers
      );
    else
      v_semi_prompt:=jsonb_set(
        jsonb_set(jsonb_set(v_semi_prompt,'{required_profile}',v_required_profile,true),'{missing_answers}',v_missing_answers,true),
        '{input}','"credential_or_readiness_declarations"'::jsonb,true
      );
    end if;
  end if;

  return v_status || jsonb_build_object(
    'version',4,
    'onboarding_required',not v_critical_complete,
    'critical_complete',v_critical_complete,
    'semi_critical_complete',v_semi_complete,
    'profile_complete',v_profile_complete,
    'complete',v_profile_complete,
    'critical_missing_sections',to_jsonb(v_critical),
    'semi_critical_missing_sections',to_jsonb(v_semi),
    'progressive_missing_sections',to_jsonb(v_progressive),
    'missing_sections',to_jsonb(v_critical||v_semi||v_progressive),
    'next_question',v_prompt,
    'semi_critical_prompt',v_semi_prompt,
    'semi_critical_required_profile',v_required_profile,
    'semi_critical_missing_answers',v_missing_answers,
    'technical_rig_requirements_missing',v_tech_missing,
    'cleaning_setup',v_cleaning_setup
  );
end;
$$;

create or replace function public.scout_get_onboarding_catalog(p_service_slugs text[] default null::text[], p_operating_states text[] default null::text[])
returns jsonb
language sql
stable security definer
set search_path to ''
as $$
with svc as (
  select st.id,st.slug,st.name,p.slug parent_slug,p.name parent_name
  from commerce.service_types st
  left join commerce.service_types p on p.id=st.parent_id
  where st.active
), selected as (
  select id from svc where p_service_slugs is not null and slug=any(p_service_slugs)
), creds as (
  select distinct ct.slug,ct.name,ct.credential_class,ct.issuing_authority,ct.jurisdiction_code,r.requirement_kind,r.notes
  from commerce.service_credential_requirements r
  join compliance.credential_types ct on ct.id=r.credential_type_id
  join selected s on s.id=r.service_type_id
  where ct.slug<>'faa-airspace-authorization' and (
    r.jurisdiction_code is null or r.jurisdiction_code='US' or r.jurisdiction_code='STATE'
    or p_operating_states is null or r.jurisdiction_code=any(p_operating_states)
  )
)
select jsonb_build_object(
  'version',3,
  'privacy',jsonb_build_object(
    'collect_credential_identifiers',false,
    'collect_equipment_serial_numbers_during_onboarding',false,
    'optional_post_confirmation_serial_recordkeeping',true,
    'instruction','Ask only for business-relevant setup facts. Never ask for license, certificate, registration, policy, or equipment serial numbers during onboarding. Product names, manufacturers, mix descriptions and rig assignments are allowed business setup data; do not request proprietary formulas unless the operator explicitly chooses to store them.'
  ),
  'services',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'parent_slug',parent_slug,'parent_name',parent_name) order by name),'[]'::jsonb)
              from svc where p_service_slugs is null or slug=any(p_service_slugs)),
  'relevant_credentials',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'class',credential_class,'authority',issuing_authority,'jurisdiction',jurisdiction_code,'requirement',requirement_kind,'notes',notes) order by requirement_kind,name),'[]'::jsonb) from creds),
  'credential_states',jsonb_build_array('active','expired','pursuing','none','unknown'),
  'equipment_instruction','Use scout_search_equipment_models for model resolution. If no catalog model matches, preserve the operator-entered model name. Never request a serial number during setup.',
  'cleaning_product_instruction','For cleaning operators, capture the actual cleaners/chemicals/process fluids used by each rig. If Scout recognizes the product uniquely it may resolve it to the catalog; otherwise preserve the operator-entered name and optional manufacturer/product kind. Unknown identity or compatibility stays unresolved. Do not ask the operator to guess chemistry compatibility.',
  'cleaning_product_kinds',jsonb_build_array('cleaner','window_cleaner','surfactant','biocide','disinfectant','restoration_chemical','descaler','solvent','process_water','other'),
  'fluid_route_kinds',jsonb_build_array('cleaning_delivery','window_wash','rinse','chemical_transfer','mixed_service','other'),
  'fluid_route_policy','Fluid route details are optional during initial capture. Create an operator-scoped route shell when the route is known but its wetted components are not yet mapped; Scout should research/map the route later rather than asking the operator to infer compatibility.'
)
$$;
