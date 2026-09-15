-- Match Scout's internal-table privacy posture for the responsible-party subsystem.
-- Service-role and SECURITY DEFINER workers retain their existing access; no public,
-- anon, or authenticated policies are introduced.

alter table research.responsible_party_source_profiles enable row level security;
alter table research.responsible_party_resolution_jobs enable row level security;
alter table research.responsible_party_resolution_job_candidates enable row level security;
alter table research.responsible_party_resolution_deferrals enable row level security;
alter table scout.opportunity_responsible_party_evidence enable row level security;

do $$
declare v_missing text[];
begin
  select array_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname)
  into v_missing
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname,c.relname) in (
    ('research','responsible_party_source_profiles'),
    ('research','responsible_party_resolution_jobs'),
    ('research','responsible_party_resolution_job_candidates'),
    ('research','responsible_party_resolution_deferrals'),
    ('scout','opportunity_responsible_party_evidence')
  )
  and not c.relrowsecurity;

  if cardinality(coalesce(v_missing,'{}'::text[]))>0 then
    raise exception 'responsible-party tables without RLS: %',array_to_string(v_missing,', ');
  end if;
end
$$;
