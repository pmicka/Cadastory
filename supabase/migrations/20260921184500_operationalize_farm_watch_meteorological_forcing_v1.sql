begin;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-farm-watch-meteorology',true,true,now())
on conflict(slug) do update set
  enabled=excluded.enabled,
  allow_dispatch=excluded.allow_dispatch,
  updated_at=excluded.updated_at;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname='farm-watch-meteorological-forcing-hourly-v1'
  ) then
    perform cron.unschedule('farm-watch-meteorological-forcing-hourly-v1');
  end if;

  perform cron.schedule(
    'farm-watch-meteorological-forcing-hourly-v1',
    '50 * * * *',
    $cron$
      select ingest.invoke_edge_collector(
        'collect-farm-watch-meteorology',
        jsonb_build_object(
          'property','validation-property-01',
          'limit',1,
          'lookback_hours',8
        )
      );
    $cron$
  );
end;
$$;

commit;
