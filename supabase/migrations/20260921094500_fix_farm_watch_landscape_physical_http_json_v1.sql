begin;

create or replace function farm_watch.farm_watch_refresh_landscape_physical_v1_internal(
  p_slug text default 'validation-property-01'
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'farm_watch', 'vault', 'extensions'
as $$
declare
  v_token text;
  v_response extensions.http_response;
begin
  if p_slug is null
     or length(p_slug) > 80
     or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;

  select s.decrypted_secret
  into v_token
  from vault.decrypted_secrets s
  where s.name='farm_watch_materialization_worker_v1'
  limit 1;

  if v_token is null or length(v_token) < 32 then
    raise exception 'Farm Watch materialization worker credential unavailable';
  end if;

  select *
  into v_response
  from extensions.http_post(
    'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-land',
    jsonb_build_object(
      'worker_token', v_token,
      'property', p_slug
    )::text,
    'application/json'
  );

  if v_response.status < 200 or v_response.status >= 300 then
    raise exception 'Farm Watch landscape physical refresh returned HTTP %', v_response.status;
  end if;

  return jsonb_build_object(
    'property', p_slug,
    'http_status', v_response.status,
    'content_type', v_response.content_type
  );
end;
$$;

revoke all on function farm_watch.farm_watch_refresh_landscape_physical_v1_internal(text)
from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_refresh_landscape_physical_v1_internal(text)
to service_role;

commit;
