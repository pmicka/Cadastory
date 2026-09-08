-- Scout USAspending parent-IDV identifier resolution v3
-- Army IDV generated keys are deterministic in the currently verified corpus.
-- Navy identifiers must be resolved from USAspending exact-PIID search rather than guessed.

create or replace view research.v_usaspending_physical_fm_parent_idv_targets as
with expanded as (
  select
    p.program_key,
    p.program_title,
    p.buyer_name,
    p.buyer_subtier,
    p.buyer_office,
    p.program_scope_class,
    p.site_scope_status,
    p.has_surface_work_scope,
    unnest(p.award_numbers) as parent_piid
  from research.v_physical_fm_program_families p
), coded as (
  select
    e.*,
    case
      when upper(coalesce(e.buyer_subtier,'')) like '%ARMY%' then '9700'
      when upper(coalesce(e.buyer_name,'')) like '%DEFENSE%' and e.parent_piid like 'W%' then '9700'
      else null
    end as fpds_agency_code
  from expanded e
)
select
  c.*,
  case
    when c.fpds_agency_code is not null then 'CONT_IDV_' || c.parent_piid || '_' || c.fpds_agency_code
    else null
  end as parent_generated_award_id,
  case
    when c.fpds_agency_code is not null then 'deterministic_verified_dod_army_idv_key'
    else 'usaspending_exact_piid_search_required'
  end as identifier_resolution,
  false as child_propagation_authorized
from coded c;

comment on view research.v_usaspending_physical_fm_parent_idv_targets is
  'Research-only qualified parent-IDV targets. Army generated IDs use a verified deterministic convention. Other agencies, including Navy, remain unresolved until USAspending exact-PIID search returns and award-detail verification confirms the generated ID.';

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
    s.parent_piid,
    s.program_key,
    s.program_title,
    s.program_scope_class,
    s.site_scope_status,
    s.has_surface_work_scope,
    s.fpds_agency_code,
    case
      when old.identifier_resolution = 'usaspending_exact_piid_search_verified'
        then old.parent_generated_award_id
      else s.parent_generated_award_id
    end,
    case
      when old.identifier_resolution = 'usaspending_exact_piid_search_verified'
        then old.identifier_resolution
      else s.identifier_resolution
    end,
    v_refreshed_at
  from _scout_parent_targets s
  left join research.usaspending_physical_fm_parent_idv_targets old
    on old.parent_piid=s.parent_piid
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
  return jsonb_build_object(
    'targets',v_count,
    'verified_exact_piid_ids',(select count(*) from research.usaspending_physical_fm_parent_idv_targets where identifier_resolution='usaspending_exact_piid_search_verified'),
    'still_unresolved',(select count(*) from research.usaspending_physical_fm_parent_idv_targets where parent_generated_award_id is null),
    'refreshed_at',v_refreshed_at
  );
end;
$$;

create or replace function public.internal_set_usaspending_parent_idv_identifier(
  p_parent_piid text,
  p_generated_award_id text,
  p_resolved_award_piid text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row research.usaspending_physical_fm_parent_idv_targets%rowtype;
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

  update research.usaspending_physical_fm_parent_idv_targets
  set parent_generated_award_id=btrim(p_generated_award_id),
      identifier_resolution='usaspending_exact_piid_search_verified',
      refreshed_at=now()
  where upper(parent_piid)=upper(btrim(p_parent_piid))
  returning * into v_row;

  if v_row.parent_piid is null then
    raise exception 'Parent PIID is not in the qualified physical-FM target snapshot';
  end if;

  return jsonb_build_object(
    'parent_piid',v_row.parent_piid,
    'parent_generated_award_id',v_row.parent_generated_award_id,
    'identifier_resolution',v_row.identifier_resolution,
    'refreshed_at',v_row.refreshed_at
  );
end;
$$;

revoke all on function public.internal_set_usaspending_parent_idv_identifier(text,text,text) from public,anon,authenticated;
grant execute on function public.internal_set_usaspending_parent_idv_identifier(text,text,text) to service_role;

create or replace view research.v_usaspending_parent_idv_identifier_queue as
select
  parent_piid,program_key,program_title,program_scope_class,site_scope_status,
  parent_generated_award_id,identifier_resolution,refreshed_at
from research.usaspending_physical_fm_parent_idv_targets
where parent_generated_award_id is null
   or identifier_resolution='usaspending_exact_piid_search_required';

comment on view research.v_usaspending_parent_idv_identifier_queue is
  'Research-only parent IDVs requiring exact PIID resolution against USAspending before child-award collection.';

revoke all on research.v_usaspending_parent_idv_identifier_queue from anon,authenticated;
grant select on research.v_usaspending_parent_idv_identifier_queue to service_role;

select public.internal_refresh_usaspending_physical_fm_parent_idvs();
