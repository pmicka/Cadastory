-- Scout provider rig cleaning setup RPC v1
-- Final production definitions for operator cleaning inventory, rig/product/route
-- assignment, and compatibility context. Missing evidence remains unresolved.

create or replace function public.scout_get_provider_cleaning_setup(p_organization_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $$
select jsonb_build_object(
  'cleaning_products_confirmed_at',(select cleaning_products_confirmed_at from commerce.provider_onboarding_state where organization_id=p_organization_id),
  'product_inventory',coalesce((
    select jsonb_agg(jsonb_build_object(
      'provider_product_id',pp.id,
      'product_id',pp.product_id,
      'product_name',coalesce(p.product_name,pp.entered_name),
      'manufacturer',coalesce(p.manufacturer_name,pp.declared_manufacturer_name),
      'product_kind',coalesce(p.product_kind,pp.declared_product_kind),
      'catalog_resolved',pp.product_id is not null,
      'concentration_as_purchased_pct',pp.concentration_as_purchased_pct,
      'default_mix',pp.default_mix,
      'status',pp.status
    ) order by coalesce(p.product_name,pp.entered_name))
    from cleaning.provider_products pp
    left join cleaning.products p on p.id=pp.product_id
    where pp.organization_id=p_organization_id and pp.status in ('active','planned')
  ),'[]'::jsonb),
  'rig_product_assignments',coalesce((
    select jsonb_agg(to_jsonb(x) order by x.rig_name,x.product_name,x.application_role)
    from cleaning.v_provider_rig_product_readiness x where x.organization_id=p_organization_id
  ),'[]'::jsonb),
  'rig_fluid_routes',coalesce((
    select jsonb_agg(to_jsonb(x) order by x.rig_name,x.fluid_route_name,x.route_role)
    from equipment.v_provider_rig_fluid_route_readiness x where x.organization_id=p_organization_id
  ),'[]'::jsonb),
  'summary',jsonb_build_object(
    'active_product_count',(select count(*) from cleaning.provider_products pp where pp.organization_id=p_organization_id and pp.status='active'),
    'assigned_product_count',(select count(*) from cleaning.provider_rig_products rp join equipment.provider_rigs r on r.id=rp.rig_id where r.organization_id=p_organization_id and rp.status='active'),
    'unresolved_product_identity_count',(select count(*) from cleaning.v_provider_rig_product_readiness x where x.organization_id=p_organization_id and x.readiness_status='product_identity_unresolved'),
    'route_mapping_incomplete_count',(select count(*) from cleaning.v_provider_rig_product_readiness x where x.organization_id=p_organization_id and x.readiness_status='route_mapping_incomplete'),
    'compatibility_unresolved_count',(select count(*) from cleaning.v_provider_rig_product_readiness x where x.organization_id=p_organization_id and x.readiness_status in ('compatibility_unresolved','route_not_assigned')),
    'blocked_count',(select count(*) from cleaning.v_provider_rig_product_readiness x where x.organization_id=p_organization_id and x.readiness_status='blocked')
  ),
  'evidence_rule','Operator-declared products and route assignments describe actual setup intent. Unknown product identity, unmapped fluid paths, and missing compatibility evidence remain unresolved and are never treated as approval.'
);
$$;

revoke all on function public.scout_get_provider_cleaning_setup(uuid) from public,anon,authenticated;
grant execute on function public.scout_get_provider_cleaning_setup(uuid) to service_role;

create or replace function public.scout_update_provider_rig_cleaning_setup(p_organization_id uuid,p_rigs jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  rig jsonb;
  item jsonb;
  route_item jsonb;
  k text;
  v_rig_id uuid;
  v_rig_name text;
  v_route_id uuid;
  v_route_name text;
  v_route_slug text;
  v_route_kind text;
  v_route_status text;
  v_route_role text;
  v_service_id uuid;
  v_service_slug text;
  v_provider_product_id uuid;
  v_product_id uuid;
  v_product_name text;
  v_product_kind text;
  v_manufacturer text;
  v_product_status text;
  v_application_role text;
  v_service_mode text;
  v_concentration numeric;
  v_default_mix jsonb;
  v_match_count integer;
  v_allowed_route text[]:=array['fluid_route_id','name','route_kind','route_role','service_slug','status'];
  v_allowed_product text[]:=array['provider_product_id','product_id','name','manufacturer','product_kind','concentration_as_purchased_pct','default_mix','application_role','service_slug','fluid_route_id','fluid_route_name','service_mode','status'];
  v_now timestamptz:=clock_timestamp();
begin
  if not exists(select 1 from commerce.provider_profiles where organization_id=p_organization_id) then raise exception 'provider profile not found'; end if;
  if p_rigs is null or jsonb_typeof(p_rigs)<>'array' then raise exception 'rigs must be an array'; end if;
  if public.scout_json_has_forbidden_profile_keys(p_rigs) then raise exception 'sensitive identifier fields are not accepted by Scout onboarding'; end if;

  for rig in select value from jsonb_array_elements(p_rigs) loop
    if jsonb_typeof(rig)<>'object' then raise exception 'each rig must be an object'; end if;
    v_rig_id:=null;
    v_rig_name:=nullif(btrim(rig->>'name'),'');
    if nullif(rig->>'rig_id','') is not null then
      begin v_rig_id:=(rig->>'rig_id')::uuid; exception when invalid_text_representation then raise exception 'invalid rig_id'; end;
    end if;
    if v_rig_id is null and v_rig_name is not null then
      select id into v_rig_id from equipment.provider_rigs where organization_id=p_organization_id and lower(name)=lower(v_rig_name) limit 1;
    end if;
    if v_rig_id is null or not exists(select 1 from equipment.provider_rigs where id=v_rig_id and organization_id=p_organization_id) then
      raise exception 'cannot resolve provider rig for cleaning setup';
    end if;

    if rig ? 'fluid_routes' then
      if jsonb_typeof(rig->'fluid_routes')<>'array' then raise exception 'rig fluid_routes must be an array'; end if;
      if jsonb_array_length(rig->'fluid_routes')>20 then raise exception 'too many fluid routes for one rig'; end if;
      delete from equipment.provider_rig_fluid_routes where rig_id=v_rig_id and attributes->>'source'='operator_onboarding';

      for route_item in select value from jsonb_array_elements(rig->'fluid_routes') loop
        if jsonb_typeof(route_item)<>'object' then raise exception 'each fluid route must be an object'; end if;
        for k in select jsonb_object_keys(route_item) loop
          if not (k=any(v_allowed_route)) then raise exception 'unsupported fluid route field: %',k; end if;
        end loop;
        v_route_id:=null;
        v_route_name:=nullif(btrim(route_item->>'name'),'');
        if nullif(route_item->>'fluid_route_id','') is not null then
          begin v_route_id:=(route_item->>'fluid_route_id')::uuid; exception when invalid_text_representation then raise exception 'invalid fluid_route_id'; end;
          if not exists(select 1 from equipment.fluid_routes where id=v_route_id and organization_id=p_organization_id) then raise exception 'fluid_route_id does not belong to provider'; end if;
        elsif v_route_name is not null then
          select id into v_route_id from equipment.fluid_routes where organization_id=p_organization_id and lower(name)=lower(v_route_name) limit 1;
          if v_route_id is null then
            v_route_kind:=coalesce(nullif(lower(btrim(route_item->>'route_kind')),''),'cleaning_delivery');
            if v_route_kind not in ('cleaning_delivery','window_wash','rinse','chemical_transfer','mixed_service','other') then raise exception 'invalid fluid route kind'; end if;
            v_route_status:=coalesce(nullif(lower(btrim(route_item->>'status')),''),'active');
            if v_route_status not in ('active','backup','planned','retired') then raise exception 'invalid fluid route status'; end if;
            v_route_slug:=left(trim(both '-' from regexp_replace(lower(v_route_name),'[^a-z0-9]+','-','g')),100);
            if v_route_slug='' then v_route_slug:='operator-route'; end if;
            if exists(select 1 from equipment.fluid_routes where organization_id=p_organization_id and slug=v_route_slug) then
              v_route_slug:=left(v_route_slug,91)||'-'||left(gen_random_uuid()::text,8);
            end if;
            insert into equipment.fluid_routes(organization_id,slug,name,route_kind,status,attributes)
            values(p_organization_id,v_route_slug,v_route_name,v_route_kind,v_route_status,jsonb_build_object('source','operator_onboarding','declaration','self_attested','mapping_status','route_shell'))
            returning id into v_route_id;
          end if;
        else
          raise exception 'fluid route requires fluid_route_id or name';
        end if;

        v_service_id:=null;
        v_service_slug:=nullif(lower(btrim(route_item->>'service_slug')),'');
        if v_service_slug is not null then
          select id into v_service_id from commerce.service_types where slug=v_service_slug and active;
          if v_service_id is null then raise exception 'unknown or inactive fluid route service: %',v_service_slug; end if;
        end if;
        v_route_role:=coalesce(nullif(lower(btrim(route_item->>'route_role')),''),'primary_delivery');
        if v_route_role !~ '^[a-z][a-z0-9_.-]{0,79}$' then raise exception 'invalid fluid route role'; end if;
        select status into v_route_status from equipment.fluid_routes where id=v_route_id;
        insert into equipment.provider_rig_fluid_routes(rig_id,fluid_route_id,service_type_id,route_role,status,attributes)
        values(v_rig_id,v_route_id,v_service_id,v_route_role,case v_route_status when 'retired' then 'inactive' when 'backup' then 'backup' when 'planned' then 'planned' else 'active' end,jsonb_build_object('source','operator_onboarding','declaration','self_attested'))
        on conflict do nothing;
      end loop;
    end if;

    if rig ? 'products' then
      if jsonb_typeof(rig->'products')<>'array' then raise exception 'rig products must be an array'; end if;
      if jsonb_array_length(rig->'products')>60 then raise exception 'too many products for one rig'; end if;
      delete from cleaning.provider_rig_products where rig_id=v_rig_id and attributes->>'source'='operator_onboarding';

      for item in select value from jsonb_array_elements(rig->'products') loop
        if jsonb_typeof(item)<>'object' then raise exception 'each rig product must be an object'; end if;
        for k in select jsonb_object_keys(item) loop
          if not (k=any(v_allowed_product)) then raise exception 'unsupported rig product field: %',k; end if;
        end loop;

        v_provider_product_id:=null;
        v_product_id:=null;
        v_product_name:=nullif(btrim(item->>'name'),'');
        v_manufacturer:=nullif(btrim(item->>'manufacturer'),'');
        v_product_kind:=nullif(lower(btrim(item->>'product_kind')),'');
        v_product_status:=coalesce(nullif(lower(btrim(item->>'status')),''),'active');
        if v_product_status not in ('active','inactive','planned') then raise exception 'invalid provider product status'; end if;
        if v_product_kind is not null and v_product_kind !~ '^[a-z][a-z0-9_.-]{0,79}$' then raise exception 'invalid product_kind'; end if;
        v_concentration:=null;
        if item ? 'concentration_as_purchased_pct' and jsonb_typeof(item->'concentration_as_purchased_pct')<>'null' then
          v_concentration:=(item->>'concentration_as_purchased_pct')::numeric;
          if v_concentration<0 or v_concentration>100 then raise exception 'concentration_as_purchased_pct must be 0-100'; end if;
        end if;
        v_default_mix:=case when item ? 'default_mix' then item->'default_mix' else null end;

        if nullif(item->>'provider_product_id','') is not null then
          begin v_provider_product_id:=(item->>'provider_product_id')::uuid; exception when invalid_text_representation then raise exception 'invalid provider_product_id'; end;
          if not exists(select 1 from cleaning.provider_products where id=v_provider_product_id and organization_id=p_organization_id) then raise exception 'provider_product_id does not belong to provider'; end if;
        else
          if nullif(item->>'product_id','') is not null then
            begin v_product_id:=(item->>'product_id')::uuid; exception when invalid_text_representation then raise exception 'invalid product_id'; end;
            if not exists(select 1 from cleaning.products where id=v_product_id and product_status='active') then raise exception 'product_id not found or inactive'; end if;
          elsif v_product_name is not null then
            select count(*),(array_agg(id order by id))[1] into v_match_count,v_product_id
            from cleaning.products p
            where p.product_status='active' and lower(p.product_name)=lower(v_product_name)
              and (v_manufacturer is null or lower(coalesce(p.manufacturer_name,''))=lower(v_manufacturer));
            if v_match_count<>1 then v_product_id:=null; end if;
          end if;

          if v_product_id is null and v_product_name is null then raise exception 'rig product requires provider_product_id, product_id, or name'; end if;

          if v_product_id is not null then
            select id into v_provider_product_id from cleaning.provider_products where organization_id=p_organization_id and product_id=v_product_id order by created_at limit 1;
          else
            select id into v_provider_product_id
            from cleaning.provider_products
            where organization_id=p_organization_id and product_id is null and lower(coalesce(entered_name,''))=lower(v_product_name)
              and (v_manufacturer is null or lower(coalesce(declared_manufacturer_name,''))=lower(v_manufacturer))
            order by created_at limit 1;
          end if;

          if v_provider_product_id is null then
            insert into cleaning.provider_products(organization_id,product_id,entered_name,declared_product_kind,declared_manufacturer_name,concentration_as_purchased_pct,default_mix,status,attributes)
            values(p_organization_id,v_product_id,case when v_product_id is null then v_product_name else null end,v_product_kind,v_manufacturer,v_concentration,v_default_mix,v_product_status,jsonb_build_object('source','operator_onboarding','declaration','self_attested'))
            returning id into v_provider_product_id;
          else
            update cleaning.provider_products
            set entered_name=case when product_id is null then coalesce(v_product_name,entered_name) else entered_name end,
                declared_product_kind=coalesce(v_product_kind,declared_product_kind),
                declared_manufacturer_name=coalesce(v_manufacturer,declared_manufacturer_name),
                concentration_as_purchased_pct=coalesce(v_concentration,concentration_as_purchased_pct),
                default_mix=coalesce(v_default_mix,default_mix),
                status=v_product_status,
                updated_at=v_now
            where id=v_provider_product_id;
          end if;
        end if;

        v_service_id:=null;
        v_service_slug:=nullif(lower(btrim(item->>'service_slug')),'');
        if v_service_slug is not null then
          select id into v_service_id from commerce.service_types where slug=v_service_slug and active;
          if v_service_id is null then raise exception 'unknown or inactive product service: %',v_service_slug; end if;
        else
          select case when count(*)=1 then min(service_type_id) else null end into v_service_id
          from equipment.provider_rig_services where rig_id=v_rig_id and status='active';
        end if;

        v_route_id:=null;
        if nullif(item->>'fluid_route_id','') is not null then
          begin v_route_id:=(item->>'fluid_route_id')::uuid; exception when invalid_text_representation then raise exception 'invalid product fluid_route_id'; end;
        elsif nullif(btrim(item->>'fluid_route_name'),'') is not null then
          select rf.fluid_route_id into v_route_id
          from equipment.provider_rig_fluid_routes rf join equipment.fluid_routes fr on fr.id=rf.fluid_route_id
          where rf.rig_id=v_rig_id and lower(fr.name)=lower(btrim(item->>'fluid_route_name')) and rf.status in ('active','backup','planned') limit 1;
          if v_route_id is null then raise exception 'product fluid_route_name is not assigned to this rig'; end if;
        else
          select case when count(*)=1 then min(fluid_route_id) else null end into v_route_id
          from equipment.provider_rig_fluid_routes rf
          where rf.rig_id=v_rig_id and rf.status='active' and (v_service_id is null or rf.service_type_id is null or rf.service_type_id=v_service_id);
        end if;

        v_application_role:=coalesce(nullif(lower(btrim(item->>'application_role')),''),'cleaner');
        if v_application_role !~ '^[a-z][a-z0-9_.-]{0,79}$' then raise exception 'invalid product application_role'; end if;
        v_service_mode:=nullif(lower(btrim(item->>'service_mode')),'');
        if v_service_mode is not null and v_service_mode !~ '^[a-z][a-z0-9_.-]{0,119}$' then raise exception 'invalid product service_mode'; end if;

        insert into cleaning.provider_rig_products(rig_id,provider_product_id,service_type_id,fluid_route_id,application_role,service_mode,default_mix,status,attributes)
        values(v_rig_id,v_provider_product_id,v_service_id,v_route_id,v_application_role,v_service_mode,v_default_mix,case when v_product_status='inactive' then 'inactive' when v_product_status='planned' then 'planned' else 'active' end,jsonb_build_object('source','operator_onboarding','declaration','self_attested'))
        on conflict do nothing;
      end loop;
    end if;
  end loop;

  return public.scout_get_provider_cleaning_setup(p_organization_id);
end;
$$;

revoke all on function public.scout_update_provider_rig_cleaning_setup(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.scout_update_provider_rig_cleaning_setup(uuid,jsonb) to service_role;

create or replace function public.scout_get_provider_rigs_raw(p_organization_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $$
select coalesce(jsonb_agg(
  jsonb_build_object(
    'rig_id',r.id,
    'name',r.name,
    'status',r.status,
    'delivery_method',dm.slug,
    'notes',r.notes,
    'services',coalesce((
      select jsonb_agg(jsonb_build_object('slug',st.slug,'name',st.name,'delivery_method',coalesce(rsdm.slug,dm.slug),'status',rs.status) order by st.name)
      from equipment.provider_rig_services rs
      join commerce.service_types st on st.id=rs.service_type_id
      left join commerce.delivery_methods rsdm on rsdm.id=rs.delivery_method_id
      where rs.rig_id=r.id
    ),'[]'::jsonb),
    'equipment',coalesce((
      select jsonb_agg(jsonb_build_object(
        'rig_member_id',rm.id,'provider_equipment_id',pe.id,'role',rm.role,'quantity',rm.quantity,
        'model_id',m.id,'manufacturer',mf.name,'model_name',m.model_name,'entered_name',pe.entered_name,
        'status',pe.status,'notes',rm.notes
      ) order by rm.role,coalesce(mf.name||' '||m.model_name,pe.entered_name))
      from equipment.provider_rig_members rm
      join equipment.provider_equipment pe on pe.id=rm.provider_equipment_id
      left join equipment.models m on m.id=pe.model_id
      left join equipment.manufacturers mf on mf.id=m.manufacturer_id
      where rm.rig_id=r.id
    ),'[]'::jsonb),
    'fluid_routes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'rig_fluid_route_id',x.rig_fluid_route_id,'fluid_route_id',x.fluid_route_id,'name',x.fluid_route_name,
        'slug',x.fluid_route_slug,'route_kind',x.route_kind,'route_role',x.route_role,'service_slug',x.service_slug,
        'status',x.status,'readiness_status',x.readiness_status,'component_count',x.component_count,
        'wetted_inventory_complete',x.wetted_inventory_complete,'next_mapping_action',x.next_mapping_action
      ) order by x.route_role,x.fluid_route_name)
      from equipment.v_provider_rig_fluid_route_readiness x where x.rig_id=r.id
    ),'[]'::jsonb),
    'products',coalesce((
      select jsonb_agg(jsonb_build_object(
        'rig_product_id',x.rig_product_id,'provider_product_id',x.provider_product_id,'product_id',x.product_id,
        'product_name',x.product_name,'manufacturer',x.manufacturer_name,'product_kind',x.product_kind,
        'application_role',x.application_role,'service_slug',x.service_slug,'fluid_route_id',x.fluid_route_id,
        'fluid_route_name',x.fluid_route_name,'service_mode',x.service_mode,'default_mix',x.effective_default_mix,
        'status',x.status,'readiness_status',x.readiness_status,'route_product_compatibility',x.route_product_compatibility,
        'manufacturer_verification_required',x.manufacturer_verification_required
      ) order by x.application_role,x.product_name)
      from cleaning.v_provider_rig_product_readiness x where x.rig_id=r.id
    ),'[]'::jsonb)
  ) order by case r.status when 'active' then 0 when 'seasonal' then 1 when 'planned' then 2 else 3 end,r.name
),'[]'::jsonb)
from equipment.provider_rigs r
left join commerce.delivery_methods dm on dm.id=r.default_delivery_method_id
where r.organization_id=p_organization_id;
$$;

