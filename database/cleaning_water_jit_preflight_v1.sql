-- Scout just-in-time cleaning water access + water-constrained hose math v1
-- Runtime behavior:
--   * no regional bulk water mapping
--   * lookup is explicitly requested by job/preflight/opportunity workflows
--   * mapped hydrants/taps are candidates, never authorization
--   * source->rig supply hose and rig->building cleaning hose remain separate lines
--   * exact water location can constrain which staging hypotheses are plausible

alter table decisioning.cleaning_water_sources
  add column if not exists source_native_id text,
  add column if not exists observed_at timestamptz,
  add column if not exists expires_at timestamptz;

create unique index if not exists cleaning_water_sources_external_identity_uidx
on decisioning.cleaning_water_sources(
  building_source_record_id,
  coalesce(provider_organization_id,'00000000-0000-0000-0000-000000000000'::uuid),
  source_kind,
  source_native_id
)
where source_native_id is not null;

create index if not exists cleaning_water_sources_location_gix
on decisioning.cleaning_water_sources using gist(source_location)
where source_location is not null;

insert into equipment.capability_types(slug,name,value_type,unit_family,description,attributes)
values(
  'max_water_supply_hose_length_ft','Maximum water-supply hose length','numeric','length',
  'Maximum practical source-to-rig water-supply hose length in feet for the configured cleaning rig. This is distinct from the aircraft/cleaning hose.',
  jsonb_build_object('source','Scout cleaning preflight taxonomy','version',1,'recommended_unit','ft','onboarding_tier','progressive','prompt_order',15)
)
on conflict(slug) do update set
  name=excluded.name,value_type=excluded.value_type,unit_family=excluded.unit_family,description=excluded.description,
  attributes=coalesce(equipment.capability_types.attributes,'{}'::jsonb)||excluded.attributes,updated_at=now();

create table if not exists decisioning.cleaning_water_enrichment_queue(
  id uuid primary key default gen_random_uuid(),
  building_source_record_id uuid not null references ingest.raw_records(id) on delete cascade,
  provider_organization_id uuid references core.organizations(id) on delete cascade,
  reason text not null,
  state text not null default 'pending',
  priority integer not null default 50,
  search_radius_m numeric not null default 400,
  requested_source_types text[] not null default array['onsite_plumbed','hydrant']::text[],
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  last_error text,
  source_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cleaning_water_enrichment_queue_reason_check check(reason in ('plan_job','job_preflight','strong_opportunity','explicit_user_request','rig_water_dependency','comparison_preflight','other')),
  constraint cleaning_water_enrichment_queue_state_check check(state in ('pending','processing','complete','failed','cancelled')),
  constraint cleaning_water_enrichment_queue_priority_check check(priority between 0 and 100),
  constraint cleaning_water_enrichment_queue_radius_check check(search_radius_m between 50 and 1500),
  constraint cleaning_water_enrichment_queue_attempt_check check(attempt_count>=0),
  constraint cleaning_water_enrichment_queue_source_types_check check(requested_source_types <@ array['customer_spigot','onsite_plumbed','hydrant','municipal_fill_station','other']::text[])
);

create unique index if not exists cleaning_water_enrichment_queue_active_uidx
on decisioning.cleaning_water_enrichment_queue(
  building_source_record_id,
  coalesce(provider_organization_id,'00000000-0000-0000-0000-000000000000'::uuid)
)
where state in ('pending','processing');

create index if not exists cleaning_water_enrichment_queue_work_idx
on decisioning.cleaning_water_enrichment_queue(state,next_attempt_at,priority desc,created_at);

