begin;

-- One homepage gallery for the ten legacy assets AND uploaded private WebP media.
-- Previously uploaded/staged files become visible (last in order) without copying bytes.
-- The ten originals may now move anywhere among at most 40 gallery items.
alter table farm_watch.home_gallery_photos_v1
  drop constraint home_gallery_photos_v1_sort_index_check,
  add constraint home_gallery_photos_v1_sort_index_check
    check(sort_index between 1 and 40);

alter table farm_watch.home_gallery_uploads_v1
  add column sort_index integer,
  add column caption text check (caption is null or char_length(caption)<=240),
  add column alt_text text check (alt_text is null or char_length(alt_text)<=240),
  add column focal_x smallint not null default 50 check (focal_x between 0 and 100),
  add column focal_y smallint not null default 50 check (focal_y between 0 and 100),
  add column is_visible boolean not null default true;

with numbered as (
  select id,10+row_number() over(partition by property_id order by created_at,id) as position
  from farm_watch.home_gallery_uploads_v1
) update farm_watch.home_gallery_uploads_v1 u
  set sort_index=n.position from numbered n where u.id=n.id;

alter table farm_watch.home_gallery_uploads_v1
  alter column sort_index set not null,
  add constraint fw_home_gallery_uploaded_order_bounded
    check(sort_index between 1 and 40);

-- The gallery row already serializes operations. Assign a position at insertion,
-- keep identity/Storage metadata immutable on edit, and queue objects on delete.
create or replace function farm_watch.guard_home_gallery_upload_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  expected_path text;
  visible_count integer;
begin
  if tg_op='DELETE' then
    perform 1 from farm_watch.home_gallery_v1 g where g.property_id=old.property_id for update;
    if old.is_visible then
      select (select count(*) from farm_watch.home_gallery_photos_v1 p
               where p.property_id=old.property_id and p.is_visible)
        +(select count(*) from farm_watch.home_gallery_uploads_v1 u
               where u.property_id=old.property_id and u.is_visible)
      into visible_count;
      if visible_count<=1 then
        raise exception 'at least one photo must remain visible' using errcode='PT409';
      end if;
    end if;
    insert into farm_watch.home_gallery_upload_deletions_v1(object_path)
      values(old.object_path) on conflict do nothing;
    return old;
  end if;

  if tg_op='UPDATE' then
    if new.id is distinct from old.id
      or new.property_id is distinct from old.property_id
      or new.object_path is distinct from old.object_path
      or new.created_by is distinct from old.created_by
      or new.width is distinct from old.width or new.height is distinct from old.height
      or new.bytes is distinct from old.bytes or new.created_at is distinct from old.created_at
    then raise exception 'immutable uploaded photo identity' using errcode='42501'; end if;
    return new;
  end if;

  perform 1 from farm_watch.home_gallery_v1 g
    where g.property_id=new.property_id for update;
  if not found then raise exception 'not found' using errcode='42501'; end if;
  expected_path:=new.property_id::text||'/'||new.id::text||'.webp';
  if new.object_path<>expected_path
    or (select count(*) from farm_watch.home_gallery_uploads_v1 u
        where u.property_id=new.property_id)>=30 then
    raise exception 'invalid uploaded image or capacity reached' using errcode='PT409';
  end if;
  select greatest(
    coalesce((select max(p.sort_index) from farm_watch.home_gallery_photos_v1 p
              where p.property_id=new.property_id),0),
    coalesce((select max(u.sort_index) from farm_watch.home_gallery_uploads_v1 u
              where u.property_id=new.property_id),0)
  )+1 into new.sort_index;
  return new;
end $$;

