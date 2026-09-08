-- Scout USAspending physical-FM parent target snapshot v2
-- Avoids recomputing the regex-heavy research classifier inside the live collector RPC.

create table if not exists research.usaspending_physical_fm_parent_idv_targets (
  parent_piid text primary key,
  program_key text not null,
  program_title text not null,
  program_scope_class text,
  site_scope_status text,
  has_surface_work_scope boolean not null default false,
  fpds_agency_code text,
  parent_generated_award_id text,
  identifier_resolution text not null,
  refreshed_at timestamptz not null default now()
);

comment on table research.usaspending_physical_fm_parent_idv_targets is
  'Internal snapshot of parent IDVs already qualified by the physical-FM research classifier. Live collectors read this table; classification refresh is separate and may be more expensive.';

create or replace function public.internal_refresh_usaspending_physical_fm_parent_idvs()
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
  create temporary table _scout_parent_targets on commit drop as
  select
    v.parent_piid,
    v.program_key,
    v.program_title,
    v.program_scope_class,
    v.site_scope_status,
    coalesce(v.has_surface_work_scope,false) as has_surface_work_scope,
    v.fpds_agency_code,
    v.parent_generated_award_id,
    v.identifier_resolution
  from research.v_usaspending_physical_fm_parent_idv_targets v
  where nullif(btrim(v.parent_piid),'') is not null;

  if not exists(select 1 from _scout_parent_targets) then
    raise exception 'Physical-FM parent target refresh produced zero rows';
  end if;

  delete from research.usaspending_physical_fm_parent_idv_targets t
  where not exists(select 1 from _scout_parent_targets s where s.parent_piid=t.parent_piid);

  insert into research.usaspending_physical_fm_parent_idv_targets(
    parent_piid,program_key,program_title,program_scope_class,site_scope_status,
    has_surface_work_scope,fpds_agency_code,parent_generated_award_id,
    identifier_resolution,refreshed_at
  )
  select
    s.parent_piid,s.program_key,s.program_title,s.program_scope_class,s.site_scope_status,
    s.has_surface_work_scope,s.fpds_agency_code,s.parent_generated_award_id,
    s.identifier_resolution,v_refreshed_at
  from _scout_parent_targets s
  on conflict(parent_piid) do update set
    program_key=excluded.program_key,
    program_title=excluded.program_title,
    program_scope_class=excluded.program_scope_class,
    site_scope_status=excluded.site_scope_status,
    has_surface_work_scope=excluded.has_surface_work_scope,
    fpds_agency_code=excluded.fpds_agency_code,
    parent_generated_award_id=excluded.parent_generated_award_id,
    identifier_resolution=excluded.identifier_resolution,
    refreshed_at=excluded.refreshed_at;

  select count(*) into v_count from research.usaspending_physical_fm_parent_idv_targets;
  return jsonb_build_object('targets',v_count,'refreshed_at',v_refreshed_at);
end;
$$;

revoke all on function public.internal_refresh_usaspending_physical_fm_parent_idvs() from public,anon,authenticated;
grant execute on function public.internal_refresh_usaspending_physical_fm_parent_idvs() to service_role;

-- Prime the snapshot during migration with a longer administrative DDL window.
select public.internal_refresh_usaspending_physical_fm_parent_idvs();

create or replace function public.internal_get_usaspending_physical_fm_parent_idvs()
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
    'target_refreshed_at',v.refreshed_at
  ) order by v.program_title,v.parent_piid),'[]'::jsonb)
  from research.usaspending_physical_fm_parent_idv_targets v;
$$;

revoke all on function public.internal_get_usaspending_physical_fm_parent_idvs() from public,anon,authenticated;
grant execute on function public.internal_get_usaspending_physical_fm_parent_idvs() to service_role;

revoke all on research.usaspending_physical_fm_parent_idv_targets from anon,authenticated;
grant select,insert,update,delete on research.usaspending_physical_fm_parent_idv_targets to service_role;