create or replace view decisioning.v_provider_cleaning_rig_preflight_capabilities as
with cleaning_rigs as (
  select distinct r.id rig_id,r.organization_id,r.name rig_name,r.status
  from equipment.provider_rigs r
  left join equipment.provider_rig_services rs on rs.rig_id=r.id and rs.status='active'
  left join commerce.service_types st on st.id=rs.service_type_id
  left join commerce.service_types parent on parent.id=st.parent_id
  where r.status in ('active','seasonal')
    and (st.id is null or st.slug='exterior-cleaning' or parent.slug='exterior-cleaning'
      or st.slug in ('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning','solar-pv-cleaning'))
), caps as (
  select r.rig_id,r.organization_id,r.rig_name,r.status,c.value->>'slug' slug,
    nullif(c.value->>'value_numeric','')::numeric value_numeric,
    case when c.value ? 'value_boolean' and c.value->'value_boolean'<>'null'::jsonb then (c.value->>'value_boolean')::boolean else null end value_boolean
  from cleaning_rigs r
  left join lateral jsonb_array_elements(public.scout_get_rig_effective_capabilities(r.rig_id)) c(value) on true
)
select rig_id,organization_id,rig_name,status,
  max(value_numeric) filter(where slug='max_hose_length_ft') max_hose_length_ft,
  max(value_numeric) filter(where slug='max_liquid_flow_gpm') max_liquid_flow_gpm,
  max(value_numeric) filter(where slug='max_working_pressure_psi') max_working_pressure_psi,
  max(value_numeric) filter(where slug='onboard_water_capacity_gal') onboard_water_capacity_gal,
  max(value_numeric) filter(where slug='pure_water_production_gph') pure_water_production_gph,
  bool_or(coalesce(value_boolean,false)) filter(where slug='pure_water_supply') pure_water_supply,
  bool_or(coalesce(value_boolean,false)) filter(where slug='customer_spigot_refill') customer_spigot_refill,
  bool_or(coalesce(value_boolean,false)) filter(where slug='municipal_fill_refill') municipal_fill_refill,
  bool_or(coalesce(value_boolean,false)) filter(where slug='hydrant_refill') hydrant_refill,
  bool_or(coalesce(value_boolean,false)) filter(where slug='backflow_prevention_capable') backflow_prevention_capable,
  bool_or(coalesce(value_boolean,false)) filter(where slug='bulk_water_delivery_refill') bulk_water_delivery_refill,
  count(*) filter(where slug is not null)::integer effective_capability_count,
  max(value_numeric) filter(where slug='max_water_supply_hose_length_ft') max_water_supply_hose_length_ft
from caps group by rig_id,organization_id,rig_name,status;

create or replace function decisioning.request_cleaning_water_enrichment(
  p_building_source_record_id uuid,p_provider_organization_id uuid default null,p_reason text default 'other',p_force boolean default false
)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_existing uuid;v_types text[]:=array['onsite_plumbed']::text[];v_priority integer:=50;v_radius numeric:=400;
  v_recent boolean:=false;v_recent_lookup boolean:=false;v_verified boolean:=false;v_provider_configured boolean:=false;
  v_hydrant boolean:=false;v_spigot boolean:=false;v_supply_hose numeric;
begin
  if p_reason not in ('plan_job','job_preflight','strong_opportunity','explicit_user_request','rig_water_dependency','comparison_preflight','other') then raise exception 'unsupported water-enrichment reason'; end if;
  if not exists(select 1 from decisioning.v_building_cleaning_hose_baseline b where b.source_record_id=p_building_source_record_id) then raise exception 'building is not available to the cleaning hose model'; end if;
  if p_provider_organization_id is not null and not exists(select 1 from core.organizations o where o.id=p_provider_organization_id) then raise exception 'provider organization not found'; end if;

  select exists(select 1 from decisioning.cleaning_water_sources w where w.building_source_record_id=p_building_source_record_id and (w.provider_organization_id is null or w.provider_organization_id=p_provider_organization_id) and w.source_status in ('verified','authorized') and (w.expires_at is null or w.expires_at>now())) into v_verified;
  select exists(select 1 from decisioning.cleaning_water_sources w where w.building_source_record_id=p_building_source_record_id and (w.provider_organization_id is null or w.provider_organization_id=p_provider_organization_id) and w.source_kind='derived' and coalesce(w.observed_at,w.updated_at)>now()-interval '90 days' and (w.expires_at is null or w.expires_at>now())) into v_recent;
  select exists(select 1 from decisioning.cleaning_water_enrichment_queue q where q.building_source_record_id=p_building_source_record_id and q.provider_organization_id is not distinct from p_provider_organization_id and q.state='complete' and q.completed_at>now()-interval '30 days') into v_recent_lookup;

  if not p_force and (v_verified or v_recent or v_recent_lookup) then
    return jsonb_build_object('ok',true,'queued',false,'reason',case when v_verified then 'usable_water_evidence_already_present' when v_recent then 'recent_water_lookup_with_candidates' else 'recent_water_lookup_completed' end,'negative_evidence_allowed',false);
  end if;

  if p_provider_organization_id is not null then
    select coalesce(bool_or(r.hydrant_refill),false),coalesce(bool_or(r.customer_spigot_refill),false),max(r.max_water_supply_hose_length_ft)
    into v_hydrant,v_spigot,v_supply_hose from decisioning.v_provider_cleaning_rig_preflight_capabilities r where r.organization_id=p_provider_organization_id;
  end if;
  if v_hydrant then v_types:=array_append(v_types,'hydrant'); end if;
  if v_spigot then v_types:=array_append(v_types,'customer_spigot'); end if;
  v_types:=array(select distinct x from unnest(v_types) x order by x);
  v_priority:=case p_reason when 'plan_job' then 90 when 'job_preflight' then 90 when 'explicit_user_request' then 95 when 'rig_water_dependency' then 85 when 'strong_opportunity' then 70 when 'comparison_preflight' then 65 else 50 end;
  v_radius:=least(800::numeric,greatest(200::numeric,coalesce(v_supply_hose*0.3048+120,400)));

  select q.id into v_existing from decisioning.cleaning_water_enrichment_queue q where q.building_source_record_id=p_building_source_record_id and q.provider_organization_id is not distinct from p_provider_organization_id and q.state in ('pending','processing') order by q.created_at desc limit 1;
  if v_existing is not null then
    update decisioning.cleaning_water_enrichment_queue set priority=greatest(priority,v_priority),search_radius_m=greatest(search_radius_m,v_radius),requested_source_types=(select array_agg(distinct t order by t) from unnest(requested_source_types||v_types) t),source_context=source_context||jsonb_build_object('latest_reason',p_reason,'refreshed_at',now()),updated_at=now() where id=v_existing;
    return jsonb_build_object('ok',true,'queued',true,'queue_id',v_existing,'deduplicated',true,'requested_source_types',v_types,'search_radius_m',v_radius,'negative_evidence_allowed',false);
  end if;

  insert into decisioning.cleaning_water_enrichment_queue(building_source_record_id,provider_organization_id,reason,state,priority,search_radius_m,requested_source_types,source_context)
  values(p_building_source_record_id,p_provider_organization_id,p_reason,'pending',v_priority,v_radius,v_types,jsonb_build_object('request_mode','just_in_time','bulk_mapping',false,'requested_at',now())) returning id into v_existing;
  select coalesce((public.internal_get_site_access_provider_state()->>'configured')::boolean,false) into v_provider_configured;
  return jsonb_build_object('ok',true,'queued',true,'queue_id',v_existing,'deduplicated',false,'requested_source_types',v_types,'search_radius_m',v_radius,'provider_configured',v_provider_configured,'dispatch_ready',v_provider_configured,'negative_evidence_allowed',false);
