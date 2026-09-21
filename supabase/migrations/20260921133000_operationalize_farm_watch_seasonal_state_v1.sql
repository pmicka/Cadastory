begin;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname='farm-watch-seasonal-state-pilot-v1'
  ) then
    perform cron.unschedule('farm-watch-seasonal-state-pilot-v1');
  end if;

  perform cron.schedule(
    'farm-watch-seasonal-state-pilot-v1',
    '5 14 * * *',
    $cron$
      select farm_watch.farm_watch_refresh_seasonal_state_v1_internal(
        'validation-property-01',
        current_date
      );
    $cron$
  );
end;
$$;

commit;
