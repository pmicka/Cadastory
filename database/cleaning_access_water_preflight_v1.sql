-- Scout cleaning access + water preflight v1
-- Materializes mapped OSM staging hypotheses, models target water-source readiness,
-- and extends operator rig capabilities for cleaning preflight without creating a parallel profile system.

-- Rig facts used by cleaning access/water preflight.
insert into equipment.capability_types(id,slug,name,value_type,unit_family,description,attributes)
values
  (gen_random_uuid(),'onboard_water_capacity_gal','Onboard water capacity','numeric','volume','Usable onboard water storage capacity in US gallons for the configured rig.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',10,'recommended_unit','gal')),
  (gen_random_uuid(),'pure_water_production_gph','Pure-water production rate','numeric','flow','Configured RO/DI or equivalent pure-water production rate in gallons per hour.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',20,'recommended_unit','gph')),
  (gen_random_uuid(),'customer_spigot_refill','Customer spigot refill','boolean',null,'Rig can refill from a suitable customer-provided hose bib/spigot when permission and site conditions allow.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',30)),
  (gen_random_uuid(),'municipal_fill_refill','Municipal fill-station refill','boolean',null,'Operator can use an authorized municipal or commercial bulk-water fill station as part of the refill workflow.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',40)),
  (gen_random_uuid(),'hydrant_refill','Hydrant refill capability','boolean',null,'Operator is equipped and operationally prepared to use an authorized hydrant fill when legally permitted.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',50)),
  (gen_random_uuid(),'backflow_prevention_capable','Backflow prevention capability','boolean',null,'Rig carries or can provide suitable backflow-prevention equipment when a water source requires it.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',60)),
  (gen_random_uuid(),'bulk_water_delivery_refill','Bulk-water delivery refill','boolean',null,'Operator can arrange bulk-water delivery or equivalent external replenishment for a job.',jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',70))
on conflict (slug) do update
set name=excluded.name,
    value_type=excluded.value_type,
    unit_family=excluded.unit_family,
    description=excluded.description,
    attributes=equipment.capability_types.attributes||excluded.attributes,
    updated_at=clock_timestamp();

update equipment.capability_types
set attributes=attributes||case slug
  when 'max_hose_length_ft' then jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',5,'recommended_unit','ft')
  when 'max_liquid_flow_gpm' then jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',12,'recommended_unit','gpm')
  when 'max_working_pressure_psi' then jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',14,'recommended_unit','psi')
  when 'pure_water_supply' then jsonb_build_object('onboarding_group','cleaning_access_preflight','progressive',true,'prompt_order',18)
  else '{}'::jsonb end,
  updated_at=clock_timestamp()
where slug in ('max_hose_length_ft','max_liquid_flow_gpm','max_working_pressure_psi','pure_water_supply');

-- Target water-source facts. provider_organization_id NULL means general/site evidence;
-- provider-specific rows remain scoped to that provider.
create table if not exists decisioning.cleaning_water_sources(
  id uuid primary key default gen_random_uuid(),
  building_source_record_id uuid not null references ingest.raw_records(id) on delete cascade,
  provider_organization_id uuid null references core.organizations(id) on delete cascade,
  source_type text not null check (source_type in ('customer_spigot','onsite_plumbed','hydrant','municipal_fill_station','bulk_delivery','other')),
  source_status text not null default 'candidate' check (source_status in ('candidate','observed','verified','authorized','unavailable')),
  source_location geography(Point,4326),
  distance_to_building_ft numeric check (distance_to_building_ft is null or distance_to_building_ft>=0),
  estimated_flow_gpm numeric check (estimated_flow_gpm is null or estimated_flow_gpm>0),
  available_volume_gal numeric check (available_volume_gal is null or available_volume_gal>=0),
  permission_required boolean not null default true,
  permission_status text not null default 'unknown' check (permission_status in ('unknown','not_required','required','requested','authorized','denied')),
  backflow_required boolean,
  backflow_status text not null default 'unknown' check (backflow_status in ('unknown','not_required','required','available','verified')),
  source_kind text not null default 'derived' check (source_kind in ('manual','map_review','site_plan','customer','operator','derived','other')),
  confidence numeric not null default 0.5 check (confidence>=0 and confidence<=1),
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists cleaning_water_sources_building_idx
  on decisioning.cleaning_water_sources(building_source_record_id,source_status,confidence desc);
create index if not exists cleaning_water_sources_provider_idx
  on decisioning.cleaning_water_sources(provider_organization_id,building_source_record_id)
  where provider_organization_id is not null;

create or replace view decisioning.v_building_cleaning_water_source_summary as
with ranked as (
  select w.*,
         row_number() over (
           partition by w.building_source_record_id
           order by
             case w.source_status when 'authorized' then 5 when 'verified' then 4 when 'observed' then 3 when 'candidate' then 2 when 'unavailable' then 1 else 0 end desc,
             case when w.permission_status in ('authorized','not_required') then 2 when w.permission_status='denied' then 0 else 1 end desc,
             w.confidence desc,
             w.distance_to_building_ft nulls last,
             w.id
         ) as rn
  from decisioning.cleaning_water_sources w
  where w.provider_organization_id is null
), agg as (
  select building_source_record_id,
         count(*)::integer as source_count,
         count(*) filter (where source_status in ('verified','authorized'))::integer as verified_or_authorized_count,
         count(*) filter (where source_status in ('candidate','observed'))::integer as candidate_or_observed_count,
         bool_or(source_status='unavailable') as any_unavailable,
         bool_or(backflow_required is true) as any_backflow_required,
         bool_or(permission_required) as any_permission_required
  from ranked
  group by building_source_record_id
)
select b.source_record_id,
       coalesce(a.source_count,0) as source_count,
       coalesce(a.verified_or_authorized_count,0) as verified_or_authorized_count,
       coalesce(a.candidate_or_observed_count,0) as candidate_or_observed_count,
       r.id as best_water_source_id,
       r.source_type as best_water_source_type,
       r.source_status as best_water_source_status,
       r.distance_to_building_ft as best_water_source_distance_ft,
       r.estimated_flow_gpm as best_water_source_estimated_flow_gpm,
       r.available_volume_gal as best_water_source_available_volume_gal,
       r.permission_required as best_water_source_permission_required,
       r.permission_status as best_water_source_permission_status,
       r.backflow_required as best_water_source_backflow_required,
       r.backflow_status as best_water_source_backflow_status,
       r.confidence as best_water_source_confidence,
       case
         when coalesce(a.verified_or_authorized_count,0)>0 then 'verified_source_available'
         when coalesce(a.candidate_or_observed_count,0)>0 then 'candidate_source_verify'
         when coalesce(a.source_count,0)>0 and coalesce(a.any_unavailable,false) then 'no_usable_source_documented'
         else 'unknown_verify'
       end as water_source_readiness,
       case
         when coalesce(a.verified_or_authorized_count,0)>0 then 'A usable water source is documented; confirm job-specific permission, flow and connection details before execution.'
         when coalesce(a.candidate_or_observed_count,0)>0 then 'A possible water source is documented but is not yet verified for this job.'
         when coalesce(a.source_count,0)>0 then 'Scout has water-source evidence, but no currently usable source is established.'
         else 'Water source is unknown; verify customer supply, onboard capacity, refill plan, or another authorized source during preflight.'
       end as water_source_note
from decisioning.v_building_cleaning_hose_baseline b
left join agg a on a.building_source_record_id=b.source_record_id
left join ranked r on r.building_source_record_id=b.source_record_id and r.rn=1;

-- Persist the top mapped OSM staging hypotheses. Derived rows stay explicitly estimated
-- and never replace manual, customer, operator, or site-reviewed scenarios.
create unique index if not exists cleaning_access_scenarios_derived_osm_key
  on decisioning.cleaning_access_scenarios(building_source_record_id,scenario_name)
  where source_kind='derived' and provider_organization_id is null;

create or replace function decisioning.refresh_cleaning_access_scenarios(p_limit_per_building integer default 3)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit_per_building,3),10));
  v_deleted integer:=0;
  v_upserted integer:=0;
  v_buildings integer:=0;
