-- Give documented property-manager contact research bounded throughput independent
-- of the general buyer-research backlog.

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname='scout-manager-contact-evidence-worker';

  if v_jobid is null then
    perform cron.schedule(
      'scout-manager-contact-evidence-worker',
      '14,44 * * * *',
      $cron$select ingest.invoke_edge_collector('collect-buyer-document-evidence','{"limit":2,"claim_scope":"manager_contact"}'::jsonb);$cron$
    );
  else
    perform cron.alter_job(
      v_jobid,
      schedule := '14,44 * * * *',
      command := $cron$select ingest.invoke_edge_collector('collect-buyer-document-evidence','{"limit":2,"claim_scope":"manager_contact"}'::jsonb);$cron$,
      active := true
    );
  end if;
end
$$;