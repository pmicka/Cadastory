-- Batch 10: keep high-priority buyer document-evidence work synchronized with
-- the hourly buyer-route refresh without exposing the service-role seed RPC.

create or replace function research.seed_buyer_document_evidence_jobs_cron_v1(p_cluster_limit integer default 250)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;
  if p_cluster_limit < 1 or p_cluster_limit > 1000 then
    raise exception 'p_cluster_limit must be between 1 and 1000';
  end if;

  perform set_config('request.jwt.claim.role','service_role',true);
  return public.internal_seed_buyer_document_evidence_jobs(p_cluster_limit);
end
$function$;

revoke all on function research.seed_buyer_document_evidence_jobs_cron_v1(integer) from public,anon,authenticated,service_role;
grant execute on function research.seed_buyer_document_evidence_jobs_cron_v1(integer) to postgres;

select cron.schedule(
  'scout-buyer-document-evidence-seed-hourly',
  '24 * * * *',
  $$select research.seed_buyer_document_evidence_jobs_cron_v1(250);$$
);