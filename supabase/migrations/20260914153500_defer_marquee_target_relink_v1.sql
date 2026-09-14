-- Batch 8: avoid recomputing the global marquee-event target graph once per source.
-- Each successful source batch still updates its source health immediately.
-- The final source in a fully successful daily cycle performs one relink; a
-- scheduled fallback relink guarantees convergence after partial source runs.

create or replace function public.internal_upsert_marquee_event_batch(p_source_slug text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rows integer:=0;
  v_complete boolean:=false;
  v_now timestamptz:=now();
  v_relinked boolean:=false;
begin
  if not exists(
    select 1
    from intelligence.marquee_event_sources
    where source_slug=p_source_slug and active
  ) then
    raise exception 'unknown or inactive marquee event source';
  end if;

  select complete_snapshot
    into v_complete
  from intelligence.marquee_event_sources
  where source_slug=p_source_slug;

  with r as (
    select *
    from jsonb_to_recordset(coalesce(p_rows,'[]'::jsonb)) as x(
      external_event_key text,event_family text,title text,category text,
      start_date date,end_date date,venue_name text,venue_address text,
      city text,state_code text,longitude double precision,latitude double precision,
      attendance_min integer,attendance_max integer,attendance_basis text,
      recurring_annual boolean,national_draw boolean,influence_radius_m integer,
      impact_score numeric,source_url text,confidence numeric,evidence jsonb
    )
  ), u as (
    insert into intelligence.marquee_events(
      source_slug,external_event_key,event_family,title,category,start_date,end_date,
      venue_name,venue_address,city,state_code,location,attendance_min,attendance_max,
      attendance_basis,recurring_annual,national_draw,influence_radius_m,impact_score,
      event_tier,source_url,source_present,confidence,evidence,first_observed_at,
      last_observed_at,updated_at
    )
    select p_source_slug,r.external_event_key,r.event_family,r.title,r.category,
      r.start_date,coalesce(r.end_date,r.start_date),r.venue_name,r.venue_address,
      r.city,r.state_code,
      case when r.longitude is not null and r.latitude is not null
        then extensions.st_setsrid(extensions.st_makepoint(r.longitude,r.latitude),4326)::extensions.geography
        else null end,
      r.attendance_min,r.attendance_max,r.attendance_basis,
      coalesce(r.recurring_annual,false),coalesce(r.national_draw,false),
      coalesce(r.influence_radius_m,1200),
      coalesce(r.impact_score,intelligence.score_marquee_event(
        r.attendance_max,r.start_date,coalesce(r.end_date,r.start_date),
        coalesce(r.national_draw,false),r.title)),
      intelligence.marquee_event_tier(coalesce(r.impact_score,
        intelligence.score_marquee_event(
          r.attendance_max,r.start_date,coalesce(r.end_date,r.start_date),
          coalesce(r.national_draw,false),r.title))),
      coalesce(r.source_url,(select fetch_url from intelligence.marquee_event_sources where source_slug=p_source_slug)),
      true,coalesce(r.confidence,0.8),coalesce(r.evidence,'{}'::jsonb),v_now,v_now,v_now
    from r
    where r.external_event_key is not null
      and r.title is not null
      and r.start_date is not null
    on conflict(source_slug,external_event_key) do update set
      event_family=excluded.event_family,
      title=excluded.title,
      category=excluded.category,
      start_date=excluded.start_date,
      end_date=excluded.end_date,
      venue_name=excluded.venue_name,
      venue_address=coalesce(excluded.venue_address,intelligence.marquee_events.venue_address),
      city=coalesce(excluded.city,intelligence.marquee_events.city),
      state_code=coalesce(excluded.state_code,intelligence.marquee_events.state_code),
      location=coalesce(excluded.location,intelligence.marquee_events.location),
      attendance_min=excluded.attendance_min,
      attendance_max=excluded.attendance_max,
      attendance_basis=excluded.attendance_basis,
      recurring_annual=excluded.recurring_annual,
      national_draw=excluded.national_draw,
      influence_radius_m=excluded.influence_radius_m,
      impact_score=excluded.impact_score,
      event_tier=excluded.event_tier,
      source_url=excluded.source_url,
      source_present=true,
      confidence=excluded.confidence,
      evidence=excluded.evidence,
      last_observed_at=v_now,
      updated_at=v_now
    returning 1
  )
  select count(*) into v_rows from u;

  if v_complete then
    update intelligence.marquee_events e
       set source_present=false,updated_at=v_now
     where e.source_slug=p_source_slug
       and e.last_observed_at<v_now-interval '10 seconds'
       and e.start_date>=current_date-30;
  end if;

  update intelligence.marquee_event_sources
     set last_success_at=v_now,last_error=null,updated_at=v_now
   where source_slug=p_source_slug;

  -- Relink once after all active sources have succeeded during the current UTC day.
  if not exists (
    select 1
    from intelligence.marquee_event_sources s
    where s.active
      and (s.last_success_at is null or s.last_success_at < date_trunc('day',v_now))
  ) then
    perform intelligence.refresh_marquee_event_target_links();
    v_relinked:=true;
  end if;

  return jsonb_build_object(
    'source_slug',p_source_slug,
    'upserted',v_rows,
    'target_links_refreshed',v_relinked
  );
exception when others then
  update intelligence.marquee_event_sources
     set last_error=sqlerrm,updated_at=now()
   where source_slug=p_source_slug;
  raise;
end
$function$;

revoke all on function public.internal_upsert_marquee_event_batch(text,jsonb) from public,anon,authenticated;
grant execute on function public.internal_upsert_marquee_event_batch(text,jsonb) to service_role;

-- Fallback after the 08:12 UTC collector: one deterministic relink even when a
-- source feed is partial or unavailable, so successful batches still converge.
select cron.schedule(
  'scout-marquee-event-target-links-daily',
  '20 8 * * *',
  $$select intelligence.refresh_marquee_event_target_links();$$
);