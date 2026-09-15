-- Do not let high-priority candidates already attached to responsible-party jobs
-- monopolize every seed pass. Existing jobs own retry/requery lifecycle. The
-- seeders should advance to unlinked candidates, while allowing an exhausted job
-- back into selection only when its requery window is due.
--
-- This is especially important for completed person/household property owners:
-- they remain intentionally unresolved for buyer purposes and must not trigger
-- repeated parcel-owner lookups every hour.

do $$
declare
  v_def text;
  v_old text := E'      and coalesce(s.global_suppressed,false)=false\n    order by q.priority desc,q.candidate_key\n    limit p_limit';
  v_new text := E'      and coalesce(s.global_suppressed,false)=false\n      and not exists (\n        select 1\n        from research.responsible_party_resolution_job_candidates l\n        join research.responsible_party_resolution_jobs j on j.id=l.job_id\n        where l.candidate_key=q.candidate_key\n          and j.profile_key=p.profile_key\n          and not (j.state=''exhausted'' and j.requery_after<=now())\n      )\n    order by q.priority desc,q.candidate_key\n    limit p_limit';
begin
  select pg_get_functiondef('public.internal_seed_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
  into v_def;
  if v_def not like '%'||v_old||'%' then
    raise exception 'local responsible-party seed cursor patch did not match function definition';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end
$$;

do $$
declare
  v_def text;
  v_old text := E'    and s.location is not null\n    and coalesce(s.global_suppressed,false)=false\n  order by q.priority desc,q.candidate_key\n  limit p_limit';
  v_new text := E'    and s.location is not null\n    and coalesce(s.global_suppressed,false)=false\n    and not exists (\n      select 1\n      from research.responsible_party_resolution_job_candidates l\n      join research.responsible_party_resolution_jobs j on j.id=l.job_id\n      where l.candidate_key=q.candidate_key\n        and j.profile_key=p.profile_key\n        and not (j.state=''exhausted'' and j.requery_after<=now())\n    )\n  order by q.priority desc,q.candidate_key\n  limit p_limit';
begin
  select pg_get_functiondef('public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
  into v_def;
  if v_def not like '%'||v_old||'%' then
    raise exception 'remote responsible-party seed cursor patch did not match function definition';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end
$$;

do $$
declare v_local text; v_remote text;
begin
  select pg_get_functiondef('public.internal_seed_responsible_party_resolution_jobs_v1(integer)'::regprocedure) into v_local;
  select pg_get_functiondef('public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer)'::regprocedure) into v_remote;
  if v_local not like '%responsible_party_resolution_job_candidates l%j.profile_key=p.profile_key%'
     or v_remote not like '%responsible_party_resolution_job_candidates l%j.profile_key=p.profile_key%' then
    raise exception 'responsible-party seed cursor guard regression';
  end if;
end
$$;