begin
  with ranked as (
    select h.*,
           row_number() over (
             partition by h.source_record_id
             order by
               case h.staging_hypothesis_strength when 'strong' then 3 when 'moderate' then 2 when 'weak' then 1 else 0 end desc,
               h.source_confidence desc nulls last,
               h.mapped_access_lower_bound_hose_ft asc nulls last,
               h.representative_ground_run_ft asc nulls last,
               h.access_feature_id
           ) as rn
    from decisioning.v_cleaning_hose_access_hypotheses h
    where h.mapped_access_lower_bound_hose_ft is not null
      and h.representative_ground_run_ft is not null
  ), keepers as (
    select source_record_id,'osm_access:'||access_feature_id::text as scenario_name
    from ranked where rn<=v_limit
  )
  delete from decisioning.cleaning_access_scenarios s
  where s.source_kind='derived'
    and s.provider_organization_id is null
    and s.attributes->>'materializer'='osm_cleaning_access_v1'
    and not exists(
      select 1 from keepers k
      where k.source_record_id=s.building_source_record_id and k.scenario_name=s.scenario_name
    );
  get diagnostics v_deleted=row_count;

  with ranked as (
    select h.*,
           row_number() over (
             partition by h.source_record_id
             order by
               case h.staging_hypothesis_strength when 'strong' then 3 when 'moderate' then 2 when 'weak' then 1 else 0 end desc,
               h.source_confidence desc nulls last,
               h.mapped_access_lower_bound_hose_ft asc nulls last,
               h.representative_ground_run_ft asc nulls last,
               h.access_feature_id
           ) as rn
    from decisioning.v_cleaning_hose_access_hypotheses h
    where h.mapped_access_lower_bound_hose_ft is not null
      and h.representative_ground_run_ft is not null
  )
  insert into decisioning.cleaning_access_scenarios(
    building_source_record_id,provider_organization_id,scenario_name,facade_label,facade_axis,
    staging_point,launch_point,ground_run_ft_override,routing_detour_ft,access_class,access_status,
    obstacle_flags,source_kind,confidence,notes,attributes,updated_at
  )
  select
    r.source_record_id,
    null,
    'osm_access:'||r.access_feature_id::text,
    coalesce(nullif(r.staging_feature_name,''),r.feature_class||coalesce('/'||nullif(r.feature_subclass,''),'')),
    'unknown',r.candidate_point,null,r.representative_ground_run_ft,0,'unknown','estimated',
    array_remove(array[
      case when coalesce(r.barrier_count,0)>0 then 'mapped_barriers_present' end,
      case when coalesce(r.gate_count,0)>0 then 'mapped_gates_present' end
    ]::text[],null),
    'derived',
    least(0.95::numeric,coalesce(r.source_confidence,0.5::numeric) *
      case r.staging_hypothesis_strength when 'strong' then 1.0 when 'moderate' then 0.9 when 'weak' then 0.8 else 0.7 end),
    r.estimate_caveat,
    jsonb_build_object(
      'materializer','osm_cleaning_access_v1','hypothesis_rank',r.rn,'access_feature_id',r.access_feature_id,
      'feature_class',r.feature_class,'feature_subclass',r.feature_subclass,'staging_feature_name',r.staging_feature_name,
      'staging_hypothesis_strength',r.staging_hypothesis_strength,'candidate_status',r.candidate_status,
      'source_confidence',r.source_confidence,'minimum_edge_distance_ft',r.minimum_edge_distance_ft,
      'representative_ground_run_ft',r.representative_ground_run_ft,'mapped_access_lower_bound_hose_ft',r.mapped_access_lower_bound_hose_ft,
      'barrier_count',r.barrier_count,'gate_count',r.gate_count,'nearest_barrier_m',r.nearest_barrier_m,'nearest_gate_m',r.nearest_gate_m,
      'estimate_basis',r.estimate_basis,'estimate_caveat',r.estimate_caveat
    ),clock_timestamp()
  from ranked r where r.rn<=v_limit
  on conflict (building_source_record_id,scenario_name)
    where source_kind='derived' and provider_organization_id is null
  do update set
    facade_label=excluded.facade_label,facade_axis=excluded.facade_axis,staging_point=excluded.staging_point,
    ground_run_ft_override=excluded.ground_run_ft_override,routing_detour_ft=excluded.routing_detour_ft,
    access_class=excluded.access_class,access_status=excluded.access_status,obstacle_flags=excluded.obstacle_flags,
    confidence=excluded.confidence,notes=excluded.notes,attributes=excluded.attributes,updated_at=clock_timestamp();
  get diagnostics v_upserted=row_count;

  select count(distinct building_source_record_id) into v_buildings
  from decisioning.cleaning_access_scenarios
  where source_kind='derived' and provider_organization_id is null
    and attributes->>'materializer'='osm_cleaning_access_v1';

  return jsonb_build_object('materializer','osm_cleaning_access_v1','limit_per_building',v_limit,'deleted_stale',v_deleted,'upserted',v_upserted,'materialized_buildings',v_buildings);
