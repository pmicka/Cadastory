begin;

create or replace function public.farm_watch_get_account_role_v1_internal(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  with direct_role as (
    select u.account_role
    from farm_watch.authorized_users u
    where u.user_id = p_user_id
      and u.status = 'active'
      and u.revoked_at is null
    order by case when u.account_role = 'owner' then 0 else 1 end, u.updated_at desc
    limit 1
  ),
  email_role as (
    select ae.account_role
    from auth.users au
    join farm_watch.authorized_emails ae
      on ae.email = lower(au.email)
    where au.id = p_user_id
      and au.email is not null
      and au.email_confirmed_at is not null
      and ae.status = 'active'
      and ae.revoked_at is null
      and exists (
        select 1
        from auth.identities ai
        where ai.user_id = au.id
          and ai.provider = 'google'
      )
    order by case when ae.account_role = 'owner' then 0 else 1 end, ae.updated_at desc
    limit 1
  )
  select coalesce(
    (select account_role from direct_role),
    (select account_role from email_role)
  );
$function$;

revoke all on function public.farm_watch_get_account_role_v1_internal(uuid) from public, anon, authenticated;
grant execute on function public.farm_watch_get_account_role_v1_internal(uuid) to service_role;

with target as (
  select
    o.id,
    extensions.st_transform(o.geometry, 3857) as g3857
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id = o.property_id
  where p.slug = 'validation-property-01'
    and o.path_key = 'flat-creek-phase3-image-trails'
),
centered as (
  select
    id,
    g3857,
    (extensions.st_xmin(extensions.box3d(g3857)) + extensions.st_xmax(extensions.box3d(g3857))) / 2.0 as cx,
    (extensions.st_ymin(extensions.box3d(g3857)) + extensions.st_ymax(extensions.box3d(g3857))) / 2.0 as cy
  from target
),
adjusted as (
  select
    id,
    extensions.st_transform(
      extensions.st_translate(
        extensions.st_scale(
          extensions.st_translate(g3857, -cx, -cy),
          0.975,
          0.975
        ),
        cx - 203.04,
        cy + 43.00
      ),
      4326
    ) as geometry
  from centered
)
update farm_watch.property_operator_paths_v1 o
set
  geometry = a.geometry,
  geometry_basis = 'operator_guided_phase3_scale39_position_locked_v4',
  source_context = jsonb_set(
    jsonb_set(
      o.source_context,
      '{scale_lock}',
      jsonb_build_object(
        'canonical_scale', 0.39,
        'scale_percent', 39.0,
        'prior_canonical_scale', 0.40,
        'residual_scale_applied', 0.975,
        'scale_origin', 'EPSG:3857 geometry bounding-box center',
        'basis', 'operator visual QA scale-only pass followed by placement QA'
      ),
      true
    ),
    '{placement_lock}',
    jsonb_build_object(
      'east_m', -203.04,
      'north_m', 43.00,
      'qa_zoom', 16,
      'qa_screen_pixel_m', 2.39,
      'basis', 'operator visual QA pixel-nudge pass',
      'manual_qa_position_used', true,
      'road_connection_status', 'pending_reconciliation_after_placement_lock'
    ),
    true
  ),
  notes = regexp_replace(
    coalesce(o.notes, ''),
    ' Canonical scale locked at 40% during operator scale-only QA; placement remains intentionally uncorrected pending pixel-nudge QA\.$',
    ''
  ) || ' Canonical geometry now locks the operator QA result at 39.0% effective scale, 203.04 m west, and 43.00 m north. Road/trail topology will be reconciled after final placement verification.',
  updated_at = now()
from adjusted a
where o.id = a.id;

commit;
