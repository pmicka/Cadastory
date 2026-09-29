begin;

-- Keep the existing inventory/Tier-1 context reader intact, then layer dependency-aware
-- materialization freshness over its products.
alter function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  rename to farm_watch_get_deer_evidence_stack_base_v1_internal;

CREATE OR REPLACE FUNCTION farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_v1(p_base jsonb, p_property_id uuid, p_as_of_date date, p_as_of_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_key text;
  v_product jsonb;
  v_ref jsonb;
  v_materialization jsonb;
  v_products jsonb := '{}'::jsonb;
  v_available integer := 0;
  v_stale integer := 0;
  v_unavailable integer := 0;
  v_status text;
begin
  if p_base is null or p_property_id is null or p_as_of_date is null or p_as_of_at is null then
    return p_base;
  end if;

  for v_key,v_product in
    select key,value
    from jsonb_each(coalesce(p_base->'products','{}'::jsonb))
  loop
    v_ref := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
      p_property_id,v_key,p_as_of_date,p_as_of_at,0
    );
    v_materialization := v_ref->'materialization';
    v_status := coalesce(v_ref->>'status','unavailable');

    v_product := v_product || jsonb_build_object(
      'status',v_status,
      'freshness_contract',coalesce(v_ref->>'freshness_contract','dependency-aware-materialization-v1'),
      'freshness_reason_codes',coalesce(v_ref->'reason_codes','[]'::jsonb)
    );

    if v_materialization is not null and jsonb_typeof(v_materialization)='object' then
      v_product := v_product || jsonb_strip_nulls(jsonb_build_object(
        'algorithm_version',v_materialization->>'algorithm_version',
        'output_schema_version',v_materialization->>'output_schema_version',
        'identity_sha256',v_materialization->>'identity_sha256',
        'evidence_class',v_materialization->>'evidence_class',
        'summary',v_materialization->'summary',
        'source_provenance',v_materialization->'source_provenance',
        'limitations',v_materialization->'limitations',
        'artifact_sha256',v_materialization->>'artifact_sha256',
        'completed_at',v_materialization->>'completed_at',
        'expires_at',v_materialization->>'expires_at'
      ));
    end if;

    v_products := v_products || jsonb_build_object(v_key,v_product);
    if v_status='available' then v_available := v_available + 1;
    elsif v_status='stale' then v_stale := v_stale + 1;
    else v_unavailable := v_unavailable + 1;
    end if;
  end loop;

  return p_base || jsonb_build_object(
    'status',case
      when v_available > 0 then 'available'
      when v_stale > 0 then 'stale'
      else 'unavailable'
    end,
    'as_of_at',p_as_of_at,
    'freshness_contract','dependency-aware-materialization-v1',
    'counts',jsonb_build_object(
      'available',v_available,
      'stale',v_stale,
      'unavailable',v_unavailable
    ),
    'products',v_products,
    'interpretation_boundary',
      'Neutral Farm Watch evidence inventory for UI review. Materialization availability requires the current product contract, current dependency identities, requested date/time alignment where applicable, and ordinary expiration. Availability does not mean a deer relationship is applicable, a coefficient is transferable, or a deer-use prediction has been made.'
  );
end;
$function$


CREATE OR REPLACE FUNCTION farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(p_slug text, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_base jsonb;
  v_property_id uuid;
  v_as_of_at timestamptz;
begin
  v_base := farm_watch.farm_watch_get_deer_evidence_stack_base_v1_internal(
    p_slug,p_as_of_date
  );
  v_property_id := nullif(v_base#>>'{property,id}','')::uuid;
  if v_property_id is null then return v_base; end if;

  v_as_of_at := case
    when p_as_of_date = (now() at time zone 'America/Kentucky/Louisville')::date
      then now()
    else ((p_as_of_date::timestamp + interval '12 hours') at time zone 'America/Kentucky/Louisville')
  end;

  return farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_v1_internal(
    v_base,v_property_id,p_as_of_date,v_as_of_at
  );
end;
$function$


CREATE OR REPLACE FUNCTION farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(p_slug text, p_as_of_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_date date;
  v_base jsonb;
  v_property_id uuid;
begin
  if p_as_of_at is null then raise exception 'evidence-stack as-of timestamp is required'; end if;
  v_date := (p_as_of_at at time zone 'America/Kentucky/Louisville')::date;
  v_base := farm_watch.farm_watch_get_deer_evidence_stack_base_v1_internal(p_slug,v_date);
  v_property_id := nullif(v_base#>>'{property,id}','')::uuid;
  if v_property_id is null then return v_base || jsonb_build_object('as_of_at',p_as_of_at); end if;

  return farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_v1_internal(
    v_base,v_property_id,v_date,p_as_of_at
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.farm_watch_get_deer_evidence_stack_v1_internal(p_slug text, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(p_slug,p_as_of_date);
$function$


CREATE OR REPLACE FUNCTION public.farm_watch_get_deer_evidence_stack_at_v1_internal(p_slug text, p_as_of_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(p_slug,p_as_of_at);
$function$


revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_base_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_base_v1_internal(text,date)
  to service_role;

revoke all on function farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_v1_internal(jsonb,uuid,date,timestamptz)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_v1_internal(jsonb,uuid,date,timestamptz)
  to service_role;

revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  to service_role;

revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz)
  to service_role;

revoke all on function public.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  to service_role;

revoke all on function public.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz)
  to service_role;

comment on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date) is
'Returns the private neutral-evidence inventory with dependency-aware materialization freshness. Current-date reads resolve at current time; historical date-only reads resolve at local noon.';
comment on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz) is
'Returns the private neutral-evidence inventory with exact timestamp-aware dependency freshness for time-bound materializations.';

commit;