end;
$$;

comment on function decisioning.refresh_cleaning_access_scenarios(integer) is
'Materializes the top mapped OSM staging hypotheses into cleaning_access_scenarios. Derived rows remain estimated lower-bound hypotheses and never replace manual/site-verified scenarios.';

create or replace view decisioning.v_provider_cleaning_rig_preflight_capabilities as
with cleaning_rigs as (
  select distinct r.id as rig_id,r.organization_id,r.name as rig_name,r.status
  from equipment.provider_rigs r
  left join equipment.provider_rig_services rs on rs.rig_id=r.id and rs.status='active'
  left join commerce.service_types st on st.id=rs.service_type_id
  left join commerce.service_types parent on parent.id=st.parent_id
  where r.status in ('active','seasonal')
    and (st.id is null or st.slug='exterior-cleaning' or parent.slug='exterior-cleaning' or st.slug in ('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning','solar-pv-cleaning'))
), caps as (
  select r.rig_id,r.organization_id,r.rig_name,r.status,
         c->>'slug' as slug,nullif(c->>'value_numeric','')::numeric as value_numeric,
         case when c ? 'value_boolean' and c->'value_boolean' <> 'null'::jsonb then (c->>'value_boolean')::boolean end as value_boolean
  from cleaning_rigs r
  left join lateral jsonb_array_elements(public.scout_get_rig_effective_capabilities(r.rig_id)) c on true
)
select rig_id,organization_id,rig_name,status,
       max(value_numeric) filter(where slug='max_hose_length_ft') as max_hose_length_ft,
       max(value_numeric) filter(where slug='max_liquid_flow_gpm') as max_liquid_flow_gpm,
       max(value_numeric) filter(where slug='max_working_pressure_psi') as max_working_pressure_psi,
       max(value_numeric) filter(where slug='onboard_water_capacity_gal') as onboard_water_capacity_gal,
       max(value_numeric) filter(where slug='pure_water_production_gph') as pure_water_production_gph,
       bool_or(coalesce(value_boolean,false)) filter(where slug='pure_water_supply') as pure_water_supply,
       bool_or(coalesce(value_boolean,false)) filter(where slug='customer_spigot_refill') as customer_spigot_refill,
       bool_or(coalesce(value_boolean,false)) filter(where slug='municipal_fill_refill') as municipal_fill_refill,
       bool_or(coalesce(value_boolean,false)) filter(where slug='hydrant_refill') as hydrant_refill,
       bool_or(coalesce(value_boolean,false)) filter(where slug='backflow_prevention_capable') as backflow_prevention_capable,
       bool_or(coalesce(value_boolean,false)) filter(where slug='bulk_water_delivery_refill') as bulk_water_delivery_refill,
       count(*) filter(where slug is not null)::integer as effective_capability_count
