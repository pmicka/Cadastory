-- Upgrade existing records and bootstrap the sole pre-existing active owner.
reset role;
update farm_watch.authorized_users set status='active',revoked_at=null;
update farm_watch.authorized_users set account_role='owner'
where user_id='00000000-0000-0000-0000-000000000002';
create temporary table pin_icons_before_upgrade as
select id,to_jsonb(p) as original from farm_watch.property_map_pins_v1 p;