end;$$;

create or replace function public.internal_claim_cleaning_water_jobs(p_limit integer default 2)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_items jsonb;
begin
  if p_limit not between 1 and 20 then raise exception 'limit must be 1-20'; end if;
  if not coalesce((public.internal_get_site_access_provider_state()->>'configured')::boolean,false) then return '[]'::jsonb; end if;
  with picked as (
    select q.id from decisioning.cleaning_water_enrichment_queue q
    where q.state in ('pending','failed') and q.next_attempt_at<=now() and q.attempt_count<6
      and exists(select 1 from decisioning.v_building_cleaning_hose_baseline b where b.source_record_id=q.building_source_record_id and b.geometry is not null)
    order by q.priority desc,q.next_attempt_at,q.created_at for update skip locked limit p_limit
  ), upd as (
    update decisioning.cleaning_water_enrichment_queue q set state='processing',attempt_count=q.attempt_count+1,claimed_at=now(),updated_at=now() from picked p where q.id=p.id returning q.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'queue_id',u.id,'building_source_record_id',u.building_source_record_id,'provider_organization_id',u.provider_organization_id,'reason',u.reason,'priority',u.priority,'search_radius_m',u.search_radius_m,'requested_source_types',u.requested_source_types,'attempt_count',u.attempt_count,
    'bbox',jsonb_build_object(
      'west',extensions.ST_XMin(extensions.Box3D(extensions.ST_Envelope(extensions.ST_Buffer((case when extensions.ST_IsValid(b.geometry) then b.geometry else extensions.ST_MakeValid(b.geometry) end)::extensions.geography,u.search_radius_m)::extensions.geometry))),
      'south',extensions.ST_YMin(extensions.Box3D(extensions.ST_Envelope(extensions.ST_Buffer((case when extensions.ST_IsValid(b.geometry) then b.geometry else extensions.ST_MakeValid(b.geometry) end)::extensions.geography,u.search_radius_m)::extensions.geometry))),
      'east',extensions.ST_XMax(extensions.Box3D(extensions.ST_Envelope(extensions.ST_Buffer((case when extensions.ST_IsValid(b.geometry) then b.geometry else extensions.ST_MakeValid(b.geometry) end)::extensions.geography,u.search_radius_m)::extensions.geometry))),
      'north',extensions.ST_YMax(extensions.Box3D(extensions.ST_Envelope(extensions.ST_Buffer((case when extensions.ST_IsValid(b.geometry) then b.geometry else extensions.ST_MakeValid(b.geometry) end)::extensions.geography,u.search_radius_m)::extensions.geometry)))
    )) order by u.priority desc),'[]'::jsonb) into v_items
  from upd u join decisioning.v_building_cleaning_hose_baseline b on b.source_record_id=u.building_source_record_id;
  return v_items;
end;$$;