from caps group by rig_id,organization_id,rig_name,status;

create or replace view decisioning.v_building_cleaning_preflight_summary as
select h.source_record_id,h.property_address,h.property_city,h.state_code,h.county_name,h.relevance_tier,
       h.hose_model_status,h.geometry_only_recommended_typical_ft,
       h.access_modeled_min_hose_ft as mapped_access_lower_bound_hose_ft,
       h.access_modeled_typical_hose_ft as mapped_access_typical_hose_ft,
       h.access_modeled_max_hose_ft as mapped_access_max_hose_ft,
       h.scout_display_hose_ft,h.scout_display_hose_basis,h.best_scenario_id,h.best_scenario_name,
       h.best_scenario_recommended_hose_ft,h.best_scenario_ground_run_ft,h.best_scenario_confidence,
       s.facade_label as likely_staging_label,s.attributes->>'feature_class' as likely_staging_feature_class,
       nullif(s.attributes->>'minimum_edge_distance_ft','')::numeric as likely_staging_edge_distance_ft,
       coalesce(nullif(s.attributes->>'barrier_count','')::integer,0) as mapped_barrier_count,
       coalesce(nullif(s.attributes->>'gate_count','')::integer,0) as mapped_gate_count,
       w.water_source_readiness,w.best_water_source_type,w.best_water_source_status,w.best_water_source_distance_ft,
       w.best_water_source_permission_status,w.best_water_source_backflow_required,w.best_water_source_backflow_status,w.water_source_note,
       case
         when h.hose_model_status='access_modeled' and w.water_source_readiness='verified_source_available' then 'mapped_access_and_water_source_available'
         when h.hose_model_status='access_modeled' then 'mapped_access_water_verify'
         when h.hose_model_status='access_needed' then 'access_enrichment_needed'
         else 'preflight_incomplete'
       end as cleaning_preflight_status