-- Viewer-safe, identity-only private Storage read authorization. No bucket paths
-- returned by the catalog. An owner/admin may preview hidden photos.
create function public.farm_watch_home_gallery_image_v1(
  p_property_slug text, p_photo_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=auth.uid();
  account_role text;
  image_record farm_watch.home_gallery_uploads_v1%rowtype;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists(select 1 from auth.users where id=actor)
    or not public.farm_watch_authorize_user_v1_internal(actor) then
    raise exception 'not found' using errcode='42501';
  end if;
  account_role:=public.farm_watch_get_account_role_v1_internal(actor);
  if account_role not in ('owner','admin','viewer') or p_photo_id is null then
    raise exception 'not found' using errcode='42501';
  end if;
  select u.* into image_record
  from farm_watch.home_gallery_uploads_v1 u
    join farm_watch.properties p on p.id=u.property_id
  where p.slug=p_property_slug and p.status='active'
    and u.id=p_photo_id
    and (u.is_visible or account_role in ('owner','admin'));
  if not found then raise exception 'not found' using errcode='42501'; end if;
  return jsonb_build_object('object_path',image_record.object_path,'bytes',image_record.bytes);
end $$;
revoke all on function public.farm_watch_home_gallery_image_v1(text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_home_gallery_image_v1(text,uuid)
  to authenticated;

-- v1 legacy RPC remains available during frontend rollout. v2 is the single
-- ordered gallery contract, keyed by legacy:<1..10> or upload:<uuid>.
create function public.farm_watch_home_gallery_v2(
  p_property_slug text,
  p_action text default 'list',
  p_photo_id text default null,
  p_expected_revision integer default null,
  p_caption text default null,
  p_alt_text text default null,
  p_focal_x integer default null,
  p_focal_y integer default null,
  p_is_visible boolean default null,
  p_order text[] default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=auth.uid();
  account_role text;
  target_property_id uuid;
  gallery farm_watch.home_gallery_v1%rowtype;
  photo_visible boolean;
  media_count integer;
  visible_count integer;
  result jsonb;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
     or not exists(select 1 from auth.users where id=actor)
     or not public.farm_watch_authorize_user_v1_internal(actor) then
    raise exception 'not found' using errcode='42501';
  end if;
  account_role:=public.farm_watch_get_account_role_v1_internal(actor);
  if account_role not in ('owner','admin','viewer') then
    raise exception 'not found' using errcode='42501';
  end if;
  select p.id into target_property_id from farm_watch.properties p
    where p.slug=p_property_slug and p.status='active';
  if target_property_id is null then raise exception 'not found' using errcode='42501'; end if;
  select * into gallery from farm_watch.home_gallery_v1 g
    where g.property_id=target_property_id;
  if not found then raise exception 'not found' using errcode='42501'; end if;

  if p_action='list' then
    if p_photo_id is not null or p_expected_revision is not null
      or p_caption is not null or p_alt_text is not null
      or p_focal_x is not null or p_focal_y is not null
      or p_is_visible is not null or p_order is not null then
      raise exception 'invalid list' using errcode='22023';
    end if;
    with all_photos as (
      select 'legacy:'||p.photo_number::text as photo_id,'legacy'::text as kind,
        p.photo_number::integer as photo_number,p.sort_index::integer as order_value,
        p.caption,p.alt_text,p.focal_x,p.focal_y,p.is_visible
      from farm_watch.home_gallery_photos_v1 p
        where p.property_id=target_property_id
      union all
      select 'upload:'||u.id::text,'upload'::text,null::integer,
        u.sort_index,u.caption,u.alt_text,u.focal_x,u.focal_y,u.is_visible
      from farm_watch.home_gallery_uploads_v1 u
        where u.property_id=target_property_id
    ), ordered as (
      select a.*,row_number() over(order by a.order_value,a.kind,a.photo_id) as position
      from all_photos a
    )
    select coalesce(jsonb_agg(jsonb_build_object(
       'photo_id',p.photo_id,'kind',p.kind,'photo_number',p.photo_number,
       'sort_index',p.position,'caption',p.caption,'alt_text',p.alt_text,
       'focal_x',p.focal_x,'focal_y',p.focal_y,'is_visible',p.is_visible
    ) order by p.position),'[]'::jsonb) into result
    from ordered p
    where (account_role in ('owner','admin') or p.is_visible);
    return jsonb_build_object('revision',gallery.revision,'source','mixed-gallery-v2',
      'can_edit',account_role in ('owner','admin'),'photos',result);
  end if;

  if account_role not in ('owner','admin') then raise exception 'not found' using errcode='42501'; end if;
  if p_action not in ('update','reorder') then raise exception 'invalid action' using errcode='22023'; end if;
  select * into gallery from farm_watch.home_gallery_v1 g
    where g.property_id=target_property_id for update;
  if gallery.revision is distinct from p_expected_revision then
    raise exception 'gallery changed; reload' using errcode='PT409';
  end if;
  select (select count(*) from farm_watch.home_gallery_photos_v1 p where p.property_id=target_property_id)
       +(select count(*) from farm_watch.home_gallery_uploads_v1 u where u.property_id=target_property_id)
    into media_count;
  select (select count(*) from farm_watch.home_gallery_photos_v1 p
           where p.property_id=target_property_id and p.is_visible)
       +(select count(*) from farm_watch.home_gallery_uploads_v1 u
           where u.property_id=target_property_id and u.is_visible)
    into visible_count;

  if p_action='update' then
    if p_order is not null or p_photo_id is null or
       not (p_photo_id~'^legacy:(10|[1-9])$'
            or p_photo_id~'^upload:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
       or (p_caption is null and p_alt_text is null and p_focal_x is null
           and p_focal_y is null and p_is_visible is null)
       or (p_caption is not null and char_length(btrim(p_caption))>240)
       or (p_alt_text is not null and char_length(btrim(p_alt_text))>240)
       or (p_focal_x is not null and p_focal_x not between 0 and 100)
       or (p_focal_y is not null and p_focal_y not between 0 and 100) then
      raise exception 'invalid gallery update' using errcode='22023';
    end if;
    if p_photo_id like 'legacy:%' then
      select p.is_visible into photo_visible from farm_watch.home_gallery_photos_v1 p
        where p.property_id=target_property_id and p.photo_number=substring(p_photo_id from 8)::integer;
      if not found then raise exception 'not found' using errcode='42501'; end if;
      if p_is_visible=false and photo_visible and visible_count<=1 then
        raise exception 'at least one photo must remain visible' using errcode='PT409'; end if;
      update farm_watch.home_gallery_photos_v1 p set
        caption=case when p_caption is null then p.caption else nullif(btrim(p_caption),'') end,
        alt_text=case when p_alt_text is null then p.alt_text else nullif(btrim(p_alt_text),'') end,
        focal_x=coalesce(p_focal_x,p.focal_x),focal_y=coalesce(p_focal_y,p.focal_y),
        is_visible=coalesce(p_is_visible,p.is_visible)
      where p.property_id=target_property_id and p.photo_number=substring(p_photo_id from 8)::integer;
    else
      select u.is_visible into photo_visible from farm_watch.home_gallery_uploads_v1 u
        where u.property_id=target_property_id and u.id=substring(p_photo_id from 8)::uuid;
      if not found then raise exception 'not found' using errcode='42501'; end if;
      if p_is_visible=false and photo_visible and visible_count<=1 then
        raise exception 'at least one photo must remain visible' using errcode='PT409'; end if;
      update farm_watch.home_gallery_uploads_v1 u set
        caption=case when p_caption is null then u.caption else nullif(btrim(p_caption),'') end,
        alt_text=case when p_alt_text is null then u.alt_text else nullif(btrim(p_alt_text),'') end,
        focal_x=coalesce(p_focal_x,u.focal_x),focal_y=coalesce(p_focal_y,u.focal_y),
        is_visible=coalesce(p_is_visible,u.is_visible)
      where u.property_id=target_property_id and u.id=substring(p_photo_id from 8)::uuid;
    end if;
  else
    if p_photo_id is not null or p_caption is not null or p_alt_text is not null
       or p_focal_x is not null or p_focal_y is not null or p_is_visible is not null
       or p_order is null or cardinality(p_order)<>media_count
       or (select count(distinct key) from unnest(p_order) key)<>media_count
       or exists(
          select key from unnest(p_order) key
          except
          (select 'legacy:'||p.photo_number::text from farm_watch.home_gallery_photos_v1 p
             where p.property_id=target_property_id
           union all
           select 'upload:'||u.id::text from farm_watch.home_gallery_uploads_v1 u
             where u.property_id=target_property_id)
       ) then raise exception 'invalid gallery order' using errcode='22023'; end if;
    update farm_watch.home_gallery_photos_v1 p
      set sort_index=array_position(p_order,'legacy:'||p.photo_number::text)
      where p.property_id=target_property_id;
    update farm_watch.home_gallery_uploads_v1 u
      set sort_index=array_position(p_order,'upload:'||u.id::text)
      where u.property_id=target_property_id;
  end if;
  update farm_watch.home_gallery_v1 g set revision=g.revision+1,
    updated_at=clock_timestamp()
    where g.property_id=target_property_id returning * into gallery;
  return jsonb_build_object('revision',gallery.revision,'updated',true);
end $$;
revoke all on function public.farm_watch_home_gallery_v2(
  text,text,text,integer,text,text,integer,integer,boolean,text[]
) from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_home_gallery_v2(
  text,text,text,integer,text,text,integer,integer,boolean,text[]
) to authenticated;

comment on table farm_watch.home_gallery_uploads_v1 is
  'Owner/admin-created private WebP storage records, automatically in the authenticated homepage slideshow; viewer reads require visibility checks.';

commit;
