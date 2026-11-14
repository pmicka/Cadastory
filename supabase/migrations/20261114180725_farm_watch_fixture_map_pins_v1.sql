begin;

-- Map annotations may be edited/deleted without rewriting the original evidence.
-- Keep a private tombstone so a replay never resurrects a deleted migrated pin.
create table if not exists farm_watch.property_map_pin_fixture_links_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  observation_key text not null,
  source_observation_id uuid unique references farm_watch.property_operator_observations_v1(id) on delete set null,
  pin_id uuid unique references farm_watch.property_map_pins_v1(id) on delete set null,
  primary key (property_id, observation_key)
);
alter table farm_watch.property_map_pin_fixture_links_v1 enable row level security;
alter table farm_watch.property_map_pin_fixture_links_v1 force row level security;
revoke all on farm_watch.property_map_pin_fixture_links_v1 from public, anon, authenticated, service_role;
comment on table farm_watch.property_map_pin_fixture_links_v1 is
  'Private one-time map migration ledger. Source observations remain historical evidence; editable pins never update them. Null pin_id is a deletion tombstone.';

do $$
declare
  original_claims text := current_setting('request.jwt.claims', true);
  actor uuid;
  actor_count integer;
  source record;
  saved jsonb;
begin
  lock table farm_watch.property_map_pin_fixture_links_v1 in share row exclusive mode;
  if not exists (
    select 1 from farm_watch.property_operator_observations_v1 o
    join farm_watch.properties p on p.id=o.property_id
    where p.slug='validation-property-01' and p.status='active' and o.active
      and o.observation_key in ('flat-creek-deer-feeder-01','flat-creek-salt-block-01')
      and not exists (select 1 from farm_watch.property_map_pin_fixture_links_v1 l
        where l.property_id=o.property_id and l.observation_key=o.observation_key)
  ) then return; end if;

  -- These two owner/operator-submitted points predate Auth attribution. Bind the
  -- migration to the original operator's already-explicit icon grant, never to
  -- whichever future owner/admin happens to be signed in or viewing the map.
  select count(*), (array_agg(g.user_id))[1] into actor_count, actor
  from farm_watch.map_pin_icon_users_v1 g
  join farm_watch.authorized_users a on a.user_id=g.user_id
  join auth.users u on u.id=g.user_id
  where a.account_role='owner' and a.status='active' and a.revoked_at is null;
  if actor_count<>1 or (select count(*) from farm_watch.map_pin_icon_users_v1)<>1 then
    raise exception 'Legacy fixture migration requires the single original operator icon account';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);

  for source in
    select o.*, p.slug, expected.kind, expected.title, expected.icon, expected.color
    from farm_watch.property_operator_observations_v1 o
    join farm_watch.properties p on p.id=o.property_id
    join (values
      ('flat-creek-deer-feeder-01','deer_feeder_location','Corn feeder','corn_feeder','#388306'),
      ('flat-creek-salt-block-01','mineral_attractant_location','Salt block','salt_mineral_block','#008b91')
    ) as expected(key,kind,title,icon,color) on expected.key=o.observation_key
    where p.slug='validation-property-01' and p.status='active' and o.active
      and not exists (select 1 from farm_watch.property_map_pin_fixture_links_v1 l
        where l.property_id=o.property_id and l.observation_key=o.observation_key)
    order by o.observation_key
  loop
    if source.observation_kind<>source.kind or extensions.geometrytype(source.geometry)<>'POINT' then
      raise exception 'Unexpected legacy fixture source';
    end if;
    -- Reuse the real creator, capability, bounded-create and boundary checks.
    saved := public.farm_watch_map_pins_v1(source.slug,'create',
      p_title=>source.title, p_longitude=>extensions.st_x(source.geometry),
      p_latitude=>extensions.st_y(source.geometry), p_color=>source.color, p_icon=>source.icon)->'pin';
    insert into farm_watch.property_map_pin_fixture_links_v1(property_id,observation_key,source_observation_id,pin_id)
    values(source.property_id,source.observation_key,source.id,(saved->>'id')::uuid);
  end loop;
  perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
end $$;

commit;