-- Evaluate only declared rig-product relationships. Prefer whole-route evidence when
-- a route is assigned; model-level evidence remains lower-scope fallback evidence.
create or replace function public.scout_get_connection_cleaning_compatibility_context(p_connection_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare v_org uuid; v_pairs jsonb; v_unassigned jsonb;
begin
  select organization_id into v_org from commerce.provider_agent_connections
  where id=p_connection_id and status='active' and (expires_at is null or expires_at>now());
  if not found then raise exception 'active Scout connection not found'; end if;
  if v_org is null then return jsonb_build_object('available',false,'reason','onboarding_required'); end if;

  with rig_models as (
    select distinct r.id rig_id,r.name rig_name,pe.id provider_equipment_id,pe.model_id,m.model_name
    from equipment.provider_rigs r
    join equipment.provider_rig_members rm on rm.rig_id=r.id
    join equipment.provider_equipment pe on pe.id=rm.provider_equipment_id
    join equipment.models m on m.id=pe.model_id
    where r.organization_id=v_org and r.status in ('active','seasonal') and pe.status not in ('retired','removed')
  ), assigned_products as (
    select rp.rig_id,rp.provider_product_id,pp.product_id,
      p.slug product_slug,coalesce(p.product_name,pp.entered_name) product_name,
      coalesce(p.manufacturer_name,pp.declared_manufacturer_name) manufacturer_name,
      rp.fluid_route_id,fr.name fluid_route_name,rp.application_role,rp.service_mode,
      coalesce(rp.default_mix,pp.default_mix) effective_mix
    from cleaning.provider_rig_products rp
    join equipment.provider_rigs r on r.id=rp.rig_id
    join cleaning.provider_products pp on pp.id=rp.provider_product_id
    left join cleaning.products p on p.id=pp.product_id
    left join equipment.fluid_routes fr on fr.id=rp.fluid_route_id
    where r.organization_id=v_org and r.status in ('active','seasonal') and rp.status='active' and pp.status='active'
  ), pairs as (
    select rm.*,pr.*,
      rps.overall_compatibility route_product_compatibility,
      rps.confidence route_product_confidence,
      rps.manufacturer_verification_required route_manufacturer_verification_required,
      coalesce(ex.rules,'[]'::jsonb) exact_product_rules,
      coalesce(ir.rules,'[]'::jsonb) ingredient_model_rules,
      coalesce(mr.rules,'[]'::jsonb) wetted_material_conflicts,
      coalesce(ws.inventory_status,'unknown') wetted_inventory_status,
      coalesce(ws.confidence,0) wetted_inventory_confidence,
      case
        when pr.product_id is null then 'unresolved_product_identity'
        when pr.fluid_route_id is not null and rps.overall_compatibility='incompatible' then 'hard_stop'
        when pr.fluid_route_id is not null and rps.overall_compatibility='doubtful' then 'not_recommended'
        when pr.fluid_route_id is not null and rps.overall_compatibility='conditional' then 'conditional_route_rule'
        when pr.fluid_route_id is not null and rps.overall_compatibility='compatible' then 'supported_route_rule'
        when pr.fluid_route_id is not null then 'unresolved_route_evidence'
        when coalesce(ex.has_prohibited,false) or coalesce(ir.has_prohibited,false) or coalesce(mr.has_incompatible,false) then 'hard_stop'
        when coalesce(ex.has_not_recommended,false) or coalesce(ir.has_not_recommended,false) then 'not_recommended'
        when coalesce(ex.has_conditional,false) then 'conditional_exact_product_rule'
        when coalesce(ex.has_supported,false) then 'supported_exact_product_rule'
        when coalesce(ir.rule_count,0)>0 then 'unresolved_with_known_ingredient_rules'
        when coalesce(mr.rule_count,0)>0 then 'unresolved_with_known_material_rules'
        else 'unresolved'
      end decision_state
    from rig_models rm join assigned_products pr on pr.rig_id=rm.rig_id
    left join cleaning.fluid_route_product_summary rps on rps.fluid_route_id=pr.fluid_route_id and rps.product_id=pr.product_id
    left join lateral (
      select jsonb_agg(jsonb_build_object('disposition',mcr.disposition,'scope',mcr.rule_scope,'requirements',mcr.requirements,'rationale',mcr.rationale,'confidence',mcr.confidence,'evidence_claim_id',mcr.evidence_claim_id) order by mcr.confidence desc) rules,
             bool_or(mcr.disposition='prohibited') has_prohibited,bool_or(mcr.disposition='not_recommended') has_not_recommended,
             bool_or(mcr.disposition='conditional') has_conditional,bool_or(mcr.disposition='supported') has_supported
      from cleaning.model_chemistry_rules mcr where pr.product_id is not null and mcr.model_id=rm.model_id and mcr.product_id=pr.product_id
    ) ex on true
    left join lateral (
      select jsonb_agg(jsonb_build_object('chemical_agent',ca.slug,'chemical_name',ca.name,'ingredient_role',pi.ingredient_role,'ingredient_concentration_min_pct',pi.concentration_min_pct,'ingredient_concentration_max_pct',pi.concentration_max_pct,'disposition',mcr.disposition,'scope',mcr.rule_scope,'requirements',mcr.requirements,'rationale',mcr.rationale,'confidence',least(pi.confidence,mcr.confidence),'evidence_claim_id',mcr.evidence_claim_id) order by ca.slug,mcr.confidence desc) rules,
             count(*) rule_count,bool_or(mcr.disposition='prohibited') has_prohibited,bool_or(mcr.disposition='not_recommended') has_not_recommended
      from cleaning.product_ingredients pi
      join cleaning.chemical_agents ca on ca.id=pi.chemical_agent_id
      join cleaning.model_chemistry_rules mcr on mcr.model_id=rm.model_id and mcr.chemical_agent_id=pi.chemical_agent_id
      where pr.product_id is not null and pi.product_id=pr.product_id
    ) ir on true
    left join lateral (
      select jsonb_agg(jsonb_build_object('component_role',mwm.component_role,'service_mode',mwm.service_mode,'material_slug',hm.slug,'material_name',hm.name,'compatibility',phc.compatibility,'manufacturer_verification_required',phc.manufacturer_verification_required,'rationale',phc.rationale,'confidence',least(mwm.confidence,phc.confidence),'evidence_claim_id',phc.evidence_claim_id) order by mwm.component_role,hm.slug) rules,
             count(*) rule_count,bool_or(phc.compatibility='incompatible') has_incompatible
      from equipment.model_wetted_materials mwm
      join cleaning.hardware_materials hm on hm.id=mwm.hardware_material_id
      join cleaning.product_hardware_compatibility phc on phc.product_id=pr.product_id and phc.hardware_material_id=mwm.hardware_material_id
      where pr.product_id is not null and mwm.model_id=rm.model_id
    ) mr on true
    left join lateral (
      select inventory_status,confidence from equipment.model_wetted_material_status s
      where s.model_id=rm.model_id order by (s.configuration_id is null) desc,s.updated_at desc limit 1
    ) ws on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rig_id',rig_id,'rig_name',rig_name,'provider_equipment_id',provider_equipment_id,'model_id',model_id,'model_name',model_name,
    'provider_product_id',provider_product_id,'product_id',product_id,'product_slug',product_slug,'product_name',product_name,'manufacturer',manufacturer_name,
    'fluid_route_id',fluid_route_id,'fluid_route_name',fluid_route_name,'application_role',application_role,'service_mode',service_mode,'effective_mix',effective_mix,
    'decision_state',decision_state,'route_product_compatibility',route_product_compatibility,'route_product_confidence',route_product_confidence,
    'route_manufacturer_verification_required',route_manufacturer_verification_required,
    'wetted_inventory_status',wetted_inventory_status,'wetted_inventory_confidence',wetted_inventory_confidence,
    'exact_product_rules',exact_product_rules,'ingredient_model_rules',ingredient_model_rules,'wetted_material_conflicts',wetted_material_conflicts,
    'interpretation',case decision_state
      when 'supported_route_rule' then 'Scout has whole-route product compatibility evidence for the operator-declared fluid route, subject to current configuration and stated requirements.'
      when 'conditional_route_rule' then 'Scout has conditional whole-route product evidence; satisfy every stated requirement before use.'
      when 'unresolved_route_evidence' then 'The operator assigned this product to a fluid route, but whole-route evidence is incomplete. This remains unresolved, not approval.'
      when 'unresolved_product_identity' then 'Scout preserved the operator-entered product, but has not resolved it to a catalog/SDS-backed product yet. Compatibility cannot be inferred.'
      when 'supported_exact_product_rule' then 'Scout has a product-specific model rule supporting this model/product combination, but the full operator fluid route is not mapped; do not generalize this to whole-system approval.'
      when 'conditional_exact_product_rule' then 'Scout has a product-specific conditional model rule; satisfy every stated requirement and resolve the full operator route before use.'
      when 'hard_stop' then 'Scout has evidence of an incompatible or prohibited condition. Do not treat this combination as usable without authoritative resolution.'
      when 'not_recommended' then 'Scout has evidence that this combination is not recommended.'
      else 'Scout does not have enough whole-system evidence to call this product/rig combination compatible. Missing evidence is unresolved, not approval.'
    end
  ) order by rig_name,model_name,product_name),'[]'::jsonb) into v_pairs from pairs;

  select coalesce(jsonb_agg(jsonb_build_object(
    'provider_product_id',pp.id,'product_id',pp.product_id,'product_name',coalesce(p.product_name,pp.entered_name),
    'manufacturer',coalesce(p.manufacturer_name,pp.declared_manufacturer_name),'product_kind',coalesce(p.product_kind,pp.declared_product_kind),
    'reason','not_assigned_to_active_rig'
  ) order by coalesce(p.product_name,pp.entered_name)),'[]'::jsonb)
  into v_unassigned
  from cleaning.provider_products pp left join cleaning.products p on p.id=pp.product_id
  where pp.organization_id=v_org and pp.status='active'
    and not exists(
      select 1 from cleaning.provider_rig_products rp
      join equipment.provider_rigs r on r.id=rp.rig_id
      where rp.provider_product_id=pp.id and rp.status='active' and r.status in ('active','seasonal')
    );

  return jsonb_build_object(
    'available',true,
    'organization_id',v_org,
    'pairs',v_pairs,
    'unassigned_products',v_unassigned,
    'hard_stop_count',(select count(*) from jsonb_array_elements(v_pairs) e where e->>'decision_state'='hard_stop'),
    'unresolved_count',(select count(*) from jsonb_array_elements(v_pairs) e where e->>'decision_state' like 'unresolved%'),
    'contract',jsonb_build_object(
      'absence_of_rule_means','unresolved',
      'evaluate_only_operator_declared_rig_product_assignments',true,
      'prefer_operator_fluid_route_evidence_when_available',true,
      'whole_system_compatibility_requires_complete_relevant_path_evidence',true,
      'do_not_generalize_component_rule_to_entire_rig',true,
      'unresolved_operator_product_identity_means','research_required_not_approval'
    )
  );
end;
$$;

comment on function public.scout_update_provider_rig_cleaning_setup(uuid,jsonb) is 'Processes nested operator rig fluid_routes and products after core rig/equipment setup. Unknown product names are preserved without guessing; route mapping may remain incomplete.';
