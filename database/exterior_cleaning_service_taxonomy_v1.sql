-- Scout by Cadastory
-- Exterior-cleaning service taxonomy + workflow model.
-- Consolidated source-of-truth migration for the production changes deployed 2026-09-07.

-- Commercial service taxonomy -------------------------------------------------
do $$
declare v_parent uuid;
begin
  select id into v_parent from commerce.service_types where slug='exterior-cleaning';
  if v_parent is null then raise exception 'exterior-cleaning parent service missing'; end if;

  insert into commerce.service_types(slug,name,parent_id,description,active)
  values
    ('building-envelope-cleaning','Building Envelope Cleaning',v_parent,'Commercial exterior building-envelope washing/cleaning. Pressure washing, soft washing and rinse techniques are execution workflows, not separate customer-facing services.',true),
    ('pure-water-window-cleaning','Pure-Water Exterior Glass Cleaning',v_parent,'Exterior glass/window cleaning using service-quality purified water such as RO/DI, with workflow-specific equipment and water-quality requirements.',true),
    ('exterior-biocide-treatment','Exterior Biocide Treatment',v_parent,'Exterior treatment using a labeled biocide, quat or comparable product where the product label, substrate, equipment, environmental conditions and operator credentials permit.',true),
    ('masonry-restoration-cleaning','Masonry / Limestone Restoration Cleaning',v_parent,'Specialty cleaning/restoration of masonry, limestone, stone, brick or related mineral facade materials using material-specific products and controlled application/rinse procedures.',true)
  on conflict(slug) do update set parent_id=excluded.parent_id,name=excluded.name,description=excluded.description,active=true;
end $$;

insert into equipment.capability_types(slug,name,value_type,unit_family,description,attributes)
values('pure_water_supply','Service-quality purified water supply','boolean',null,'Rig/system can provide service-quality purified water for a cleaning workflow, whether generated on site by RO/DI or supplied from a documented equivalent source.',jsonb_build_object('source','Scout cleaning workflow taxonomy','version',1))
on conflict(slug) do update set name=excluded.name,value_type=excluded.value_type,description=excluded.description,attributes=equipment.capability_types.attributes||excluded.attributes;

-- Keep the catalog vocabulary aligned with operator onboarding.
alter table cleaning.products drop constraint if exists products_product_kind_check;
alter table cleaning.products add constraint products_product_kind_check
  check(product_kind = any(array['cleaner','surfactant','disinfectant','solvent','descaler','rinse_aid','window_cleaner','biocide','restoration_chemical','process_water','other']::text[]));

