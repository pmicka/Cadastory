begin;

create table if not exists farm_watch.mast_survey_publication_watch_v1 (
  survey_year smallint primary key check (survey_year between 2007 and 2100),
  status text not null
    check (status in ('not_published','published_pending_ingest','ingested')),
  index_url text not null,
  index_sha256 text not null check (index_sha256 ~ '^[0-9a-f]{64}$'),
  discovered_report_url text,
  first_discovered_at timestamptz,
  last_checked_at timestamptz not null,
  canonical_report_present boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status='not_published' and discovered_report_url is null and first_discovered_at is null)
    or
    (status in ('published_pending_ingest','ingested') and discovered_report_url is not null and first_discovered_at is not null)
  )
);

alter table farm_watch.mast_survey_publication_watch_v1 enable row level security;
revoke all on farm_watch.mast_survey_publication_watch_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.mast_survey_publication_watch_v1 to service_role;

create or replace function farm_watch.farm_watch_record_mast_survey_publication_watch_v1_internal(
  p_survey_year integer,
  p_index_url text,
  p_index_sha256 text,
  p_discovered_report_url text,
  p_checked_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_canonical_url text;
  v_status text;
  v_first_discovered_at timestamptz;
begin
  if p_survey_year is null or p_survey_year < 2007 or p_survey_year > 2100 then
    raise exception 'invalid mast survey year';
  end if;
  if p_index_url is null or p_index_url !~ '^https://fw\.ky\.gov/' then
    raise exception 'invalid KDFWR mast survey index URL';
  end if;
  if p_index_sha256 is null or p_index_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid KDFWR mast survey index hash';
  end if;
  if p_discovered_report_url is not null
     and p_discovered_report_url !~ '^https://fw\.ky\.gov/.*\.pdf([?].*)?$' then
    raise exception 'invalid KDFWR mast survey report URL';
  end if;
  if p_checked_at is null then
    raise exception 'mast publication checked_at is required';
  end if;

  select r.report_url
  into v_canonical_url
  from farm_watch.mast_survey_reports_v1 r
  where r.survey_year=p_survey_year
  limit 1;

  if v_canonical_url is not null then
    v_status := 'ingested';
  elsif p_discovered_report_url is not null then
    v_status := 'published_pending_ingest';
  else
    v_status := 'not_published';
  end if;

  select w.first_discovered_at
  into v_first_discovered_at
  from farm_watch.mast_survey_publication_watch_v1 w
  where w.survey_year=p_survey_year;

  if p_discovered_report_url is not null and v_first_discovered_at is null then
    v_first_discovered_at := p_checked_at;
  end if;

  insert into farm_watch.mast_survey_publication_watch_v1(
    survey_year,status,index_url,index_sha256,discovered_report_url,
    first_discovered_at,last_checked_at,canonical_report_present,updated_at
  ) values (
    p_survey_year,v_status,p_index_url,p_index_sha256,
    coalesce(p_discovered_report_url,v_canonical_url),
    v_first_discovered_at,
    p_checked_at,
    v_canonical_url is not null,
    now()
  )
  on conflict(survey_year) do update set
    status=excluded.status,
    index_url=excluded.index_url,
    index_sha256=excluded.index_sha256,
    discovered_report_url=excluded.discovered_report_url,
    first_discovered_at=excluded.first_discovered_at,
    last_checked_at=excluded.last_checked_at,
    canonical_report_present=excluded.canonical_report_present,
    updated_at=now();

  return jsonb_build_object(
    'survey_year',p_survey_year,
    'status',v_status,
    'index_url',p_index_url,
    'index_sha256',p_index_sha256,
    'report_url',coalesce(p_discovered_report_url,v_canonical_url),
    'first_discovered_at',v_first_discovered_at,
    'last_checked_at',p_checked_at,
    'canonical_report_present',v_canonical_url is not null
  );
end;
$$;

revoke all on function farm_watch.farm_watch_record_mast_survey_publication_watch_v1_internal(
  integer,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_record_mast_survey_publication_watch_v1_internal(
  integer,text,text,text,timestamptz
) to service_role;

create or replace function public.farm_watch_record_mast_survey_publication_watch_v1_internal(
  p_survey_year integer,
  p_index_url text,
  p_index_sha256 text,
  p_discovered_report_url text,
  p_checked_at timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_record_mast_survey_publication_watch_v1_internal(
    p_survey_year,p_index_url,p_index_sha256,p_discovered_report_url,p_checked_at
  );
$$;

revoke all on function public.farm_watch_record_mast_survey_publication_watch_v1_internal(
  integer,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.farm_watch_record_mast_survey_publication_watch_v1_internal(
  integer,text,text,text,timestamptz
) to service_role;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-farm-watch-mast-publication',true,true,now())
on conflict(slug) do update set
  enabled=excluded.enabled,
  allow_dispatch=excluded.allow_dispatch,
  updated_at=excluded.updated_at;

do $$
begin
  if exists(
    select 1 from cron.job where jobname='farm-watch-mast-publication-daily-seasonal-v1'
  ) then
    perform cron.unschedule('farm-watch-mast-publication-daily-seasonal-v1');
  end if;

  perform cron.schedule(
    'farm-watch-mast-publication-daily-seasonal-v1',
    '20 14 * 9-11 *',
    $cron$
      select ingest.invoke_edge_collector(
        'collect-farm-watch-mast-publication',
        jsonb_build_object(
          'survey_year',extract(year from current_date)::integer
        )
      );
    $cron$
  );

  if exists(
    select 1 from cron.job where jobname='farm-watch-mast-resource-context-pilot-v1'
  ) then
    perform cron.unschedule('farm-watch-mast-resource-context-pilot-v1');
  end if;

  perform cron.schedule(
    'farm-watch-mast-resource-context-pilot-v1',
    '35 14 * 9-11 *',
    $cron$
      select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
        'validation-property-01',
        extract(year from current_date)::integer
      );
    $cron$
  );
end;
$$;

comment on table farm_watch.mast_survey_publication_watch_v1 is
'Seasonal KDFWR mast-report publication monitor. Polls the authoritative report index daily September-November and is dormant December-August; discovery does not imply canonical report values have been ingested.';

commit;
