-- Scout unified USAspending parent-vehicle target snapshot v1
-- Generalizes the live target set beyond physical-FM to include awarded parent vehicles
-- already proven by SAM child notices to generate KY/IN/OH physical-asset work.
-- Existing physical-FM RPC names remain compatibility aliases for deployed collectors.

create table if not exists research.usaspending_parent_vehicle_targets (
  parent_piid text primary key,
  program_key text not null,
  program_title text not null,
  program_scope_class text,
  site_scope_status text,
  has_surface_work_scope boolean not null default false,
  fpds_agency_code text,
  parent_generated_award_id text,
  identifier_resolution text not null,
  target_reasons text[] not null default '{}'::text[],
  regional_supported_states text[],
  local_child_notice_count bigint not null default 0,
  refreshed_at timestamptz not null default now()
);

comment on table research.usaspending_parent_vehicle_targets is
  'Internal collector snapshot for qualified USAspending parent IDVs. Sources currently include physical-FM award families and parent vehicles with supported-area KY/IN/OH child-work evidence. Collection is evidence enrichment only.';

create or replace view research.v_usaspending_parent_vehicle_targets as
with source_rows as (
  select
    p.parent_piid,
    p.program_key,
    p.program_title,
    p.program_scope_class,
    p.site_scope_status,
    coalesce(p.has_surface_work_scope,false) as has_surface_work_scope,
    p.fpds_agency_code,
    p.parent_generated_award_id,
    p.identifier_resolution,
    'physical_fm_award_family'::text as target_reason,
    null::text[] as regional_supported_states,
    0::bigint as local_child_notice_count
  from research.v_usaspending_physical_fm_parent_idv_targets p

  union all

  select
    r.parent_piid,
    r.program_key,
    r.program_title,
    r.program_scope_class,
    r.site_scope_status,
    coalesce(r.has_surface_work_scope,false),
    r.fpds_agency_code,
    r.parent_generated_award_id,
    r.identifier_resolution,
    'regional_local_child_work_proven'::text,
    r.supported_states,
    r.local_child_notice_count
  from research.v_usaspending_regional_parent_vehicle_targets r
), grouped as (
  select
    s.parent_piid,
    md5('qualified-parent-vehicle:' || s.parent_piid) as program_key,
    max(s.program_title) as program_title,
    case
      when count(distinct s.target_reason) > 1 then 'multi_reason_parent_vehicle'
      else max(s.program_scope_class)
    end as program_scope_class,
    case
      when bool_or(s.target_reason='regional_local_child_work_proven') then 'local_child_work_proven'
      else max(s.site_scope_status)
    end as site_scope_status,
    bool_or(s.has_surface_work_scope) as has_surface_work_scope,
    max(s.fpds_agency_code) filter(where s.fpds_agency_code is not null) as fpds_agency_code,
    max(s.parent_generated_award_id) filter(where s.parent_generated_award_id is not null) as parent_generated_award_id,
    case
      when bool_or(s.identifier_resolution='usaspending_exact_piid_search_verified') then 'usaspending_exact_piid_search_verified'
      when bool_or(s.identifier_resolution='already_collected_verified') then 'already_collected_verified'
      when bool_or(s.identifier_resolution='deterministic_verified_dod_army_idv_key') then 'deterministic_verified_dod_army_idv_key'
      else 'usaspending_exact_piid_search_required'
    end as identifier_resolution,
    array_agg(distinct s.target_reason order by s.target_reason) as target_reasons,
    case
      when bool_or(s.regional_supported_states is not null)
      then array(
        select distinct x
        from unnest(array_cat_agg(coalesce(s.regional_supported_states,'{}'::text[]))) x
        where x is not null
        order by x
      )
      else null::text[]
    end as regional_supported_states,
    sum(s.local_child_notice_count) as local_child_notice_count
  from source_rows s
  where nullif(btrim(s.parent_piid),'') is not null
  group by s.parent_piid
)
select * from grouped;

comment on view research.v_usaspending_parent_vehicle_targets is
  'Research-only union of qualified USAspending parent-IDV targets. Regional inclusion requires explicit supported-area child-work evidence; prospective solicitations/RFIs are not included until awarded parent PIIDs exist.';

create or replace function public.internal_refresh_usaspending_parent_vehicle_targets()
returns jsonb
language plpgsql
security definer
set search_path=''
set statement_timeout='60s'
as $$
declare
  v_count integer;
  v_refreshed_at timestamptz := now();
