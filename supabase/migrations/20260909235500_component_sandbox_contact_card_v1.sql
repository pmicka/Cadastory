create or replace function public.scout_get_component_sandbox_map_targets_v3_internal(
  p_property_limit integer default 12,
  p_group_limit integer default 14
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public','extensions'
as $function$
with base_doc as (
  select public.scout_get_component_sandbox_map_targets_v2_internal(
    p_property_limit,
    p_group_limit
  ) as doc
),
base_rows as (
  select value as item
  from base_doc
  cross join lateral jsonb_array_elements(coalesce(doc,'[]'::jsonb))
),
resolved as (
  select
    b.item,
    case
      when b.item->>'kind' = 'group'
       and split_part(b.item->>'key',':',2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then split_part(b.item->>'key',':',2)::uuid
      else null::uuid
    end as organization_id,
    case
      when b.item->>'kind' = 'property'
       and split_part(b.item->>'key',':',1) = 'premium'
       and split_part(b.item->>'key',':',2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then split_part(b.item->>'key',':',2)::uuid
      else null::uuid
    end as premium_target_id
  from base_rows b
),
with_subject as (
  select
    r.*,
    p.operator_name,
    p.website_url,
    coalesce(p.property_address,p.address_text) as property_address,
    p.target_class,
    p.target_subclass
  from resolved r
  left join intelligence.premium_exterior_targets p
    on p.id = r.premium_target_id
),
with_routes as (
  select
    s.*,
    coalesce(routes.routes,'[]'::jsonb) as routes
  from with_subject s
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'key',c.contact_point_id::text,
        'channel_type',c.channel_type,
        'value',c.contact_value,
        'label',c.label,
        'scope',c.contact_scope,
        'department',c.department_name,
        'stability_class',c.stability_class,
        'confidence',c.confidence,
        'verify_after',c.verify_after,
        'is_primary',c.is_primary,
        'inherited',c.inherited,
        'routing_note',c.routing_note,
        'source_authority',c.source_authority,
        'source_url',c.source_url
      ) order by c.route_order
    ) as routes
    from (
      select
        ec.*,
        row_number() over (
          order by
            ec.is_primary desc nulls last,
            case ec.contact_scope
              when 'supplier_registration' then 1
              when 'procurement' then 2
              when 'facility_operations' then 3
              when 'engineering' then 4
              when 'administrative' then 5
              when 'general_switchboard' then 8
              else 6
            end,
            case ec.stability_class
              when 'institutional' then 1
              when 'departmental' then 2
              when 'role_holder' then 3
              else 4
            end,
            ec.confidence desc nulls last,
            ec.contact_point_id
        ) as route_order
      from core.v_organization_effective_contacts ec
      where ec.organization_id = s.organization_id
      limit 3
    ) c
  ) routes on true
),
carded as (
  select
    w.item || jsonb_build_object(
      'contact_card',
      jsonb_build_object(
        'lead_key',w.item->>'key',
        'subject_name',w.item->>'label',
        'organization_name',case
          when w.item->>'kind' = 'group' then w.item->>'label'
          else nullif(w.operator_name,'')
        end,
        'organization_type',case
          when w.item->>'kind' = 'group' then nullif(w.item->>'portfolio_archetype','')
          else coalesce(nullif(w.target_subclass,''),nullif(w.target_class,''))
        end,
        'site_name',case when w.item->>'kind' = 'property' then w.item->>'label' else null end,
        'address',w.property_address,
        'website_url',w.website_url,
        'role_label',null,
        'resolution_status',case
          when w.organization_id is not null and jsonb_array_length(w.routes) > 0 then 'organization_resolved'
          when w.organization_id is not null then 'organization_resolved_no_route'
          when nullif(w.operator_name,'') is not null then 'named_responsibility'
          else 'lead_identified'
        end,
        'enrichment_status',case
          when jsonb_array_length(w.routes) >= 2 then 'enriched'
          when jsonb_array_length(w.routes) = 1 then 'partial'
          when nullif(w.operator_name,'') is not null or nullif(w.website_url,'') is not null then 'partial'
          else 'none'
        end,
        'routes',w.routes,
        'route_count',jsonb_array_length(w.routes),
        'research_note',case
          when jsonb_array_length(w.routes) = 0 then 'No verified contact route is attached yet; keep the lead and continue contact enrichment.'
          else null
        end
      )
    ) as item
  from with_routes w
)
select coalesce(jsonb_agg(item order by item->>'kind',item->>'key'),'[]'::jsonb)
from carded;
$function$;

revoke all on function public.scout_get_component_sandbox_map_targets_v3_internal(integer,integer) from public;
revoke all on function public.scout_get_component_sandbox_map_targets_v3_internal(integer,integer) from anon;
revoke all on function public.scout_get_component_sandbox_map_targets_v3_internal(integer,integer) from authenticated;
grant execute on function public.scout_get_component_sandbox_map_targets_v3_internal(integer,integer) to service_role;