from decisioning.v_building_cleaning_hose_summary h
left join decisioning.cleaning_access_scenarios s on s.id=h.best_scenario_id
left join decisioning.v_building_cleaning_water_source_summary w on w.source_record_id=h.source_record_id;

create or replace function decisioning.get_cleaning_preflight(p_building_source_record_id uuid,p_provider_organization_id uuid)
returns jsonb
language sql stable security invoker set search_path to ''
as $$
with site as (
  select * from decisioning.v_building_cleaning_preflight_summary where source_record_id=p_building_source_record_id
), water as (
  select w.*,row_number() over(order by
    case w.source_status when 'authorized' then 5 when 'verified' then 4 when 'observed' then 3 when 'candidate' then 2 when 'unavailable' then 1 else 0 end desc,
    case when w.permission_status in ('authorized','not_required') then 2 when w.permission_status='denied' then 0 else 1 end desc,
    w.confidence desc,w.distance_to_building_ft nulls last,w.id) rn
  from decisioning.cleaning_water_sources w
  where w.building_source_record_id=p_building_source_record_id
    and (w.provider_organization_id is null or w.provider_organization_id=p_provider_organization_id)
), best_water as (select * from water where rn=1), rigs as (
  select r.*,
    case
      when s.mapped_access_typical_hose_ft is null and s.mapped_access_lower_bound_hose_ft is null then 'site_hose_unknown'
      when r.max_hose_length_ft is null then 'rig_hose_unknown'
      when s.mapped_access_typical_hose_ft is not null and r.max_hose_length_ft>=s.mapped_access_typical_hose_ft then 'likely_fit_typical'
      when s.mapped_access_lower_bound_hose_ft is not null and r.max_hose_length_ft>=s.mapped_access_lower_bound_hose_ft then 'staging_dependent_fit'
      else 'below_mapped_lower_bound' end as hose_fit_status,
    case
      when bw.id is not null and bw.source_status in ('verified','authorized')
        and (not bw.permission_required or bw.permission_status in ('authorized','not_required'))
        and (bw.backflow_required is not true or coalesce(r.backflow_prevention_capable,false))
        and ((bw.source_type in ('customer_spigot','onsite_plumbed') and coalesce(r.customer_spigot_refill,false))
          or (bw.source_type='hydrant' and coalesce(r.hydrant_refill,false))
          or (bw.source_type='municipal_fill_station' and coalesce(r.municipal_fill_refill,false))
          or (bw.source_type='bulk_delivery' and coalesce(r.bulk_water_delivery_refill,false)) or bw.source_type='other')
        then 'verified_source_rig_compatible'
      when coalesce(r.onboard_water_capacity_gal,0)>0 then 'onboard_capacity_available_demand_unknown'
      when coalesce(r.customer_spigot_refill,false) or coalesce(r.hydrant_refill,false) or coalesce(r.municipal_fill_refill,false) or coalesce(r.bulk_water_delivery_refill,false)
        then 'refill_strategy_available_source_verify'
      else 'water_plan_missing' end as water_fit_status
  from decisioning.v_provider_cleaning_rig_preflight_capabilities r cross join site s left join best_water bw on true
  where r.organization_id=p_provider_organization_id
), ranked_rigs as (
  select r.*,row_number() over(order by
    case r.hose_fit_status when 'likely_fit_typical' then 4 when 'staging_dependent_fit' then 3 when 'rig_hose_unknown' then 2 when 'site_hose_unknown' then 1 else 0 end desc,
    case r.water_fit_status when 'verified_source_rig_compatible' then 4 when 'onboard_capacity_available_demand_unknown' then 3 when 'refill_strategy_available_source_verify' then 2 else 0 end desc,
    r.max_hose_length_ft desc nulls last,r.rig_name) rn
  from rigs r
)
select jsonb_build_object(
  'building',to_jsonb(s),
  'water_source',case when bw.id is null then jsonb_build_object('readiness','unknown_verify','note','Water source is unknown; verify customer supply, onboard capacity, refill plan, or another authorized source during preflight.') else jsonb_build_object(
    'id',bw.id,'type',bw.source_type,'status',bw.source_status,'distance_to_building_ft',bw.distance_to_building_ft,
    'estimated_flow_gpm',bw.estimated_flow_gpm,'available_volume_gal',bw.available_volume_gal,'permission_required',bw.permission_required,
    'permission_status',bw.permission_status,'backflow_required',bw.backflow_required,'backflow_status',bw.backflow_status,'confidence',bw.confidence) end,
  'rig_count',(select count(*) from ranked_rigs),
  'best_rig',(select to_jsonb(r)-'rn' from ranked_rigs r where rn=1),
  'rig_options',coalesce((select jsonb_agg(to_jsonb(r)-'rn' order by rn) from ranked_rigs r),'[]'::jsonb),
  'decision_rule','Mapped hose estimates are lower-bound/typical planning hypotheses, not a final route. Water readiness requires a verified source or a provider refill strategy; onboard capacity alone does not establish sufficient job water volume.'
)
from site s left join best_water bw on true;
$$;

