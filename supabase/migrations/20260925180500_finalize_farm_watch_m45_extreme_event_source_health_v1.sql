begin;

create table if not exists intelligence.nws_alert_poll_status_v1 (
  state_code text primary key check (state_code ~ '^[A-Z]{2}$'),
  fetched_at timestamptz not null,
  http_status integer,
  feature_count integer not null default 0 check (feature_count >= 0),
  error_message text,
  updated_at timestamptz not null default now()
);

alter table intelligence.nws_alert_poll_status_v1 enable row level security;
revoke all on intelligence.nws_alert_poll_status_v1 from public,anon,authenticated;
grant select on intelligence.nws_alert_poll_status_v1 to service_role;

create or replace function intelligence.collect_nws_pilot_alerts()
returns jsonb
language plpgsql
security definer
set search_path to 'intelligence','public','extensions'
as $function$
declare
  state_code text;
  req extensions.http_request;
  resp extensions.http_response;
  body jsonb;
  combined jsonb := '[]'::jsonb;
  state_counts jsonb := '{}'::jsonb;
  state_status jsonb := '{}'::jsonb;
  ingest_result jsonb;
  zone_result jsonb;
  refresh_result jsonb;
  cnt integer;
  v_fetched_at timestamptz := now();
  v_error text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','8000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','3000');

  foreach state_code in array array['KY','IN','OH'] loop
    cnt := 0;
    v_error := null;

    begin
      req := row(
        'GET',
        'https://api.weather.gov/alerts/active?area='||state_code,
        array[
          row(
            'User-Agent',
            'Scout-by-Cadastory/1.0 (weather-demand-engine)'
          )::extensions.http_header,
          row(
            'Accept',
            'application/geo+json'
          )::extensions.http_header
        ],
        null,
        null
      )::extensions.http_request;

      resp := extensions.http(req);
      state_status := state_status || jsonb_build_object(state_code,resp.status);

      if resp.status=200 then
        body := resp.content::jsonb;
        cnt := coalesce(
          jsonb_array_length(coalesce(body->'features','[]'::jsonb)),
          0
        );
        state_counts := state_counts || jsonb_build_object(state_code,cnt);
        combined := combined || coalesce(body->'features','[]'::jsonb);
      else
        state_counts := state_counts || jsonb_build_object(state_code,0);
        v_error := 'HTTP '||resp.status::text;
      end if;
    exception when others then
      v_error := sqlerrm;
      state_status :=
        state_status || jsonb_build_object(state_code,'error:'||v_error);
      state_counts :=
        state_counts || jsonb_build_object(state_code,0);
    end;

    insert into intelligence.nws_alert_poll_status_v1(
      state_code,
      fetched_at,
      http_status,
      feature_count,
      error_message,
      updated_at
    ) values (
      state_code,
      v_fetched_at,
      case
        when v_error is null then resp.status
        else null
      end,
      cnt,
      v_error,
      now()
    )
    on conflict(state_code) do update set
      fetched_at=excluded.fetched_at,
      http_status=excluded.http_status,
      feature_count=excluded.feature_count,
      error_message=excluded.error_message,
      updated_at=now();
  end loop;

  ingest_result := intelligence.ingest_nws_alerts(combined);
  zone_result := intelligence.resolve_nws_zone_geometries(150);
  refresh_result := intelligence.refresh_weather_windows();

  return jsonb_build_object(
    'fetched_at',v_fetched_at,
    'state_http_status',state_status,
    'state_feature_counts',state_counts,
    'features_received',jsonb_array_length(combined),
    'ingest',ingest_result,
    'zone_resolution',zone_result,
    'refresh',refresh_result
  );
end
$function$;