create or replace function public.internal_complete_cleaning_water_job(p_queue_id uuid,p_sources jsonb,p_source_timestamp timestamptz default null,p_response_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare q decisioning.cleaning_water_enrichment_queue%rowtype;bgeom extensions.geometry;item jsonb;loc extensions.geometry;v_count integer:=0;v_type text;v_native text;v_provider text;v_distance numeric;
begin
  if p_sources is null or jsonb_typeof(p_sources)<>'array' or jsonb_array_length(p_sources)>250 then raise exception 'sources must be an array of at most 250 items'; end if;
  select * into q from decisioning.cleaning_water_enrichment_queue where id=p_queue_id for update;
  if not found then raise exception 'cleaning water queue item not found'; end if;
  if q.state<>'processing' then raise exception 'cleaning water queue item is not processing'; end if;
  select geometry into bgeom from decisioning.v_building_cleaning_hose_baseline where source_record_id=q.building_source_record_id;
  if bgeom is null then raise exception 'building geometry unavailable'; end if;
  select provider_slug into v_provider from decisioning.site_access_providers where enabled order by provider_slug limit 1;

  delete from decisioning.cleaning_water_sources w where w.building_source_record_id=q.building_source_record_id and w.provider_organization_id is not distinct from q.provider_organization_id and w.source_kind='derived' and coalesce(w.attributes->>'provider_slug','')=coalesce(v_provider,'') and coalesce(w.observed_at,w.updated_at)<coalesce(p_source_timestamp,now())-interval '1 second';

  for item in select value from jsonb_array_elements(p_sources) loop
    v_type:=item->>'source_type';v_native:=nullif(item->>'source_native_id','');
    if v_native is null or v_type not in ('customer_spigot','onsite_plumbed','hydrant','municipal_fill_station','other') then continue; end if;
    begin loc:=extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON((item->'geometry')::text),4326); exception when others then loc:=null; end;
    if loc is null or extensions.ST_IsEmpty(loc) or not extensions.ST_DWithin(loc::extensions.geography,bgeom::extensions.geography,q.search_radius_m) then continue; end if;
    v_distance:=extensions.ST_Distance(loc::extensions.geography,bgeom::extensions.geography)*3.28083989501312;
    insert into decisioning.cleaning_water_sources(building_source_record_id,provider_organization_id,source_type,source_status,source_location,distance_to_building_ft,estimated_flow_gpm,available_volume_gal,permission_required,permission_status,backflow_required,backflow_status,source_kind,source_native_id,confidence,notes,attributes,observed_at,expires_at,updated_at)
    values(q.building_source_record_id,q.provider_organization_id,v_type,'candidate',loc::extensions.geography,round(v_distance::numeric,1),null,null,coalesce((item->>'permission_required')::boolean,true),coalesce(nullif(item->>'permission_status',''),'unknown'),case when item ? 'backflow_required' and item->'backflow_required'<>'null'::jsonb then (item->>'backflow_required')::boolean else null end,coalesce(nullif(item->>'backflow_status',''),'unknown'),'derived',left(v_native,160),least(1::numeric,greatest(0::numeric,coalesce((item->>'confidence')::numeric,0.55))),nullif(item->>'notes',''),coalesce(item->'raw_attributes','{}'::jsonb)||jsonb_build_object('provider_slug',v_provider,'queue_id',q.id,'lookup_reason',q.reason,'just_in_time',true,'negative_evidence_allowed',false,'response_meta',coalesce(p_response_meta,'{}'::jsonb)),coalesce(p_source_timestamp,now()),now()+interval '90 days',now())
    on conflict(building_source_record_id,coalesce(provider_organization_id,'00000000-0000-0000-0000-000000000000'::uuid),source_kind,source_native_id) where source_native_id is not null
    do update set source_type=excluded.source_type,source_status='candidate',source_location=excluded.source_location,distance_to_building_ft=excluded.distance_to_building_ft,permission_required=excluded.permission_required,permission_status=excluded.permission_status,backflow_required=excluded.backflow_required,backflow_status=excluded.backflow_status,confidence=excluded.confidence,notes=excluded.notes,attributes=excluded.attributes,observed_at=excluded.observed_at,expires_at=excluded.expires_at,updated_at=now();
    v_count:=v_count+1;
  end loop;
  update decisioning.cleaning_water_enrichment_queue set state='complete',completed_at=now(),last_error=null,source_context=source_context||jsonb_build_object('source_count',v_count,'source_timestamp',p_source_timestamp,'provider_slug',v_provider),updated_at=now() where id=q.id;
  return jsonb_build_object('ok',true,'queue_id',q.id,'building_source_record_id',q.building_source_record_id,'source_count',v_count,'negative_evidence_allowed',false);
end;$$;