create or replace function public.scout_get_cleaning_access_onboarding_catalog()
returns jsonb
language sql stable security definer set search_path to ''
as $$
select jsonb_build_object(
  'section','cleaning_access_preflight','tier','progressive','blocking_for_initial_value',false,
  'instruction','Capture these rig facts progressively when they become relevant to cleaning job preflight. Do not block initial Scout value merely because a preflight detail is unknown.',
  'capabilities',coalesce(jsonb_agg(jsonb_build_object(
      'slug',slug,'name',name,'value_type',value_type,'unit_family',unit_family,'description',description,
      'recommended_unit',attributes->>'recommended_unit','prompt_order',coalesce((attributes->>'prompt_order')::integer,999)
    ) order by coalesce((attributes->>'prompt_order')::integer,999),name),'[]'::jsonb),
  'water_source_types',jsonb_build_array('customer_spigot','onsite_plumbed','hydrant','municipal_fill_station','bulk_delivery','other'),
  'water_source_rule','No source is assumed from OSM access alone. Unknown remains unknown until customer/operator/site evidence establishes a source.',
  'privacy','Do not request equipment serial numbers, utility account identifiers, hydrant permit numbers, or other unnecessary identifiers during onboarding.'
)
from equipment.capability_types where attributes->>'onboarding_group'='cleaning_access_preflight';
$$;

