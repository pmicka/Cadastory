-- Enable the autonomous buyer evidence collector to use Tavily keyless search
-- when no project API key is stored. A Vault key remains the preferred override.
-- Keyless mode was verified from the production Supabase runtime before rollout.

create or replace function public.internal_get_buyer_research_provider_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select nullif(decrypted_secret,'')
  into v_key
  from vault.decrypted_secrets
  where name='scout_buyer_research_tavily_api_key'
  order by updated_at desc
  limit 1;

  return jsonb_build_object(
    'provider','tavily',
    'search_available',true,
    'mode',case when v_key is null then 'keyless' else 'api_key' end,
    'configured',v_key is not null,
    'api_key',v_key
  );
end
$$;

revoke all on function public.internal_get_buyer_research_provider_v1() from public, anon, authenticated;
grant execute on function public.internal_get_buyer_research_provider_v1() to service_role;

-- Run twice per hour. Batches are deliberately small so provider limits and
-- source-site latency cannot turn the worker into another long-running cron lane.
select cron.unschedule('scout-buyer-document-evidence-worker')
where exists(select 1 from cron.job where jobname='scout-buyer-document-evidence-worker');

select cron.schedule(
  'scout-buyer-document-evidence-worker',
  '4,34 * * * *',
  $$select ingest.invoke_edge_collector('collect-buyer-document-evidence','{"limit":4}'::jsonb);$$
);
