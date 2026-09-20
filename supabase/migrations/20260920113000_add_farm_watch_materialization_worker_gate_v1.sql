do $$
begin
  if not exists (
    select 1 from vault.secrets where name='farm_watch_materialization_worker_v1'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'farm_watch_materialization_worker_v1',
      'Internal service gate for Farm Watch materialization worker requests'
    );
  end if;
end;
$$;

create or replace function farm_watch.farm_watch_validate_materialization_worker_v1_internal(
  p_token text
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog,vault
as $$
  select exists (
    select 1
    from vault.decrypted_secrets s
    where s.name='farm_watch_materialization_worker_v1'
      and p_token is not null
      and length(p_token) >= 32
      and s.decrypted_secret = p_token
  );
$$;

revoke all on function farm_watch.farm_watch_validate_materialization_worker_v1_internal(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_validate_materialization_worker_v1_internal(text)
  to postgres,service_role;

create or replace function public.farm_watch_validate_materialization_worker_v1_internal(
  p_token text
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_validate_materialization_worker_v1_internal(p_token);
$$;

revoke all on function public.farm_watch_validate_materialization_worker_v1_internal(text)
  from public,anon,authenticated;
grant execute on function public.farm_watch_validate_materialization_worker_v1_internal(text)
  to postgres,service_role;
