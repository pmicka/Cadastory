-- Full buyer-route rebuilds must restore durable responsible-party evidence before
-- reconstructing opportunity_buyer_routes and buyer_resolution_queue.
do $$
declare v_def text; v_before text;
begin
  select pg_get_functiondef('scout.refresh_opportunity_buyer_routes()'::regprocedure) into v_def;
  v_before:=v_def;
  v_def:=replace(
    v_def,
    E'  end if;\n  delete from scout.opportunity_buyer_routes;',
    E'  end if;\n  perform scout.restore_responsible_party_buyer_candidates_v1(null);\n  delete from scout.opportunity_buyer_routes;'
  );
  if v_def=v_before or v_def not like '%restore_responsible_party_buyer_candidates_v1%' then
    raise exception 'responsible-party overlay patch did not match buyer refresh definition';
  end if;
  execute v_def;
end
$$;

-- Rebuild immediately to verify the durable overlay path on deployment.
select scout.refresh_opportunity_buyer_routes();
