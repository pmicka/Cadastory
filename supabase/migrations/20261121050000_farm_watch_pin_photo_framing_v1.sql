begin;
-- Framing is presentation-only metadata. Existing rows remain centered and the
-- private Storage object/bytes, authorization, and upload contract are unchanged.
alter table farm_watch.map_pin_photos_v1
 add column focal_x integer not null default 50 check (focal_x between 0 and 100),
 add column focal_y integer not null default 50 check (focal_y between 0 and 100);

create or replace function farm_watch.guard_pin_photo_v1() returns trigger language plpgsql set search_path='' as $$
declare expected text; begin
 if tg_op='DELETE' then
  insert into farm_watch.map_pin_photo_deletions_v1(object_path) values(old.object_path) on conflict do nothing;
  return old;
 end if;
 if tg_op='UPDATE' then
  -- Only non-destructive framing values may change. Identity, processed image
  -- metadata, and Storage path remain immutable.
  if (to_jsonb(new)-'focal_x'-'focal_y') is distinct from (to_jsonb(old)-'focal_x'-'focal_y')
   or new.focal_x not between 0 and 100 or new.focal_y not between 0 and 100 then
   raise exception 'immutable photo' using errcode='42501';
  end if;
  return new;
 end if;
 select p.property_id::text||'/'||p.id::text||'/'||new.id::text||'.webp' into expected
 from farm_watch.property_map_pins_v1 p where p.id=new.pin_id for update;
 if expected is null or new.object_path<>expected then raise exception 'invalid photo identity' using errcode='22023'; end if;
 if (select count(*) from farm_watch.map_pin_photos_v1 where pin_id=new.pin_id)>=4 then
  raise exception 'four photos maximum' using errcode='PT409';
 end if;
 return new;
end $$;

-- Preserve the five-argument legacy RPC and its existing grants.
-- Only its list/attach response projections acquire focal metadata.
create or replace function public.farm_watch_pin_photos_v1(p_property_slug text,p_pin_id uuid,p_action text,
 p_photo_id uuid default null,p_expected_revision integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); property farm_watch.properties%rowtype; pin farm_watch.property_map_pins_v1%rowtype;
 photo farm_watch.map_pin_photos_v1%rowtype; object storage.objects%rowtype; path text; result jsonb;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  or not exists(select 1 from auth.users where id=actor)
  or not public.farm_watch_authorize_user_v1_internal(actor)
  or coalesce(public.farm_watch_get_account_role_v1_internal(actor),'') not in ('owner','admin','viewer') then
  raise exception 'not found' using errcode='42501';
 end if;
 select * into property from farm_watch.properties where slug=p_property_slug and status='active';
 if property.id is null then raise exception 'not found' using errcode='42501'; end if;
 if p_action in ('prepare','attach','delete') then
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id and created_by=actor for update;
 else
  select * into pin from farm_watch.property_map_pins_v1 where id=p_pin_id and property_id=property.id;
 end if;
 if pin.id is null then raise exception 'not found' using errcode='42501'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'width',width,'height',height,'bytes',bytes,'focal_x',focal_x,'focal_y',focal_y) order by created_at,id),'[]') into result
   from farm_watch.map_pin_photos_v1 where pin_id=pin.id;
  return jsonb_build_object('photos',result,'revision',pin.revision);
 elsif p_action='read' then
  select * into photo from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
  return jsonb_build_object('object_path',photo.object_path,'bytes',photo.bytes);
 elsif p_action not in ('prepare','attach','delete') or p_action is null then
  raise exception 'invalid action' using errcode='22023';
 end if;
 if pin.icon<>'pin' and not farm_watch.can_use_map_pin_icons_v1(actor) then raise exception 'not found' using errcode='42501'; end if;
 if p_expected_revision is null or pin.revision<>p_expected_revision then raise exception 'pin changed; reload' using errcode='PT409'; end if;
 if p_photo_id is null then raise exception 'invalid photo' using errcode='22023'; end if;
 path:=property.id::text||'/'||pin.id::text||'/'||p_photo_id::text||'.webp';
 if p_action in ('prepare','attach') and (select count(*) from farm_watch.map_pin_photos_v1 where pin_id=pin.id)>=4 then
  raise exception 'four photos maximum' using errcode='PT409';
 end if;
 if p_action='prepare' then return jsonb_build_object('object_path',path); end if;
 if p_action='attach' then
  -- Only server-processed objects in this pin's own namespace can be attached.
  -- Clients cannot upload/read objects directly or forge these Storage fields.
  if exists(select 1 from farm_watch.map_pin_photo_deletions_v1 where object_path=path)
   or exists(select 1 from farm_watch.map_pin_photos_v1 where id=p_photo_id) then
   raise exception 'invalid photo' using errcode='22023';
  end if;
  select * into object from storage.objects where bucket_id='farm-watch-pin-photos' and name=path;
  if object.id is null or object.created_at<now()-interval '15 minutes' or object.metadata->>'mimetype' is distinct from 'image/webp'
   or object.user_metadata->>'pin_id' is distinct from pin.id::text
   or object.user_metadata->>'photo_id' is distinct from p_photo_id::text
   or coalesce(object.metadata->>'size','')!~'^[0-9]{1,7}$'
   or coalesce(object.user_metadata->>'width','')!~'^[0-9]{1,4}$'
   or coalesce(object.user_metadata->>'height','')!~'^[0-9]{1,4}$' then
   raise exception 'invalid processed photo' using errcode='22023';
  end if;
  insert into farm_watch.map_pin_photos_v1(id,pin_id,object_path,width,height,bytes)
   values(p_photo_id,pin.id,path,(object.user_metadata->>'width')::integer,(object.user_metadata->>'height')::integer,(object.metadata->>'size')::integer)
   returning * into photo;
 else
  delete from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id returning * into photo;
  if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
 end if;
 -- Serialize attachment changes with normal edits/deletion and the same guard.
 update farm_watch.property_map_pins_v1 set title=title where id=pin.id returning * into pin;
 return jsonb_build_object('revision',pin.revision,'photo',jsonb_build_object('id',photo.id,'width',photo.width,'height',photo.height,'bytes',photo.bytes,'focal_x',photo.focal_x,'focal_y',photo.focal_y));
