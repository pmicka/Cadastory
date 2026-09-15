-- SECURITY DEFINER functions use an empty search_path. Qualify PostGIS type,
-- operator, and function references in the responsible-party seeder.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.internal_seed_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
  into v_def;
  v_def:=replace(v_def,'s.location::geometry location','s.location::extensions.geometry location');
  v_def:=replace(
    v_def,
    'r.geometry::geometry && e.location and st_intersects(r.geometry::geometry,e.location)',
    'r.geometry::extensions.geometry OPERATOR(extensions.&&) e.location and extensions.st_intersects(r.geometry::extensions.geometry,e.location)'
  );
  if v_def not like '%extensions.st_intersects%' then
    raise exception 'responsible-party PostGIS qualification patch did not match function definition';
  end if;
  execute v_def;
end
$$;
