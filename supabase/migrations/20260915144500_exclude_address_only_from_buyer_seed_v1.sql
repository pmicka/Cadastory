-- Generic buyer web research should only receive named/resolved organizations.
-- Address-only opportunities are handled by the responsible-party resolution lane.
do $$
declare v_def text; v_before text;
begin
  select pg_get_functiondef('public.internal_seed_buyer_document_evidence_jobs(integer)'::regprocedure)
  into v_def;
  v_before:=v_def;
  v_def:=replace(
    v_def,
    E'and q.next_attempt_at<=now()\n      and (s.time_sensitive',
    E'and q.next_attempt_at<=now()\n      and (s.buyer_organization_id is not null or nullif(btrim(q.buyer_hint),'''') is not null)\n      and (s.time_sensitive'
  );
  if v_def=v_before or v_def not like '%buyer_organization_id is not null or nullif(btrim(q.buyer_hint)%' then
    raise exception 'buyer seeder address-only exclusion patch did not match function definition';
  end if;
  execute v_def;
end
$$;