end $$;

create function public.farm_watch_pin_photo_framing_v1(
 p_property_slug text, p_pin_id uuid, p_photo_id uuid, p_expected_revision integer,
 p_focal_x integer, p_focal_y integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); property farm_watch.properties%rowtype;
 pin farm_watch.property_map_pins_v1%rowtype; photo farm_watch.map_pin_photos_v1%rowtype;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  or not exists(select 1 from auth.users where id=actor)
  or not public.farm_watch_authorize_user_v1_internal(actor)
  or coalesce(public.farm_watch_get_account_role_v1_internal(actor),'') not in ('owner','admin','viewer') then
  raise exception 'not found' using errcode='42501';
 end if;
 select * into property from farm_watch.properties where slug=p_property_slug and status='active';
 if property.id is null then raise exception 'not found' using errcode='42501'; end if;
 select * into pin from farm_watch.property_map_pins_v1
  where id=p_pin_id and property_id=property.id and created_by=actor for update;
 if pin.id is null or (pin.icon<>'pin' and not farm_watch.can_use_map_pin_icons_v1(actor)) then
  raise exception 'not found' using errcode='42501';
 end if;
 if p_expected_revision is null or pin.revision<>p_expected_revision then
  raise exception 'pin changed; reload' using errcode='PT409';
 end if;
 if p_focal_x is null or p_focal_y is null
  or p_focal_x not between 0 and 100 or p_focal_y not between 0 and 100 then
  raise exception 'invalid framing' using errcode='22023';
 end if;
 select * into photo from farm_watch.map_pin_photos_v1 where id=p_photo_id and pin_id=pin.id for update;
 if photo.id is null then raise exception 'not found' using errcode='42501'; end if;
 if photo.focal_x is distinct from p_focal_x or photo.focal_y is distinct from p_focal_y then
  update farm_watch.map_pin_photos_v1 set focal_x=p_focal_x,focal_y=p_focal_y
   where id=photo.id returning * into photo;
  -- Same pin revision guard/increment as upload, deletion, and regular edits.
  update farm_watch.property_map_pins_v1 set title=title where id=pin.id returning * into pin;
 end if;
 return jsonb_build_object('revision',pin.revision,'photo',
  jsonb_build_object('id',photo.id,'focal_x',photo.focal_x,'focal_y',photo.focal_y));
end $$;
revoke all on function public.farm_watch_pin_photo_framing_v1(text,uuid,uuid,integer,integer,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_pin_photo_framing_v1(text,uuid,uuid,integer,integer,integer)
 to authenticated;

notify pgrst,'reload schema';
commit;