-- Execution workflow taxonomy -------------------------------------------------
create table if not exists cleaning.service_workflows(
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check(slug ~ '^[a-z][a-z0-9_.-]{1,119}$'),
  name text not null check(length(btrim(name)) between 2 and 160),
  workflow_kind text not null check(workflow_kind in ('mechanical_wash','low_pressure_chemical','pure_water','treatment','restoration','rinse','other')),
  description text,
  active boolean not null default true,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists cleaning.service_workflow_applicability(
  id uuid primary key default gen_random_uuid(),
  service_type_id uuid not null references commerce.service_types(id) on delete cascade,
  workflow_id uuid not null references cleaning.service_workflows(id) on delete cascade,
  workflow_role text not null default 'primary' check(workflow_role in ('primary','supporting','optional')),
  default_for_service boolean not null default false,
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(service_type_id,workflow_id)
);

create table if not exists cleaning.workflow_capability_requirements(
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references cleaning.service_workflows(id) on delete cascade,
  capability_type_id uuid not null references equipment.capability_types(id) on delete cascade,
  requirement_level text not null default 'required' check(requirement_level in ('required','preferred','disqualifying')),
  comparator text not null default 'equals' check(comparator in ('equals','not_equals','at_least','at_most','contains','exists')),
  value_boolean boolean,
  value_numeric numeric,
  value_text text,
  value_json jsonb,
  unit text,
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check(num_nonnulls(value_boolean,value_numeric,value_text,value_json)<=1),
  unique(workflow_id,capability_type_id,requirement_level,comparator)
);

create table if not exists cleaning.workflow_product_requirements(
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references cleaning.service_workflows(id) on delete cascade,
  product_kind text not null check(product_kind ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  application_role text check(application_role is null or application_role ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  requirement_level text not null default 'required' check(requirement_level in ('required','preferred')),
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(workflow_id,product_kind,application_role)
);

create table if not exists cleaning.workflow_route_requirements(
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references cleaning.service_workflows(id) on delete cascade,
  route_kind text not null check(route_kind in ('cleaning_delivery','window_wash','rinse','chemical_transfer','mixed_service','other')),
  requirement_level text not null default 'preferred' check(requirement_level in ('required','preferred')),
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(workflow_id,route_kind)
);

alter table cleaning.service_workflows enable row level security;
alter table cleaning.service_workflow_applicability enable row level security;
alter table cleaning.workflow_capability_requirements enable row level security;
alter table cleaning.workflow_product_requirements enable row level security;
alter table cleaning.workflow_route_requirements enable row level security;

revoke all on cleaning.service_workflows,cleaning.service_workflow_applicability,cleaning.workflow_capability_requirements,cleaning.workflow_product_requirements,cleaning.workflow_route_requirements from anon,authenticated;
grant select,insert,update,delete on cleaning.service_workflows,cleaning.service_workflow_applicability,cleaning.workflow_capability_requirements,cleaning.workflow_product_requirements,cleaning.workflow_route_requirements to service_role;

drop policy if exists service_workflows_service_role on cleaning.service_workflows;
create policy service_workflows_service_role on cleaning.service_workflows for all to service_role using(true) with check(true);
drop policy if exists service_workflow_applicability_service_role on cleaning.service_workflow_applicability;
create policy service_workflow_applicability_service_role on cleaning.service_workflow_applicability for all to service_role using(true) with check(true);
drop policy if exists workflow_capability_requirements_service_role on cleaning.workflow_capability_requirements;
create policy workflow_capability_requirements_service_role on cleaning.workflow_capability_requirements for all to service_role using(true) with check(true);
drop policy if exists workflow_product_requirements_service_role on cleaning.workflow_product_requirements;
create policy workflow_product_requirements_service_role on cleaning.workflow_product_requirements for all to service_role using(true) with check(true);
drop policy if exists workflow_route_requirements_service_role on cleaning.workflow_route_requirements;
create policy workflow_route_requirements_service_role on cleaning.workflow_route_requirements for all to service_role using(true) with check(true);

insert into cleaning.service_workflows(slug,name,workflow_kind,description,attributes)
values
 ('pressure-wash','Pressure Wash','mechanical_wash','Higher-pressure exterior cleaning workflow. Applicability depends on substrate, pressure limits, equipment path and job-specific controls.',jsonb_build_object('version',1,'customer_facing_service',false)),
 ('soft-wash','Soft Wash','low_pressure_chemical','Low-pressure exterior cleaning workflow using a compatible cleaning chemistry and delivery path where supported.',jsonb_build_object('version',1,'customer_facing_service',false)),
 ('pure-water-rodi','RO/DI Pure-Water Cleaning','pure_water','Spot-reducing exterior glass/window cleaning workflow using service-quality purified water such as RO/DI.',jsonb_build_object('version',1,'customer_facing_service',false)),
 ('biocide-application','Biocide / Quat Application','treatment','Exterior treatment workflow using a labeled biocide, quat or comparable treatment product. Product label and jurisdictional requirements remain controlling.',jsonb_build_object('version',1,'customer_facing_service',false)),
 ('masonry-restoration-chemical','Specialty Masonry Restoration Chemistry','restoration','Material-specific restoration/cleaning workflow for limestone, masonry, stone, brick or related mineral surfaces using an identified compatible product and controlled process.',jsonb_build_object('version',1,'customer_facing_service',false)),
 ('controlled-rinse','Controlled Rinse','rinse','Supporting rinse workflow used after compatible cleaning/treatment processes when required by the product, substrate or procedure.',jsonb_build_object('version',1,'customer_facing_service',false))
on conflict(slug) do update set name=excluded.name,workflow_kind=excluded.workflow_kind,description=excluded.description,active=true,attributes=cleaning.service_workflows.attributes||excluded.attributes,updated_at=now();

insert into cleaning.service_workflow_applicability(service_type_id,workflow_id,workflow_role,default_for_service,notes)
select st.id,w.id,x.role,x.is_default,x.notes
from (values
 ('building-envelope-cleaning','pressure-wash','primary'::text,false,'One valid primary execution path for building-envelope cleaning; substrate and job conditions control applicability.'),
 ('building-envelope-cleaning','soft-wash','primary',false,'One valid primary execution path for building-envelope cleaning; chemistry and substrate compatibility remain evidence-gated.'),
 ('building-envelope-cleaning','controlled-rinse','supporting',false,'Supporting rinse workflow when required.'),
 ('pure-water-window-cleaning','pure-water-rodi','primary',true,'Primary workflow for the pure-water exterior-glass service.'),
 ('exterior-biocide-treatment','biocide-application','primary',true,'Primary workflow for exterior biocide treatment.'),
 ('exterior-biocide-treatment','controlled-rinse','optional',false,'Some products/procedures may require rinse; product label controls.'),
 ('masonry-restoration-cleaning','masonry-restoration-chemical','primary',true,'Primary specialty restoration workflow.'),
 ('masonry-restoration-cleaning','controlled-rinse','supporting',false,'Controlled rinse is commonly part of a restoration procedure when required by the product/procedure.')
) x(service_slug,workflow_slug,role,is_default,notes)
join commerce.service_types st on st.slug=x.service_slug
join cleaning.service_workflows w on w.slug=x.workflow_slug
on conflict(service_type_id,workflow_id) do update set workflow_role=excluded.workflow_role,default_for_service=excluded.default_for_service,notes=excluded.notes;

insert into cleaning.workflow_capability_requirements(workflow_id,capability_type_id,requirement_level,comparator,value_boolean,notes)
select w.id,c.id,'required','equals',true,x.notes
from (values
 ('pressure-wash','pressure_wash_delivery','Rig must support pressure-wash liquid delivery.'),
 ('soft-wash','softwash_delivery','Rig must support soft-wash/low-pressure chemistry delivery.'),
 ('pure-water-rodi','pure_water_supply','Rig/system must provide service-quality purified water.'),
 ('pure-water-rodi','liquid_delivery','Rig/system must support liquid delivery to the service surface.'),
 ('biocide-application','liquid_delivery','Rig/system must support controlled liquid application.'),
 ('masonry-restoration-chemical','liquid_delivery','Rig/system must support controlled liquid application.'),
 ('controlled-rinse','liquid_delivery','Rig/system must support liquid delivery for rinse.')
) x(workflow_slug,capability_slug,notes)
join cleaning.service_workflows w on w.slug=x.workflow_slug
join equipment.capability_types c on c.slug=x.capability_slug
on conflict(workflow_id,capability_type_id,requirement_level,comparator) do update set value_boolean=excluded.value_boolean,notes=excluded.notes;

insert into cleaning.workflow_product_requirements(workflow_id,product_kind,application_role,requirement_level,notes)
select w.id,x.product_kind,x.application_role,x.level,x.notes
from (values
 ('biocide-application','biocide','biocide','required','An identified operator product declared as a biocide is required before Scout can treat this workflow as configured.'),
 ('masonry-restoration-chemical','restoration_chemical','restoration','required','An identified operator restoration chemical is required before Scout can treat this workflow as configured.'),
 ('soft-wash','cleaner','cleaner','preferred','A compatible cleaner is normally relevant to this workflow; exact chemistry is operator/product specific.'),
 ('soft-wash','surfactant','surfactant','preferred','A surfactant may be part of this workflow but is not universally required.')
) x(workflow_slug,product_kind,application_role,level,notes)
join cleaning.service_workflows w on w.slug=x.workflow_slug
on conflict(workflow_id,product_kind,application_role) do update set requirement_level=excluded.requirement_level,notes=excluded.notes;

insert into cleaning.workflow_route_requirements(workflow_id,route_kind,requirement_level,notes)
select w.id,x.route_kind,x.level,x.notes
from (values
 ('pressure-wash','cleaning_delivery','preferred','Prefer an operator-mapped cleaning-delivery fluid route.'),
 ('soft-wash','cleaning_delivery','preferred','Prefer an operator-mapped cleaning-delivery fluid route.'),
 ('pure-water-rodi','window_wash','preferred','Prefer an operator-mapped window-wash route; another mapped delivery route may still be valid if explicitly documented.'),
 ('biocide-application','cleaning_delivery','preferred','Prefer an operator-mapped treatment/cleaning delivery route.'),
 ('masonry-restoration-chemical','cleaning_delivery','preferred','Prefer an operator-mapped restoration delivery route.'),
 ('controlled-rinse','rinse','preferred','Prefer an operator-mapped rinse route.')
) x(workflow_slug,route_kind,level,notes)
join cleaning.service_workflows w on w.slug=x.workflow_slug
on conflict(workflow_id,route_kind) do update set requirement_level=excluded.requirement_level,notes=excluded.notes;

-- General liquid-delivery capability inherited from exterior-cleaning.
insert into commerce.service_capability_requirements(service_type_id,delivery_method_id,capability_type_id,requirement_level,comparator,value_boolean,value_numeric,value_text,value_json,unit,notes,attributes)
select child.id,parent_req.delivery_method_id,parent_req.capability_type_id,parent_req.requirement_level,parent_req.comparator,parent_req.value_boolean,parent_req.value_numeric,parent_req.value_text,parent_req.value_json,parent_req.unit,
       'Inherited from exterior-cleaning: '||coalesce(parent_req.notes,''),parent_req.attributes||jsonb_build_object('taxonomy_inherited_from','exterior-cleaning')
from commerce.service_types child
join commerce.service_types parent on parent.slug='exterior-cleaning' and child.parent_id=parent.id
join commerce.service_capability_requirements parent_req on parent_req.service_type_id=parent.id and parent_req.requirement_level='required'
where child.slug in ('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning')
and not exists(select 1 from commerce.service_capability_requirements x where x.service_type_id=child.id and x.delivery_method_id is not distinct from parent_req.delivery_method_id and x.capability_type_id=parent_req.capability_type_id and x.requirement_level=parent_req.requirement_level and x.comparator=parent_req.comparator);

-- Pure-water-specific capability is workflow-authoritative; remove any duplicate service-level copy.
delete from commerce.service_capability_requirements r
using commerce.service_types st,equipment.capability_types ct
where r.service_type_id=st.id and r.capability_type_id=ct.id
  and st.slug='pure-water-window-cleaning' and ct.slug='pure_water_supply'
  and r.attributes->>'source'='Scout cleaning workflow taxonomy';

-- Child services inherit the same drone credential gates as their umbrella parent.
insert into commerce.service_credential_requirements(service_type_id,delivery_method_id,credential_type_id,requirement_kind,jurisdiction_code,condition,notes)
select child.id,r.delivery_method_id,r.credential_type_id,r.requirement_kind,r.jurisdiction_code,r.condition,
       'Inherited from exterior-cleaning taxonomy parent. '||coalesce(r.notes,'')
from commerce.service_types child
join commerce.service_types parent on parent.slug='exterior-cleaning' and child.parent_id=parent.id
join commerce.service_credential_requirements r on r.service_type_id=parent.id
where child.slug in ('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning')
on conflict(service_type_id,delivery_method_id,credential_type_id,jurisdiction_code) do update set requirement_kind=excluded.requirement_kind,condition=excluded.condition,notes=excluded.notes;

-- Aliases --------------------------------------------------------------------
insert into knowledge.service_scope_aliases(alias_key,service_type_id,alias_kind,match_strength,notes)
select x.alias_key,st.id,x.alias_kind,x.strength,x.notes
from (values
 ('building-envelope-cleaning','building-envelope-cleaning','canonical'::text,1.00::numeric,'Canonical Scout service slug.'),
 ('full_envelope_cleaning','building-envelope-cleaning','synonym',0.98,'Commercial full-envelope exterior cleaning.'),
 ('facade_cleaning','building-envelope-cleaning','synonym',0.95,'Facade/building-envelope cleaning synonym.'),
 ('building_washing','building-envelope-cleaning','synonym',0.92,'Building-envelope washing synonym.'),
 ('pure-water-window-cleaning','pure-water-window-cleaning','canonical',1.00,'Canonical Scout service slug.'),
 ('pure_water_window_cleaning','pure-water-window-cleaning','synonym',0.99,'Pure-water exterior glass cleaning.'),
 ('ro_di_window_cleaning','pure-water-window-cleaning','synonym',0.99,'RO/DI exterior glass cleaning.'),
 ('glass_only_cleaning','pure-water-window-cleaning','synonym',0.94,'Commercial glass-only cleaning context.'),
 ('exterior-biocide-treatment','exterior-biocide-treatment','canonical',1.00,'Canonical Scout service slug.'),
 ('biocide_application','exterior-biocide-treatment','synonym',0.98,'Exterior biocide treatment/application.'),
 ('quat_application','exterior-biocide-treatment','synonym',0.97,'Quat/biocide exterior treatment context.'),
 ('masonry-restoration-cleaning','masonry-restoration-cleaning','canonical',1.00,'Canonical Scout service slug.'),
 ('masonry_restoration','masonry-restoration-cleaning','synonym',0.99,'Masonry restoration cleaning.'),
 ('limestone_restoration','masonry-restoration-cleaning','synonym',0.99,'Limestone restoration cleaning.'),
 ('stone_restoration_cleaning','masonry-restoration-cleaning','synonym',0.96,'Stone/masonry restoration cleaning.')
) x(alias_key,service_slug,alias_kind,strength,notes)
join commerce.service_types st on st.slug=x.service_slug
on conflict(alias_key,service_type_id) do update set alias_kind=excluded.alias_kind,match_strength=excluded.match_strength,notes=excluded.notes;

-- Taxonomy/read catalog -------------------------------------------------------
create or replace view commerce.v_service_taxonomy as
with recursive tree as (
  select st.id,st.slug,st.name,st.parent_id,st.description,st.active,0::int depth,array[st.slug]::text[] path_slugs,array[st.name]::text[] path_names
  from commerce.service_types st where st.parent_id is null
  union all
  select c.id,c.slug,c.name,c.parent_id,c.description,c.active,t.depth+1,t.path_slugs||c.slug,t.path_names||c.name
  from commerce.service_types c join tree t on c.parent_id=t.id
)
select * from tree;

revoke all on commerce.v_service_taxonomy from anon,authenticated;
grant select on commerce.v_service_taxonomy to service_role;

create or replace function public.scout_get_service_taxonomy(p_root_slug text default null)
returns jsonb language sql stable security definer set search_path='' as $$
with selected as (
  select t.* from commerce.v_service_taxonomy t
  where p_root_slug is null or t.slug=p_root_slug or p_root_slug=any(t.path_slugs)
), nodes as (
  select s.id,s.slug,s.name,s.description,s.active,s.depth,s.parent_id,p.slug parent_slug,
         exists(select 1 from commerce.service_types c where c.parent_id=s.id and c.active) has_children,
         s.path_slugs,s.path_names
  from selected s left join commerce.service_types p on p.id=s.parent_id
)
select jsonb_build_object(
  'root_slug',p_root_slug,
  'nodes',coalesce(jsonb_agg(jsonb_build_object('service_id',id,'slug',slug,'name',name,'description',description,'parent_slug',parent_slug,'depth',depth,'has_children',has_children,'path_slugs',path_slugs,'path_names',path_names) order by path_slugs),'[]'::jsonb),
  'contract',jsonb_build_object('parent_is_umbrella_not_automatic_specialty_attestation',true,'child_selection_should_be_explicit_or_evidence_backed',true,'existing_parent_declarations_remain_valid',true)
) from nodes;
$$;

create or replace function public.scout_get_cleaning_workflow_catalog(p_service_slug text default null)
returns jsonb language sql stable security definer set search_path='' as $$
with rows as (
  select st.slug service_slug,st.name service_name,w.id workflow_id,w.slug workflow_slug,w.name workflow_name,w.workflow_kind,w.description,
         a.workflow_role,a.default_for_service,
         coalesce((select jsonb_agg(jsonb_build_object('capability_slug',ct.slug,'capability_name',ct.name,'requirement_level',r.requirement_level,'comparator',r.comparator,'value_boolean',r.value_boolean,'value_numeric',r.value_numeric,'value_text',r.value_text,'value_json',r.value_json,'unit',r.unit,'notes',r.notes) order by ct.name)
                   from cleaning.workflow_capability_requirements r join equipment.capability_types ct on ct.id=r.capability_type_id where r.workflow_id=w.id),'[]'::jsonb) capability_requirements,
         coalesce((select jsonb_agg(jsonb_build_object('product_kind',pr.product_kind,'application_role',pr.application_role,'requirement_level',pr.requirement_level,'notes',pr.notes) order by pr.requirement_level,pr.product_kind)
                   from cleaning.workflow_product_requirements pr where pr.workflow_id=w.id),'[]'::jsonb) product_requirements,
         coalesce((select jsonb_agg(jsonb_build_object('route_kind',rr.route_kind,'requirement_level',rr.requirement_level,'notes',rr.notes) order by rr.requirement_level,rr.route_kind)
                   from cleaning.workflow_route_requirements rr where rr.workflow_id=w.id),'[]'::jsonb) route_requirements
  from cleaning.service_workflow_applicability a
  join commerce.service_types st on st.id=a.service_type_id
  join cleaning.service_workflows w on w.id=a.workflow_id and w.active
  where p_service_slug is null or st.slug=p_service_slug
)
select jsonb_build_object('service_slug',p_service_slug,'workflows',coalesce(jsonb_agg(to_jsonb(rows) order by service_slug,case workflow_role when 'primary' then 0 when 'supporting' then 1 else 2 end,workflow_name),'[]'::jsonb),
'contract',jsonb_build_object('commercial_service_and_execution_workflow_are_distinct',true,'multiple_primary_workflows_mean_any_supported_primary_path_can_satisfy_the_service',true,'supporting_workflows_do_not_define_the_customer_service',true))
from rows;
$$;

revoke all on function public.scout_get_service_taxonomy(text) from public,anon,authenticated;
revoke all on function public.scout_get_cleaning_workflow_catalog(text) from public,anon,authenticated;
grant execute on function public.scout_get_service_taxonomy(text) to service_role;
grant execute on function public.scout_get_cleaning_workflow_catalog(text) to service_role;

-- Rig workflow readiness ------------------------------------------------------
create or replace function public.scout_get_rig_cleaning_workflow_access(p_organization_id uuid,p_rig_id uuid,p_service_slug text)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_service_id uuid;
  v_service_name text;
  v_workflows jsonb;
  v_primary_count integer:=0;
  v_any_ready boolean:=false;
begin
  select id,name into v_service_id,v_service_name from commerce.service_types where slug=p_service_slug and active;
  if v_service_id is null then raise exception 'unknown or inactive service: %',p_service_slug; end if;
  if not exists(select 1 from equipment.provider_rigs where id=p_rig_id and organization_id=p_organization_id and status in ('active','seasonal')) then raise exception 'active provider rig not found'; end if;

  select count(*) into v_primary_count from cleaning.service_workflow_applicability a join cleaning.service_workflows w on w.id=a.workflow_id and w.active where a.service_type_id=v_service_id and a.workflow_role='primary';
  if v_primary_count=0 then
    return jsonb_build_object('available',false,'reason','no_cleaning_workflow_model','service_slug',p_service_slug,'service_name',v_service_name,'rig_id',p_rig_id,'ready',true,'missing_requirements','[]'::jsonb,'workflows','[]'::jsonb);
  end if;

  with primary_workflows as (
    select w.id,w.slug,w.name,w.workflow_kind,a.default_for_service
    from cleaning.service_workflow_applicability a join cleaning.service_workflows w on w.id=a.workflow_id and w.active
    where a.service_type_id=v_service_id and a.workflow_role='primary'
  ), effective as (
    select rc.capability_type_id,rc.value_boolean,rc.value_numeric,rc.value_text,rc.value_json,rc.unit,rc.confidence from equipment.provider_rig_capabilities rc where rc.rig_id=p_rig_id
    union all
    select ec.capability_type_id,ec.value_boolean,ec.value_numeric,ec.value_text,ec.value_json,ec.unit,ec.confidence
    from scout.v_operator_effective_capabilities ec
    where ec.organization_id=p_organization_id and ec.source_provider_equipment_id is not null
      and exists(select 1 from equipment.provider_rig_members rm where rm.rig_id=p_rig_id and rm.provider_equipment_id=ec.source_provider_equipment_id)
  ), eval as (
    select pw.*,
      coalesce((select jsonb_agg(jsonb_build_object('type','workflow_capability','key',ct.slug,'name',ct.name,'workflow_slug',pw.slug,'gate_mode','profile_gate','requirement_level',r.requirement_level,'comparator',r.comparator,'required_value',jsonb_strip_nulls(jsonb_build_object('boolean',r.value_boolean,'numeric',r.value_numeric,'text',r.value_text,'json',r.value_json,'unit',r.unit)),'notes',r.notes) order by ct.name)
                from cleaning.workflow_capability_requirements r join equipment.capability_types ct on ct.id=r.capability_type_id
                where r.workflow_id=pw.id and r.requirement_level='required' and not exists(
                  select 1 from effective e where e.capability_type_id=r.capability_type_id and coalesce(e.confidence,0)>=0.5 and (
                    r.comparator='exists' or
                    (r.comparator='equals' and ((r.value_boolean is not null and e.value_boolean is not distinct from r.value_boolean) or (r.value_numeric is not null and e.value_numeric is not null and e.value_numeric=r.value_numeric and (r.unit is null or e.unit is null or lower(e.unit)=lower(r.unit))) or (r.value_text is not null and e.value_text is not null and lower(e.value_text)=lower(r.value_text)) or (r.value_json is not null and e.value_json=r.value_json))) or
                    (r.comparator='at_least' and r.value_numeric is not null and e.value_numeric is not null and e.value_numeric>=r.value_numeric and (r.unit is null or e.unit is null or lower(e.unit)=lower(r.unit))) or
                    (r.comparator='at_most' and r.value_numeric is not null and e.value_numeric is not null and e.value_numeric<=r.value_numeric and (r.unit is null or e.unit is null or lower(e.unit)=lower(r.unit)))
                  ))),'[]'::jsonb) cap_missing,
      coalesce((select jsonb_agg(jsonb_build_object('type','workflow_product','key',pr.product_kind,'name',initcap(replace(pr.product_kind,'_',' ')),'workflow_slug',pw.slug,'application_role',pr.application_role,'gate_mode','profile_gate','requirement_level','required','notes',pr.notes) order by pr.product_kind)
                from cleaning.workflow_product_requirements pr
                where pr.workflow_id=pw.id and pr.requirement_level='required' and not exists(
                  select 1 from cleaning.provider_rig_products rp
                  join cleaning.provider_products pp on pp.id=rp.provider_product_id
                  left join cleaning.products p on p.id=pp.product_id
                  left join commerce.service_types rst on rst.id=rp.service_type_id
                  where rp.rig_id=p_rig_id and rp.status='active' and pp.status='active' and pp.product_id is not null
                    and lower(coalesce(p.product_kind,pp.declared_product_kind,''))=lower(pr.product_kind)
                    and (pr.application_role is null or lower(coalesce(rp.application_role,''))=lower(pr.application_role))
                    and (rp.service_type_id is null or rp.service_type_id=v_service_id or rst.slug='exterior-cleaning')
                )),'[]'::jsonb) product_missing,
      coalesce((select jsonb_agg(jsonb_build_object('type','workflow_preference','key','route:'||rr.route_kind,'name','mapped '||replace(rr.route_kind,'_',' ')||' fluid route','workflow_slug',pw.slug,'requirement_level','preferred','notes',rr.notes) order by rr.route_kind)
                from cleaning.workflow_route_requirements rr
                where rr.workflow_id=pw.id and rr.requirement_level='preferred' and not exists(
                  select 1 from equipment.provider_rig_fluid_routes rf join equipment.fluid_routes fr on fr.id=rf.fluid_route_id
                  where rf.rig_id=p_rig_id and rf.status in ('active','backup') and fr.route_kind=rr.route_kind
                )),'[]'::jsonb) advisories
    from primary_workflows pw
  ), final as (
    select *,cap_missing||product_missing missing,jsonb_array_length(cap_missing||product_missing)=0 ready from eval
  )
  select coalesce(jsonb_agg(jsonb_build_object('workflow_id',id,'workflow_slug',slug,'workflow_name',name,'workflow_kind',workflow_kind,'default_for_service',default_for_service,'ready',ready,'missing_requirements',missing,'advisories',advisories) order by case when ready then 0 else 1 end,default_for_service desc,name),'[]'::jsonb),coalesce(bool_or(ready),false)
  into v_workflows,v_any_ready from final;

  return jsonb_build_object('available',true,'service_slug',p_service_slug,'service_name',v_service_name,'rig_id',p_rig_id,'ready',v_any_ready,'workflows',v_workflows,
    'missing_requirements',case when v_any_ready then '[]'::jsonb else coalesce((select jsonb_agg(distinct m.value) from jsonb_array_elements(v_workflows) w cross join lateral jsonb_array_elements(w.value->'missing_requirements') m),'[]'::jsonb) end,
    'contract',jsonb_build_object('any_ready_primary_workflow_satisfies_service_execution_path',true,'required_product_must_resolve_to_catalog_identity',true,'preferred_route_mapping_is_advisory_not_a_service_gate',true,'compatibility_evidence_is_evaluated_separately',true));
end;
$$;

revoke all on function public.scout_get_rig_cleaning_workflow_access(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.scout_get_rig_cleaning_workflow_access(uuid,uuid,text) to service_role;

-- Extend the existing service capability gate with cleaning workflow readiness.
create or replace function public.scout_get_rig_service_capability_access(p_organization_id uuid,p_rig_id uuid,p_service_slug text)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_service_id uuid; v_service_name text; v_delivery_id uuid; v_delivery_slug text; v_rig_name text; v_missing jsonb; v_workflow jsonb;
begin
  select st.id,st.name into v_service_id,v_service_name from commerce.service_types st where st.slug=p_service_slug and st.active;
  if v_service_id is null then raise exception 'unknown or inactive service: %',p_service_slug; end if;
  select r.name,coalesce(rs.delivery_method_id,r.default_delivery_method_id),dm.slug into v_rig_name,v_delivery_id,v_delivery_slug
  from equipment.provider_rigs r join equipment.provider_rig_services rs on rs.rig_id=r.id and rs.service_type_id=v_service_id and rs.status='active'
  left join commerce.delivery_methods dm on dm.id=coalesce(rs.delivery_method_id,r.default_delivery_method_id)
  where r.id=p_rig_id and r.organization_id=p_organization_id and r.status in ('active','seasonal') limit 1;
  if v_rig_name is null then return jsonb_build_object('ready',false,'service_slug',p_service_slug,'rig_id',p_rig_id,'missing_requirements',jsonb_build_array(jsonb_build_object('type','rig_service_mapping','name','active rig/service mapping','gate_mode','profile_gate'))); end if;

  with req as (
    select r.id,ct.id capability_type_id,ct.slug,ct.name,ct.value_type,r.comparator,r.value_boolean,r.value_numeric,r.value_text,r.value_json,r.unit,r.notes
    from commerce.service_capability_requirements r join equipment.capability_types ct on ct.id=r.capability_type_id
    where r.service_type_id=v_service_id and r.requirement_level='required' and (r.delivery_method_id is null or r.delivery_method_id=v_delivery_id)
  ), effective as (
    select rc.capability_type_id,rc.qualifier,rc.value_boolean,rc.value_numeric,rc.value_text,rc.value_json,rc.unit,rc.confidence from equipment.provider_rig_capabilities rc where rc.rig_id=p_rig_id
    union all
    select ec.capability_type_id,ec.qualifier,ec.value_boolean,ec.value_numeric,ec.value_text,ec.value_json,ec.unit,ec.confidence
    from scout.v_operator_effective_capabilities ec where ec.organization_id=p_organization_id and ec.source_provider_equipment_id is not null and exists(select 1 from equipment.provider_rig_members rm where rm.rig_id=p_rig_id and rm.provider_equipment_id=ec.source_provider_equipment_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object('type','equipment_capability','key',req.slug,'name',req.name,'gate_mode','profile_gate','requirement_level','required','comparator',req.comparator,'required_value',jsonb_strip_nulls(jsonb_build_object('boolean',req.value_boolean,'numeric',req.value_numeric,'text',req.value_text,'json',req.value_json,'unit',req.unit)),'notes',req.notes) order by req.name),'[]'::jsonb)
  into v_missing from req
  where not exists(select 1 from effective e where e.capability_type_id=req.capability_type_id and coalesce(e.confidence,0)>=0.5 and req.comparator='equals' and ((req.value_boolean is not null and e.value_boolean is not distinct from req.value_boolean) or (req.value_numeric is not null and e.value_numeric is not null and e.value_numeric=req.value_numeric and (req.unit is null or e.unit is null or lower(e.unit)=lower(req.unit))) or (req.value_text is not null and e.value_text is not null and lower(e.value_text)=lower(req.value_text)) or (req.value_json is not null and e.value_json=req.value_json)));

  v_workflow:=public.scout_get_rig_cleaning_workflow_access(p_organization_id,p_rig_id,p_service_slug);
  if coalesce((v_workflow->>'available')::boolean,false) and not coalesce((v_workflow->>'ready')::boolean,false) then v_missing:=v_missing||coalesce(v_workflow->'missing_requirements','[]'::jsonb); end if;

  return jsonb_build_object('ready',jsonb_array_length(v_missing)=0,'service_slug',p_service_slug,'service_name',v_service_name,'rig_id',p_rig_id,'rig_name',v_rig_name,'delivery_method',v_delivery_slug,'missing_requirements',v_missing,'effective_capabilities',public.scout_get_rig_effective_capabilities(p_rig_id),'cleaning_workflow_access',v_workflow,'authoritative_legal_determination',false);
end;
$$;

-- Onboarding catalog ----------------------------------------------------------
create or replace function public.scout_get_onboarding_catalog(p_service_slugs text[] default null::text[], p_operating_states text[] default null::text[])
returns jsonb
language sql
stable security definer
set search_path=''
as $$
with svc as (
  select st.id,st.slug,st.name,st.description,p.slug parent_slug,p.name parent_name,exists(select 1 from commerce.service_types c where c.parent_id=st.id and c.active) has_children
  from commerce.service_types st left join commerce.service_types p on p.id=st.parent_id where st.active
), selected as (
  select id from svc where p_service_slugs is not null and slug=any(p_service_slugs)
), creds as (
  select distinct ct.slug,ct.name,ct.credential_class,ct.issuing_authority,ct.jurisdiction_code,r.requirement_kind,r.notes
  from commerce.service_credential_requirements r join compliance.credential_types ct on ct.id=r.credential_type_id join selected s on s.id=r.service_type_id
  where ct.slug<>'faa-airspace-authorization' and (r.jurisdiction_code is null or r.jurisdiction_code='US' or r.jurisdiction_code='STATE' or p_operating_states is null or r.jurisdiction_code=any(p_operating_states))
), cleaning_scope as (
  select exists(select 1 from svc s where (p_service_slugs is null or s.slug=any(p_service_slugs)) and (s.slug='exterior-cleaning' or s.parent_slug='exterior-cleaning')) relevant
)
select jsonb_build_object(
  'version',4,
  'privacy',jsonb_build_object('collect_credential_identifiers',false,'collect_equipment_serial_numbers_during_onboarding',false,'optional_post_confirmation_serial_recordkeeping',true,'instruction','Ask only for business-relevant setup facts. Never ask for license, certificate, registration, policy, or equipment serial numbers during onboarding. Product names, manufacturers, mix descriptions and rig assignments are allowed business setup data; do not request proprietary formulas unless the operator explicitly chooses to store them.'),
  'services',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'description',description,'parent_slug',parent_slug,'parent_name',parent_name,'has_children',has_children) order by coalesce(parent_name,name),case when parent_slug is null then 0 else 1 end,name),'[]'::jsonb) from svc where p_service_slugs is null or slug=any(p_service_slugs)),
  'service_selection_policy',jsonb_build_object('umbrella_and_specialization_are_distinct',true,'exterior_cleaning_rule','Exterior Cleaning is an umbrella. When an operator selects it, ask which supported child services they actually perform rather than inferring every specialty.','supported_exterior_cleaning_children',jsonb_build_array('building-envelope-cleaning','pure-water-window-cleaning','exterior-biocide-treatment','masonry-restoration-cleaning','solar-pv-cleaning'),'pressure_softwash_rule','Pressure wash and soft wash are execution workflows under Building Envelope Cleaning, not separate commercial services.','no_specialty_is_valid',true),
  'exterior_cleaning_taxonomy',case when (select relevant from cleaning_scope) then public.scout_get_service_taxonomy('exterior-cleaning') else null end,
  'cleaning_workflows',case when (select relevant from cleaning_scope) then public.scout_get_cleaning_workflow_catalog(null) else jsonb_build_object('workflows','[]'::jsonb) end,
  'relevant_credentials',(select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'class',credential_class,'authority',issuing_authority,'jurisdiction',jurisdiction_code,'requirement',requirement_kind,'notes',notes) order by requirement_kind,name),'[]'::jsonb) from creds),
  'credential_states',jsonb_build_array('active','expired','pursuing','none','unknown'),
  'equipment_instruction','Use scout_search_equipment_models for model resolution. If no catalog model matches, preserve the operator-entered model name. Never request a serial number during setup.',
  'cleaning_product_instruction','For cleaning operators, capture the actual cleaners/chemicals/process fluids used by each rig. If Scout recognizes the product uniquely it may resolve it to the catalog; otherwise preserve the operator-entered name and optional manufacturer/product kind. Unknown identity or compatibility stays unresolved. Do not ask the operator to guess chemistry compatibility.',
  'cleaning_product_kinds',jsonb_build_array('cleaner','window_cleaner','surfactant','biocide','disinfectant','restoration_chemical','descaler','solvent','process_water','other'),
  'fluid_route_kinds',jsonb_build_array('cleaning_delivery','window_wash','rinse','chemical_transfer','mixed_service','other'),
  'fluid_route_policy','Fluid route details are optional during initial capture. Create an operator-scoped route shell when the route is known but its wetted components are not yet mapped; Scout should research/map the route later rather than asking the operator to infer compatibility.'
)
$$;