create or replace function public.internal_fail_cleaning_water_job(p_queue_id uuid,p_error text,p_retry_after_seconds integer default null,p_terminal boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare q decisioning.cleaning_water_enrichment_queue%rowtype;v_delay integer;v_state text;
begin
  select * into q from decisioning.cleaning_water_enrichment_queue where id=p_queue_id for update;
  if not found then raise exception 'cleaning water queue item not found'; end if;
  v_delay:=least(21600,greatest(60,coalesce(p_retry_after_seconds,(power(2,least(q.attempt_count,6))*300)::integer)));
  v_state:=case when p_terminal or q.attempt_count>=6 then 'failed' else 'pending' end;
  update decisioning.cleaning_water_enrichment_queue set state=v_state,claimed_at=null,next_attempt_at=case when v_state='pending' then now()+make_interval(secs=>v_delay) else next_attempt_at end,last_error=left(coalesce(p_error,'unspecified water enrichment failure'),600),updated_at=now() where id=q.id;
  return jsonb_build_object('ok',false,'queue_id',q.id,'state',v_state,'retry_after_seconds',case when v_state='pending' then v_delay else null end);
end;$$;

create or replace view decisioning.v_cleaning_scenario_water_routes as
select s.id scenario_id,s.building_source_record_id,s.provider_organization_id scenario_provider_organization_id,s.scenario_name,s.facade_label,s.access_class,s.access_status,s.source_kind scenario_source_kind,s.confidence scenario_confidence,s.staging_point,s.ground_run_ft,s.recommended_hose_ft cleaning_hose_ft,
  w.id water_source_id,w.provider_organization_id water_provider_organization_id,w.source_type water_source_type,w.source_status water_source_status,w.source_location,w.permission_required,w.permission_status,w.backflow_required,w.backflow_status,w.confidence water_source_confidence,
  round((extensions.ST_Distance(w.source_location,s.staging_point)*3.28083989501312)::numeric,1) water_supply_run_ft,
  round((s.recommended_hose_ft+extensions.ST_Distance(w.source_location,s.staging_point)*3.28083989501312)::numeric,1) combined_separate_hose_inventory_ft,
  case when w.permission_required and w.permission_status='denied' then 'permission_denied' when w.source_status in ('verified','authorized') and (not w.permission_required or w.permission_status in ('authorized','not_required')) then 'source_ready' when w.source_status in ('candidate','observed') then 'candidate_unverified' else 'source_unresolved' end source_route_status
from decisioning.v_cleaning_hose_scenarios s join decisioning.cleaning_water_sources w on w.building_source_record_id=s.building_source_record_id and w.source_status<>'unavailable' and w.source_location is not null
where s.estimate_status='complete' and s.staging_point is not null;

-- Provider-aware preflight. Water location constrains plausible staging but the two hose lines remain separate.
create or replace function decisioning.get_cleaning_preflight(p_building_source_record_id uuid,p_provider_organization_id uuid)
returns jsonb language sql stable set search_path to '' as $$
with site as (
  select * from decisioning.v_building_cleaning_preflight_summary where source_record_id=p_building_source_record_id
), water as (
  select w.*,row_number() over(order by case w.source_status when 'authorized' then 5 when 'verified' then 4 when 'observed' then 3 when 'candidate' then 2 when 'unavailable' then 1 else 0 end desc,case when w.permission_status in ('authorized','not_required') then 2 when w.permission_status='denied' then 0 else 1 end desc,w.confidence desc,w.distance_to_building_ft nulls last,w.id) rn
  from decisioning.cleaning_water_sources w where w.building_source_record_id=p_building_source_record_id and (w.provider_organization_id is null or w.provider_organization_id=p_provider_organization_id) and (w.expires_at is null or w.expires_at>now())
), best_water as (select * from water where rn=1),
rig_base as (select r.* from decisioning.v_provider_cleaning_rig_preflight_capabilities r where r.organization_id=p_provider_organization_id),
route_eval as (
  select r.rig_id,wr.scenario_id,wr.scenario_name,wr.facade_label,wr.cleaning_hose_ft,wr.water_source_id,wr.water_source_type,wr.water_source_status,wr.water_supply_run_ft,wr.combined_separate_hose_inventory_ft,wr.permission_required,wr.permission_status,wr.backflow_required,wr.backflow_status,wr.water_source_confidence,wr.scenario_confidence,wr.source_route_status,
    case when wr.water_source_type in ('customer_spigot','onsite_plumbed') then coalesce(r.customer_spigot_refill,false) when wr.water_source_type='hydrant' then coalesce(r.hydrant_refill,false) when wr.water_source_type='municipal_fill_station' then coalesce(r.municipal_fill_refill,false) when wr.water_source_type='bulk_delivery' then coalesce(r.bulk_water_delivery_refill,false) else true end source_method_compatible,
    case when r.max_water_supply_hose_length_ft is null then 'supply_hose_unknown' when wr.water_supply_run_ft<=r.max_water_supply_hose_length_ft then 'supply_hose_fit' else 'supply_hose_too_short' end supply_hose_fit_status,
    case when wr.backflow_required is true and not coalesce(r.backflow_prevention_capable,false) then false else true end backflow_compatible,
    case when wr.water_source_status in ('verified','authorized') and (not wr.permission_required or wr.permission_status in ('authorized','not_required')) and (wr.backflow_required is not true or coalesce(r.backflow_prevention_capable,false)) then true else false end source_operationally_ready
  from rig_base r join decisioning.v_cleaning_scenario_water_routes wr on wr.building_source_record_id=p_building_source_record_id and (wr.water_provider_organization_id is null or wr.water_provider_organization_id=p_provider_organization_id) and (wr.scenario_provider_organization_id is null or wr.scenario_provider_organization_id=p_provider_organization_id)
), route_agg as (
  select rig_id,
    min(cleaning_hose_ft) filter(where source_method_compatible and backflow_compatible and max_supply_ok) provisional_water_constrained_lower_bound_hose_ft,
    min(cleaning_hose_ft) filter(where source_method_compatible and backflow_compatible and source_operationally_ready and max_supply_ok) verified_water_constrained_lower_bound_hose_ft
  from (select re.*,case when rb.max_water_supply_hose_length_ft is null then false else re.water_supply_run_ft<=rb.max_water_supply_hose_length_ft end max_supply_ok from route_eval re join rig_base rb using(rig_id)) x group by rig_id
), best_route as (
  select * from (select re.*,row_number() over(partition by re.rig_id order by re.source_method_compatible desc,re.source_operationally_ready desc,case re.supply_hose_fit_status when 'supply_hose_fit' then 3 when 'supply_hose_unknown' then 2 else 1 end desc,re.cleaning_hose_ft,re.water_supply_run_ft,re.water_source_confidence desc,re.scenario_confidence desc,re.scenario_id) rn from route_eval re) x where rn=1
), rigs as (
  select r.*,a.provisional_water_constrained_lower_bound_hose_ft,a.verified_water_constrained_lower_bound_hose_ft,
    coalesce(a.verified_water_constrained_lower_bound_hose_ft,a.provisional_water_constrained_lower_bound_hose_ft,s.mapped_access_lower_bound_hose_ft) effective_lower_bound_hose_ft,
    case when a.verified_water_constrained_lower_bound_hose_ft is not null then 'verified_water_constrained' when a.provisional_water_constrained_lower_bound_hose_ft is not null then 'candidate_water_constrained' when s.mapped_access_lower_bound_hose_ft is not null then 'staging_only' else 'unknown' end effective_lower_bound_basis,
    br.scenario_id best_water_route_scenario_id,br.scenario_name best_water_route_scenario_name,br.facade_label best_water_route_staging_label,br.water_source_id best_water_route_source_id,br.water_source_type best_water_route_source_type,br.water_source_status best_water_route_source_status,br.cleaning_hose_ft best_water_route_cleaning_hose_ft,br.water_supply_run_ft best_water_route_supply_hose_ft,br.combined_separate_hose_inventory_ft best_water_route_combined_hose_inventory_ft,br.supply_hose_fit_status,br.source_method_compatible,br.source_operationally_ready,
    case when coalesce(a.verified_water_constrained_lower_bound_hose_ft,a.provisional_water_constrained_lower_bound_hose_ft,s.mapped_access_lower_bound_hose_ft) is null then 'site_hose_unknown' when r.max_hose_length_ft is null then 'rig_hose_unknown' when r.max_hose_length_ft>=coalesce(a.verified_water_constrained_lower_bound_hose_ft,a.provisional_water_constrained_lower_bound_hose_ft,s.mapped_access_lower_bound_hose_ft) then case when s.mapped_access_typical_hose_ft is not null and r.max_hose_length_ft>=s.mapped_access_typical_hose_ft then 'likely_fit_typical' else 'staging_dependent_fit' end else 'below_mapped_lower_bound' end hose_fit_status,
    case when br.water_source_id is not null and br.source_operationally_ready and br.source_method_compatible and br.supply_hose_fit_status='supply_hose_fit' then 'verified_source_rig_compatible' when br.water_source_id is not null and br.source_method_compatible and br.supply_hose_fit_status='supply_hose_fit' then 'candidate_source_route_plausible_verify' when br.water_source_id is not null and br.supply_hose_fit_status='supply_hose_too_short' then 'water_source_outside_supply_hose_reach' when coalesce(r.onboard_water_capacity_gal,0)>0 then 'onboard_capacity_available_demand_unknown' when coalesce(r.customer_spigot_refill,false) or coalesce(r.hydrant_refill,false) or coalesce(r.municipal_fill_refill,false) or coalesce(r.bulk_water_delivery_refill,false) then 'refill_strategy_available_source_verify' else 'water_plan_missing' end water_fit_status
  from rig_base r cross join site s left join route_agg a on a.rig_id=r.rig_id left join best_route br on br.rig_id=r.rig_id
), ranked_rigs as (
  select r.*,row_number() over(order by case r.hose_fit_status when 'likely_fit_typical' then 4 when 'staging_dependent_fit' then 3 when 'rig_hose_unknown' then 2 when 'site_hose_unknown' then 1 else 0 end desc,case r.water_fit_status when 'verified_source_rig_compatible' then 5 when 'candidate_source_route_plausible_verify' then 4 when 'onboard_capacity_available_demand_unknown' then 3 when 'refill_strategy_available_source_verify' then 2 else 0 end desc,r.max_hose_length_ft desc nulls last,r.rig_name) rn from rigs r
), best_rig as (select * from ranked_rigs where rn=1)
select jsonb_build_object(
  'building',to_jsonb(s),
  'water_source',case when bw.id is null then jsonb_build_object('readiness','unknown_verify','note','Water source is unknown; request just-in-time water enrichment when this job/opportunity is operationally worth preflighting.') else jsonb_build_object('id',bw.id,'type',bw.source_type,'status',bw.source_status,'distance_to_building_ft',bw.distance_to_building_ft,'estimated_flow_gpm',bw.estimated_flow_gpm,'available_volume_gal',bw.available_volume_gal,'permission_required',bw.permission_required,'permission_status',bw.permission_status,'backflow_required',bw.backflow_required,'backflow_status',bw.backflow_status,'confidence',bw.confidence,'location_known',bw.source_location is not null) end,
  'rig_count',(select count(*) from ranked_rigs),'best_rig',(select to_jsonb(r)-'rn' from ranked_rigs r where rn=1),'rig_options',coalesce((select jsonb_agg(to_jsonb(r)-'rn' order by rn) from ranked_rigs r),'[]'::jsonb),
  'water_hose_math',case when br.rig_id is null then jsonb_build_object('staging_only_lower_bound_hose_ft',s.mapped_access_lower_bound_hose_ft,'status','provider_rig_unavailable') else jsonb_build_object('staging_only_lower_bound_hose_ft',s.mapped_access_lower_bound_hose_ft,'water_constrained_lower_bound_hose_ft',br.effective_lower_bound_hose_ft,'lower_bound_basis',br.effective_lower_bound_basis,'cleaning_hose_available_ft',br.max_hose_length_ft,'water_supply_hose_available_ft',br.max_water_supply_hose_length_ft,'selected_staging_scenario_id',br.best_water_route_scenario_id,'selected_staging_label',br.best_water_route_staging_label,'selected_water_source_id',br.best_water_route_source_id,'selected_water_source_type',br.best_water_route_source_type,'cleaning_hose_required_ft',br.best_water_route_cleaning_hose_ft,'water_supply_hose_required_ft',br.best_water_route_supply_hose_ft,'combined_separate_hose_inventory_ft',br.best_water_route_combined_hose_inventory_ft,'supply_hose_fit_status',br.supply_hose_fit_status,'note','Cleaning hose and source-to-rig supply hose are separate lines. Scout constrains the cleaning-hose lower bound to staging scenarios reachable from the mapped water point; it does not add the two runs and pretend they are one hose.') end,
  'decision_rule','Mapped staging and mapped water are hypotheses until site/permission evidence verifies them. Water source location constrains plausible staging; cleaning hose and water-supply hose remain distinct operational requirements.'
) from site s left join best_water bw on true left join best_rig br on true;
$$;

create or replace function decisioning.resolve_job_cleaning_building_source_record_id(p_job_id uuid)
returns uuid language plpgsql stable set search_path to '' as $$
declare j decisioning.jobs%rowtype;v_id uuid;v_text text;
begin
  select * into j from decisioning.jobs where id=p_job_id;if not found then return null;end if;
  v_text:=coalesce(nullif(j.target->>'building_source_record_id',''),nullif(j.source_context->>'building_source_record_id',''));
  if v_text is not null then begin v_id:=v_text::uuid;exception when invalid_text_representation then v_id:=null;end;if v_id is not null and exists(select 1 from decisioning.v_building_cleaning_hose_baseline b where b.source_record_id=v_id) then return v_id;end if;end if;
  select oti.canonical_asset_id into v_id from scout.opportunity_target_identities oti where oti.candidate_key=j.source_context->>'candidate_key' and oti.target_class='building' and oti.canonical_namespace='decisioning.building_candidates' and oti.resolution_status='canonical_asset' and oti.canonical_asset_id is not null limit 1;
  if v_id is not null and exists(select 1 from decisioning.v_building_cleaning_hose_baseline b where b.source_record_id=v_id) then return v_id;end if;return null;
end;$$;

create or replace function decisioning.enqueue_cleaning_water_from_preflight()
returns trigger language plpgsql security definer set search_path to '' as $$
declare j decisioning.jobs%rowtype;v_service_slug text;v_parent_slug text;v_building uuid;v_request jsonb;v_preflight jsonb;v_hose_status text;v_water_status text;v_lower numeric;v_available numeric;v_status text;v_severity text;v_title text;v_message text;v_action text;
begin
  select * into j from decisioning.jobs where id=new.job_id;if not found then return new;end if;
  select st.slug,p.slug into v_service_slug,v_parent_slug from commerce.service_types st left join commerce.service_types p on p.id=st.parent_id where st.id=j.service_type_id;
  if coalesce(v_service_slug,'')<>'exterior-cleaning' and coalesce(v_parent_slug,'')<>'exterior-cleaning' and coalesce(v_service_slug,'') not in ('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning','solar-pv-cleaning') then return new;end if;
  v_building:=decisioning.resolve_job_cleaning_building_source_record_id(j.id);if v_building is null then return new;end if;
  begin v_request:=decisioning.request_cleaning_water_enrichment(v_building,j.organization_id,'job_preflight',false);v_preflight:=decisioning.get_cleaning_preflight(v_building,j.organization_id);
  exception when others then
    insert into decisioning.preflight_checks(run_id,check_type,severity,status,subject_type,subject_id,title,message,recommended_action,attributes)
    values(new.id,'cleaning_water_access','warning','unknown','building',v_building,'Cleaning water preflight unavailable','Scout could not prepare the water/access enrichment for this run. The rest of the job preflight remains valid.','Verify water access manually or retry the cleaning preflight later.',jsonb_build_object('diagnostic_code','cleaning_water_enrichment_unavailable','sqlstate',sqlstate,'epistemic_status','unknown'));return new;
  end;
  v_hose_status:=v_preflight#>>'{best_rig,hose_fit_status}';v_water_status:=v_preflight#>>'{best_rig,water_fit_status}';
  begin v_lower:=(v_preflight#>>'{water_hose_math,water_constrained_lower_bound_hose_ft}')::numeric;exception when others then v_lower:=null;end;
  begin v_available:=(v_preflight#>>'{water_hose_math,cleaning_hose_available_ft}')::numeric;exception when others then v_available:=null;end;
  if v_hose_status='below_mapped_lower_bound' then v_status:='action_required';v_severity:='warning';v_title:='Cleaning hose may be too short for mapped access';v_message:='The configured cleaning hose is below Scout''s current lower-bound access estimate. Water-source discovery may further constrain which staging points are practical.';v_action:='Verify staging and water access; add hose or use a closer validated staging point before treating the job as ready.';
  elsif v_water_status='verified_source_rig_compatible' and v_hose_status in ('likely_fit_typical','staging_dependent_fit') then v_status:='pass';v_severity:='info';v_title:='Cleaning water/access route has a usable current hypothesis';v_message:='Scout has a water-aware staging hypothesis compatible with the configured rig. Site permission and current physical conditions still require operator confirmation.';v_action:=null;
  elsif v_water_status='candidate_source_route_plausible_verify' then v_status:='unknown';v_severity:='warning';v_title:='Mapped water candidate needs verification';v_message:='Scout found a mapped water point that can constrain staging/hose planning, but its permission, flow, connection, or backflow status is not yet verified.';v_action:='Verify the candidate water source before relying on it for the job.';
  else v_status:='unknown';v_severity:='warning';v_title:='Water access not yet established';v_message:='This cleaning job has no verified water source in Scout. A just-in-time water lookup has been requested when the configured provider supports it.';v_action:='Confirm customer water, onboard capacity/refill strategy, or another authorized source before final job planning.';end if;
  insert into decisioning.preflight_checks(run_id,check_type,severity,status,subject_type,subject_id,title,message,recommended_action,attributes)
  values(new.id,'cleaning_water_access',v_severity,v_status,'building',v_building,v_title,v_message,v_action,jsonb_build_object('building_source_record_id',v_building,'water_enrichment_request',v_request,'hose_fit_status',v_hose_status,'water_fit_status',v_water_status,'effective_lower_bound_hose_ft',v_lower,'cleaning_hose_available_ft',v_available,'water_hose_math',v_preflight->'water_hose_math','epistemic_status','planning_hypothesis_not_site_authorization'));
  return new;
end;$$;

drop trigger if exists preflight_enqueue_cleaning_water on decisioning.preflight_runs;
create trigger preflight_enqueue_cleaning_water after insert on decisioning.preflight_runs for each row execute function decisioning.enqueue_cleaning_water_from_preflight();

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-cleaning-water-access',true,true,now())
on conflict(slug) do update set enabled=true,allow_dispatch=true,updated_at=now();

select cron.unschedule(jobid) from cron.job where jobname='collect-cleaning-water-access-5m';
select cron.schedule(
  'collect-cleaning-water-access-5m','3-59/5 * * * *',
  $cmd$select case when coalesce((public.internal_get_site_access_provider_state()->>'configured')::boolean,false)
    then ingest.invoke_edge_collector('collect-cleaning-water-access',jsonb_build_object('limit',2))
    else jsonb_build_object('skipped',true,'reason','production_provider_not_configured') end;$cmd$
);