begin
  create temporary table _scout_parent_vehicle_targets on commit drop as
  select * from research.v_usaspending_parent_vehicle_targets;

  if not exists(select 1 from _scout_parent_vehicle_targets) then
    raise exception 'Unified parent-vehicle target refresh produced zero rows';
  end if;

  delete from research.usaspending_parent_vehicle_targets t
  where not exists(
    select 1 from _scout_parent_vehicle_targets s where upper(s.parent_piid)=upper(t.parent_piid)
  );

  insert into research.usaspending_parent_vehicle_targets(
    parent_piid,program_key,program_title,program_scope_class,site_scope_status,
    has_surface_work_scope,fpds_agency_code,parent_generated_award_id,
    identifier_resolution,target_reasons,regional_supported_states,
    local_child_notice_count,refreshed_at
  )
  select
    s.parent_piid,
    s.program_key,
    s.program_title,
    s.program_scope_class,
    s.site_scope_status,
    s.has_surface_work_scope,
    s.fpds_agency_code,
    case
      when old.identifier_resolution='usaspending_exact_piid_search_verified'
        then old.parent_generated_award_id
      when old.parent_generated_award_id is not null and s.parent_generated_award_id is null
        then old.parent_generated_award_id
      else s.parent_generated_award_id
    end,
    case
      when old.identifier_resolution='usaspending_exact_piid_search_verified'
        then old.identifier_resolution
      else s.identifier_resolution
    end,
    s.target_reasons,
    s.regional_supported_states,
    s.local_child_notice_count,
    v_refreshed_at
  from _scout_parent_vehicle_targets s
  left join research.usaspending_parent_vehicle_targets old
    on upper(old.parent_piid)=upper(s.parent_piid)
  on conflict(parent_piid) do update set
    program_key=excluded.program_key,
    program_title=excluded.program_title,
    program_scope_class=excluded.program_scope_class,
    site_scope_status=excluded.site_scope_status,
    has_surface_work_scope=excluded.has_surface_work_scope,
    fpds_agency_code=excluded.fpds_agency_code,
    parent_generated_award_id=excluded.parent_generated_award_id,
    identifier_resolution=excluded.identifier_resolution,
    target_reasons=excluded.target_reasons,
    regional_supported_states=excluded.regional_supported_states,
    local_child_notice_count=excluded.local_child_notice_count,
    refreshed_at=excluded.refreshed_at;

  select count(*) into v_count from research.usaspending_parent_vehicle_targets;
  return jsonb_build_object(
    'targets',v_count,
    'physical_fm_targets',(select count(*) from research.usaspending_parent_vehicle_targets where target_reasons @> array['physical_fm_award_family']),
    'regional_local_child_targets',(select count(*) from research.usaspending_parent_vehicle_targets where target_reasons @> array['regional_local_child_work_proven']),
    'unresolved_identifiers',(select count(*) from research.usaspending_parent_vehicle_targets where parent_generated_award_id is null),
    'refreshed_at',v_refreshed_at
  );
end;
$$;

create or replace function public.internal_get_usaspending_parent_vehicle_targets()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'program_key',v.program_key,
    'program_title',v.program_title,
    'program_scope_class',v.program_scope_class,
    'site_scope_status',v.site_scope_status,
    'has_surface_work_scope',v.has_surface_work_scope,
    'parent_piid',v.parent_piid,
    'fpds_agency_code',v.fpds_agency_code,
    'parent_generated_award_id',v.parent_generated_award_id,
    'identifier_resolution',v.identifier_resolution,
    'target_reasons',v.target_reasons,
    'regional_supported_states',v.regional_supported_states,
    'local_child_notice_count',v.local_child_notice_count,
    'target_refreshed_at',v.refreshed_at
  ) order by v.program_title,v.parent_piid),'[]'::jsonb)
  from research.usaspending_parent_vehicle_targets v;
$$;