create or replace function farm_watch.farm_watch_resolve_extreme_weather_event_context_v2_internal(
  p_slug text,
  p_as_of_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions','intelligence'
as $$
declare
  v_property_id uuid;
  v_state_code text;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_poll intelligence.nws_alert_poll_status_v1%rowtype;
  v_poll_age_seconds double precision;
  v_events jsonb;
  v_count integer;
  v_unresolved_count integer;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
  v_status text;
  v_applicability_state text;
begin
  select p.id,p.state_code,p.boundary
  into v_property_id,v_state_code,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug)
    );
  end if;

  select *
  into v_poll
  from intelligence.nws_alert_poll_status_v1 s
  where s.state_code=v_state_code
  limit 1;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );

  if v_poll.state_code is null then
    v_poll_age_seconds := null;
  else
    v_poll_age_seconds := abs(
      extract(epoch from (p_as_of_at-v_poll.fetched_at))
    );
  end if;

  if
    v_poll.state_code is null
    or v_poll.http_status is distinct from 200
    or v_poll.error_message is not null
    or v_poll_age_seconds > 1800
  then
    v_status := 'unavailable';
    v_applicability_state := 'source_unavailable';
    v_events := '[]'::jsonb;
    v_count := 0;
    v_unresolved_count := 0;
  else
    select count(*)::integer
    into v_unresolved_count
    from intelligence.weather_events e
    where e.source_slug='nws-alerts-api'
      and e.status='Actual'
      and e.event_type = any(array[
        'Hurricane Warning','Hurricane Watch',
        'Tropical Storm Warning','Tropical Storm Watch',
        'Storm Surge Warning','Storm Surge Watch',
        'Extreme Wind Warning'
      ])
      and coalesce(e.onset_at,e.effective_at,e.sent_at) <= p_as_of_at
      and coalesce(
        e.ends_at,
        e.expires_at,
        e.last_observed_at + interval '1 hour'
      ) >= p_as_of_at
      and e.geometry is null
      and exists (
        select 1
        from jsonb_array_elements_text(
          coalesce(
            e.raw_payload#>'{properties,geocode,UGC}',
            '[]'::jsonb
          )
        ) ugc(code)
        where ugc.code like v_state_code||'%'
      );

    if v_unresolved_count > 0 then
      v_status := 'unavailable';
      v_applicability_state := 'source_unavailable';
      v_events := '[]'::jsonb;
      v_count := 0;
    else
      select
        coalesce(
          jsonb_agg(
            jsonb_strip_nulls(
              jsonb_build_object(
                'canonical_key',e.canonical_key,
                'event_type',e.event_type,
                'status',e.status,
                'severity',e.severity,
                'certainty',e.certainty,
                'urgency',e.urgency,
                'headline',e.headline,
                'effective_at',e.effective_at,
                'onset_at',e.onset_at,
                'ends_at',e.ends_at,
                'expires_at',e.expires_at,
                'source_slug',e.source_slug,
                'source_native_id',e.source_native_id
              )
            )
            order by
              coalesce(e.onset_at,e.effective_at,e.sent_at),
              e.canonical_key
          ),
          '[]'::jsonb
        ),
        count(*)::integer
      into v_events,v_count
      from intelligence.weather_events e
      where e.source_slug='nws-alerts-api'
        and e.status='Actual'
        and e.event_type = any(array[
          'Hurricane Warning','Hurricane Watch',
          'Tropical Storm Warning','Tropical Storm Watch',
          'Storm Surge Warning','Storm Surge Watch',
          'Extreme Wind Warning'
        ])
        and coalesce(e.onset_at,e.effective_at,e.sent_at) <= p_as_of_at
        and coalesce(
          e.ends_at,
          e.expires_at,
          e.last_observed_at + interval '1 hour'
        ) >= p_as_of_at
        and e.geometry is not null
        and extensions.st_intersects(e.geometry,v_boundary);

      v_status := case
        when v_count>0 then 'available'
        else 'inactive'
      end;
      v_applicability_state := case
        when v_count>0 then 'active_extreme_event'
        else 'not_applicable'
      end;
    end if;
  end if;

  v_source_signature := concat_ws(
    '|',
    'product=extreme-weather-event-context',
    'algorithm=nws-tropical-extreme-event-gate-v2',
    'as_of_minute='||date_trunc('minute',p_as_of_at)::text,
    'state='||v_state_code,
    'poll_fetched_at='||coalesce(v_poll.fetched_at::text,'missing'),
    'poll_http_status='||coalesce(v_poll.http_status::text,'missing'),
    'poll_error='||coalesce(v_poll.error_message,''),
    'unresolved_qualifying_event_count='||coalesce(v_unresolved_count,0)::text,
    'qualifying_event_count='||coalesce(v_count,0)::text,
    'event_keys='||coalesce((
      select string_agg(
        x->>'canonical_key',
        ','
        order by x->>'canonical_key'
      )
      from jsonb_array_elements(v_events) x
    ),'')
  );

  v_source_signature_sha256 := encode(
    extensions.digest(
      convert_to(v_source_signature,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          v_property_id::text,
          v_boundary_sha256,
          'nws-tropical-extreme-event-gate-v2',
          'extreme-weather-event-context-v1',
          v_source_signature_sha256
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_context := jsonb_build_object(
    'schema','extreme-weather-event-context-v1',
    'method','nws-tropical-extreme-event-gate-v2',
    'evidence_class','authoritative_event_context',
    'as_of_at',p_as_of_at,
    'applicability_state',v_applicability_state,
    'event_active',v_status='available',
    'events',v_events,
    'source_health',jsonb_build_object(
      'status',case
        when v_status='unavailable' then 'unavailable'
        else 'healthy'
      end,
      'jurisdiction',v_state_code,
      'poll_fetched_at',v_poll.fetched_at,
      'poll_age_seconds',v_poll_age_seconds,
      'http_status',v_poll.http_status,
      'feature_count',v_poll.feature_count,
      'error_message',v_poll.error_message,
      'unresolved_qualifying_event_count',
        coalesce(v_unresolved_count,0),
      'maximum_accepted_poll_age_seconds',1800
    ),
    'qualifying_event_types',jsonb_build_array(
      'Hurricane Warning','Hurricane Watch',
      'Tropical Storm Warning','Tropical Storm Watch',
      'Storm Surge Warning','Storm Surge Watch',
      'Extreme Wind Warning'
    ),
    'event_eligibility',jsonb_build_object(
      'nws_status','Actual',
      'spatial_gate','property boundary intersects authoritative alert geometry',
      'temporal_gate','alert onset/effective time <= as_of_at and end/expiry >= as_of_at',
      'unresolved_geometry_policy',
        'fail closed when a current qualifying jurisdiction alert lacks resolved geometry'
    ),
    'ordinary_weather_activation_allowed',false,
    'source','NOAA National Weather Service Alerts API',
    'source_fingerprint_sha256',v_source_signature_sha256,
    'scoring_performed',false,
    'deer_inference_performed',false,
    'coefficient_transfer_performed',false,
    'interpretation_boundary',
      'This is an explicit current tropical/extreme-wind event gate for FW-D18. A healthy authoritative poll with no intersecting qualifying event means not applicable. Source failure or unresolved qualifying alert geometry means unavailable, not inactive. Severe thunderstorms, routine wind, ordinary rainfall, heat, and generic storminess never activate the relationship.'
  );

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object(
      'slug',p_slug,
      'id',v_property_id,
      'state_code',v_state_code
    ),
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version','nws-tropical-extreme-event-gate-v2',
      'output_schema_version','extreme-weather-event-context-v1',
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_extreme_weather_event_context_v2_internal(
  p_slug text,
  p_as_of_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_resolved jsonb;
  v_property_id uuid;
begin
  v_resolved :=
    farm_watch.farm_watch_resolve_extreme_weather_event_context_v2_internal(
      p_slug,
      p_as_of_at
    );

  if v_resolved->>'status'='missing' then
    return v_resolved;
  end if;

  v_property_id := (v_resolved->'property'->>'id')::uuid;

  insert into farm_watch.property_extreme_weather_event_context_v1(
    property_id,
    as_of_at,
    status,
    context,
    boundary_sha256,
    source_signature,
    source_signature_sha256,
    algorithm_version,
    output_schema_version,
    identity_sha256,
    retrieved_at,
    updated_at
  ) values (
    v_property_id,
    p_as_of_at,
    v_resolved->>'status',
    v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),
    now()
  )
  on conflict(property_id) do update set
    as_of_at=excluded.as_of_at,
    status=excluded.status,
    context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    updated_at=now();

  return v_resolved;
end;
$$;

revoke all on intelligence.nws_alert_poll_status_v1
  from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_extreme_weather_event_context_v2_internal(
  text,timestamptz
) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_extreme_weather_event_context_v2_internal(
  text,timestamptz
) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_resolve_extreme_weather_event_context_v2_internal(
  text,timestamptz
) to service_role;
grant execute on function farm_watch.farm_watch_refresh_extreme_weather_event_context_v2_internal(
  text,timestamptz
) to service_role;

do $$
begin
  if exists(
    select 1
    from cron.job
    where jobname='farm-watch-extreme-weather-context-v1'
  ) then
    perform cron.unschedule('farm-watch-extreme-weather-context-v1');
  end if;

  perform cron.schedule(
    'farm-watch-extreme-weather-context-v2',
    '2,12,22,32,42,52 * * * *',
    $cron$
      select farm_watch.farm_watch_refresh_extreme_weather_event_context_v2_internal(
        'validation-property-01',
        now()
      );
    $cron$
  );
end;
$$;

comment on table intelligence.nws_alert_poll_status_v1 is
'Authoritative per-jurisdiction NWS alert poll health. Enables downstream consumers to distinguish a healthy zero-alert result from source failure.';

comment on function farm_watch.farm_watch_resolve_extreme_weather_event_context_v2_internal(
  text,timestamptz
) is
'FW-M45 authoritative event+footprint+time resolver. Returns not-applicable only after a fresh successful NWS jurisdiction poll and fails closed on stale source health or unresolved qualifying alert geometry.';

commit;
