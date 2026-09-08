-- Close current-snapshot procurement records that disappear from an authoritative snapshot.
-- This is internal source-state hygiene, not an inference about award/cancellation reason.

create or replace function public.internal_finalize_procurement_opportunity_snapshot(
  p_source_slug text,
  p_snapshot_observed_at timestamptz
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer := 0;
begin
  if not exists (select 1 from ingest.sources where slug = p_source_slug) then
    raise exception 'Unknown procurement source slug: %', p_source_slug;
  end if;

  update procurement.opportunities
     set active = false,
         updated_at = now()
   where source_slug = p_source_slug
     and active is distinct from false
     and last_observed_at < p_snapshot_observed_at;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.internal_finalize_procurement_opportunity_snapshot(text,timestamptz) from public;
revoke all on function public.internal_finalize_procurement_opportunity_snapshot(text,timestamptz) from anon, authenticated;
grant execute on function public.internal_finalize_procurement_opportunity_snapshot(text,timestamptz) to service_role;