create or replace function public.internal_set_usaspending_parent_vehicle_identifier(
  p_parent_piid text,
  p_generated_award_id text,
  p_resolved_award_piid text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row research.usaspending_parent_vehicle_targets%rowtype;
begin
  if nullif(btrim(p_parent_piid),'') is null
     or nullif(btrim(p_generated_award_id),'') is null
     or nullif(btrim(p_resolved_award_piid),'') is null then
    raise exception 'parent PIID, generated award ID, and resolved award PIID are required';
  end if;
  if upper(btrim(p_parent_piid)) <> upper(btrim(p_resolved_award_piid)) then
    raise exception 'Resolved USAspending award PIID does not equal requested parent PIID';
  end if;
  if p_generated_award_id !~ '^CONT_IDV_' then
    raise exception 'Resolved generated award ID is not an IDV natural key';
  end if;

  update research.usaspending_parent_vehicle_targets
  set parent_generated_award_id=btrim(p_generated_award_id),
      identifier_resolution='usaspending_exact_piid_search_verified',
      refreshed_at=now()
  where upper(parent_piid)=upper(btrim(p_parent_piid))
  returning * into v_row;

  if v_row.parent_piid is null then
    raise exception 'Parent PIID is not in the qualified parent-vehicle target snapshot';
  end if;

  return jsonb_build_object(
    'parent_piid',v_row.parent_piid,
    'parent_generated_award_id',v_row.parent_generated_award_id,
    'identifier_resolution',v_row.identifier_resolution,
    'refreshed_at',v_row.refreshed_at
  );
end;
$$;

-- Compatibility aliases used by the already-deployed physical-FM collectors.
create or replace function public.internal_refresh_usaspending_physical_fm_parent_idvs()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.internal_refresh_usaspending_parent_vehicle_targets();
$$;

create or replace function public.internal_get_usaspending_physical_fm_parent_idvs()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.internal_get_usaspending_parent_vehicle_targets();
$$;

create or replace function public.internal_set_usaspending_parent_idv_identifier(
  p_parent_piid text,
  p_generated_award_id text,
  p_resolved_award_piid text
) returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.internal_set_usaspending_parent_vehicle_identifier(
    p_parent_piid,p_generated_award_id,p_resolved_award_piid
  );
$$;

create or replace view research.v_usaspending_parent_idv_identifier_queue as
select
  parent_piid,program_key,program_title,program_scope_class,site_scope_status,
  parent_generated_award_id,identifier_resolution,target_reasons,
  regional_supported_states,local_child_notice_count,refreshed_at
from research.usaspending_parent_vehicle_targets
where parent_generated_award_id is null
   or identifier_resolution='usaspending_exact_piid_search_required';

comment on view research.v_usaspending_parent_idv_identifier_queue is
  'Research-only unified parent-vehicle identifier queue. Includes physical-FM and regionally proven parent IDVs requiring exact USAspending PIID resolution.';

revoke all on research.usaspending_parent_vehicle_targets from anon,authenticated;
revoke all on research.v_usaspending_parent_vehicle_targets from anon,authenticated;
revoke all on research.v_usaspending_parent_idv_identifier_queue from anon,authenticated;
grant select,insert,update,delete on research.usaspending_parent_vehicle_targets to service_role;
grant select on research.v_usaspending_parent_vehicle_targets to service_role;
grant select on research.v_usaspending_parent_idv_identifier_queue to service_role;

revoke all on function public.internal_refresh_usaspending_parent_vehicle_targets() from public,anon,authenticated;
revoke all on function public.internal_get_usaspending_parent_vehicle_targets() from public,anon,authenticated;
revoke all on function public.internal_set_usaspending_parent_vehicle_identifier(text,text,text) from public,anon,authenticated;
grant execute on function public.internal_refresh_usaspending_parent_vehicle_targets() to service_role;
grant execute on function public.internal_get_usaspending_parent_vehicle_targets() to service_role;
grant execute on function public.internal_set_usaspending_parent_vehicle_identifier(text,text,text) to service_role;

revoke all on function public.internal_refresh_usaspending_physical_fm_parent_idvs() from public,anon,authenticated;
revoke all on function public.internal_get_usaspending_physical_fm_parent_idvs() from public,anon,authenticated;
revoke all on function public.internal_set_usaspending_parent_idv_identifier(text,text,text) from public,anon,authenticated;
grant execute on function public.internal_refresh_usaspending_physical_fm_parent_idvs() to service_role;
grant execute on function public.internal_get_usaspending_physical_fm_parent_idvs() to service_role;
grant execute on function public.internal_set_usaspending_parent_idv_identifier(text,text,text) to service_role;

select public.internal_refresh_usaspending_parent_vehicle_targets();
