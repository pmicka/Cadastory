-- Add documented-manager contact research to the existing hourly evidence seed cadence.

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname='scout-buyer-document-evidence-seed-hourly';

  if v_jobid is null then
    raise exception 'scout-buyer-document-evidence-seed-hourly cron job not found';
  end if;

  perform cron.alter_job(
    v_jobid,
    command := 'select research.seed_buyer_document_evidence_jobs_cron_v4(250,50);'
  );
end
$$;