-- Additive onboarding-catalog evolution: expose the progressive cleaning-access section
-- without making it a blocker for first value.
create or replace function public.scout_get_onboarding_catalog(p_service_slugs text[] default null::text[], p_operating_states text[] default null::text[])
returns jsonb
language sql stable security definer set search_path to ''
as $$
with svc as (
  select st.id,st.slug,st.name,st.description,p.slug parent_slug,p.name parent_name,
         exists(select 1 from commerce.service_types c where c.parent_id=st.id and c.active) has_children
  from commerce.service_types st left join commerce.service_types p on p.id=st.parent_id where st.active
), selected as (select id from svc where p_service_slugs is not null and slug=any(p_service_slugs)), creds as (
  select distinct ct.slug,ct.name,ct.credential_class,ct.issuing_authority,ct.jurisdiction_code,r.requirement_kind,r.notes
  from commerce.service_credential_requirements r join compliance.credential_types ct on ct.id=r.credential_type_id join selected s on s.id=r.service_type_id
  where ct.slug<>'faa-airspace-authorization' and (r.jurisdiction_code is null or r.jurisdiction_code='US' or r.jurisdiction_code='STATE' or p_operating_states is null or r.jurisdiction_code=any(p_operating_states))
), cleaning_scope as (
  select exists(select 1 from svc s where (p_service_slugs is null or s.slug=any(p_service_slugs)) and (s.slug='exterior-cleaning' or s.parent_slug='exterior-cleaning')) relevant
)
select jsonb_build_object(
  'version',5,
  'privacy',jsonb_build_object('collect_credential_identifiers',false,'collect_equipment_serial_numbers_during_onboarding',false,'optional_post_confirmation_serial_recordkeeping',true,
    'instruction','Ask only for business-relevant setup facts. Never ask for license, certificate, registration, policy, or equipment serial numbers during onboarding. Product names, manufacturers, mix descriptions and rig assignments are allowed business setup data; do not request proprietary formulas unless the operator explicitly chooses to store them.'),
  'services',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'description',description,'parent_slug',parent_slug,'parent_name',parent_name,'has_children',has_children)
    order by coalesce(parent_name,name),case when parent_slug is null then 0 else 1 end,name),'[]'::jsonb) from svc where p_service_slugs is null or slug=any(p_service_slugs)),
  'service_selection_policy',jsonb_build_object('umbrella_and_specialization_are_distinct',true,'exterior_cleaning_rule','Exterior Cleaning is an umbrella. When an operator selects it, ask which supported child services they actually perform rather than inferring every specialty.',
    'supported_exterior_cleaning_children',jsonb_build_array('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning','solar-pv-cleaning'),
    'pressure_softwash_rule','Pressure wash and soft wash are execution workflows under Building Envelope Cleaning, not separate commercial services.','no_specialty_is_valid',true),
  'exterior_cleaning_taxonomy',case when (select relevant from cleaning_scope) then public.scout_get_service_taxonomy('exterior-cleaning') else null end,
  'cleaning_workflows',case when (select relevant from cleaning_scope) then public.scout_get_cleaning_workflow_catalog(null) else jsonb_build_object('workflows','[]'::jsonb) end,
  'cleaning_access_preflight',case when (select relevant from cleaning_scope) then public.scout_get_cleaning_access_onboarding_catalog() else null end,
  'relevant_credentials',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'class',credential_class,'authority',issuing_authority,'jurisdiction',jurisdiction_code,'requirement',requirement_kind,'notes',notes) order by requirement_kind,name),'[]'::jsonb) from creds),
  'credential_states',jsonb_build_array('active','expired','pursuing','none','unknown'),
  'equipment_instruction','Use scout_search_equipment_models for model resolution. If no catalog model matches, preserve the operator-entered model name. Never request a serial number during setup.',
  'cleaning_product_instruction','For cleaning operators, capture the actual cleaners/chemicals/process fluids used by each rig. If Scout recognizes the product uniquely it may resolve it to the catalog; otherwise preserve the operator-entered name and optional manufacturer/product kind. Unknown identity or compatibility stays unresolved. Do not ask the operator to guess chemistry compatibility.',
  'cleaning_product_kinds',jsonb_build_array('cleaner','window_cleaner','surfactant','biocide','disinfectant','restoration_chemical','descaler','solvent','process_water','other'),
  'fluid_route_kinds',jsonb_build_array('cleaning_delivery','window_wash','rinse','chemical_transfer','mixed_service','other'),
  'fluid_route_policy','Fluid route details are optional during initial capture. Create an operator-scoped route shell when the route is known but its wetted components are not yet mapped; Scout should research/map the route later rather than asking the operator to infer compatibility.'
)
$$;
