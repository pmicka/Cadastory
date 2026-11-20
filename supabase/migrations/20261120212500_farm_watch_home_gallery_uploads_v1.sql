begin;

-- WMW homepage gallery uploads v1: private staging only.
-- These records never alter the legacy ten-image catalog or public slideshow.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('farm-watch-home-gallery-uploads','farm-watch-home-gallery-uploads',
       false,524288,array['image/webp'])
on conflict(id) do nothing;
do $$ begin
  if not exists (
    select 1 from storage.buckets where id='farm-watch-home-gallery-uploads'
    and public=false and file_size_limit=524288
    and allowed_mime_types=array['image/webp']
  ) then raise exception 'unsafe WMW gallery bucket configuration'; end if;
end $$;

-- Fail closed even if other code later grants a broad Storage policy.
create policy fw_home_gallery_uploads_private_v1 on storage.objects as restrictive
for all to anon,authenticated
using(bucket_id<>'farm-watch-home-gallery-uploads')
with check(bucket_id<>'farm-watch-home-gallery-uploads');

create table farm_watch.home_gallery_uploads_v1 (
  id uuid primary key,
  property_id uuid not null references farm_watch.home_gallery_v1(property_id) on delete cascade,
  object_path text not null unique,
  created_by uuid not null references auth.users(id),
  width integer not null check(width between 1 and 1600),
  height integer not null check(height between 1 and 1600),
  bytes integer not null check(bytes between 1 and 524288),
  created_at timestamptz not null default clock_timestamp()
);
create index home_gallery_uploads_v1_property
  on farm_watch.home_gallery_uploads_v1(property_id,created_at,id);
create table farm_watch.home_gallery_upload_deletions_v1 (
  object_path text primary key,
  queued_at timestamptz not null default clock_timestamp()
);
alter table farm_watch.home_gallery_uploads_v1 enable row level security;
alter table farm_watch.home_gallery_uploads_v1 force row level security;
alter table farm_watch.home_gallery_upload_deletions_v1 enable row level security;
alter table farm_watch.home_gallery_upload_deletions_v1 force row level security;
revoke all on farm_watch.home_gallery_uploads_v1,
  farm_watch.home_gallery_upload_deletions_v1
from public,anon,authenticated,service_role;

create function farm_watch.guard_home_gallery_upload_v1()
returns trigger language plpgsql set search_path='' as $$
declare expected_path text;
begin
  if tg_op='DELETE' then
    insert into farm_watch.home_gallery_upload_deletions_v1(object_path)
    values(old.object_path) on conflict do nothing;
    return old;
  end if;
  if tg_op='UPDATE' then
    raise exception 'immutable staged photo' using errcode='42501';
  end if;
  -- Cap is checked under this gallery's lock, including any privileged
  -- maintenance insert that did not enter through the RPC.
  perform 1 from farm_watch.home_gallery_v1 g
    where g.property_id=new.property_id for update;
  if not found then raise exception 'not found' using errcode='42501'; end if;
  expected_path := new.property_id::text||'/'||new.id::text||'.webp';
  if new.object_path<>expected_path or
    (select count(*) from farm_watch.home_gallery_uploads_v1 u
     where u.property_id=new.property_id)>=30 then
    raise exception 'invalid staged image or capacity reached' using errcode='PT409';
  end if;
  return new;
end $$;
revoke all on function farm_watch.guard_home_gallery_upload_v1() from public,anon,authenticated,service_role;
create trigger home_gallery_upload_guard_v1 before insert or update or delete
  on farm_watch.home_gallery_uploads_v1
  for each row execute function farm_watch.guard_home_gallery_upload_v1();

create function public.farm_watch_home_gallery_uploads_v1(
  p_property_slug text,
  p_action text,
  p_photo_id uuid default null,
  p_expected_revision integer default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  role_name text;
  target_property_id uuid;
  gallery farm_watch.home_gallery_v1%rowtype;
  staged farm_watch.home_gallery_uploads_v1%rowtype;
  object_row storage.objects%rowtype;
  path text;
  result jsonb;
begin
  if actor is null
    or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists(select 1 from auth.users where id=actor)
    or not public.farm_watch_authorize_user_v1_internal(actor)
  then raise exception 'not found' using errcode='42501'; end if;
  role_name:=public.farm_watch_get_account_role_v1_internal(actor);
  -- Staged, unpublished uploads are not part of the viewer photo catalog.
  if role_name not in ('owner','admin') or role_name is null then
    raise exception 'not found' using errcode='42501';
  end if;
  select p.id into target_property_id from farm_watch.properties p
    where p.slug=p_property_slug and p.status='active';
  if target_property_id is null then raise exception 'not found' using errcode='42501'; end if;

  if p_action='list' then
    if p_photo_id is not null or p_expected_revision is not null then
      raise exception 'invalid list' using errcode='22023'; end if;
    select * into gallery from farm_watch.home_gallery_v1 g
      where g.property_id=target_property_id;
    if not found then raise exception 'not found' using errcode='42501'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',u.id,'width',u.width,'height',u.height,'bytes',u.bytes,
      'created_at',u.created_at
    ) order by u.created_at,u.id),'[]'::jsonb) into result
    from farm_watch.home_gallery_uploads_v1 u
    where u.property_id=gallery.property_id;
    return jsonb_build_object('revision',gallery.revision,'photos',result,
      'staged_only',true,'max_uploads',30);
  end if;

  if p_action='read' then
    if p_photo_id is null or p_expected_revision is not null then
      raise exception 'invalid read' using errcode='22023'; end if;
    select * into staged from farm_watch.home_gallery_uploads_v1 u
    where u.property_id=target_property_id and u.id=p_photo_id;
    if not found then raise exception 'not found' using errcode='42501'; end if;
    return jsonb_build_object('object_path',staged.object_path,
      'bytes',staged.bytes);
  end if;

  if p_action not in ('prepare','attach','delete') or p_action is null then
    raise exception 'invalid action' using errcode='22023'; end if;
  if p_photo_id is null or p_expected_revision is null or p_expected_revision<1 then
    raise exception 'invalid photo request' using errcode='22023'; end if;
  select * into gallery from farm_watch.home_gallery_v1 g
    where g.property_id=target_property_id for update;
  if not found then raise exception 'not found' using errcode='42501'; end if;
  if gallery.revision<>p_expected_revision then
    raise exception 'gallery changed; reload' using errcode='PT409'; end if;
  path:=gallery.property_id::text||'/'||p_photo_id::text||'.webp';

  if p_action='delete' then
    delete from farm_watch.home_gallery_uploads_v1 u
      where u.property_id=gallery.property_id and u.id=p_photo_id
      returning * into staged;
    if not found then raise exception 'not found' using errcode='42501'; end if;
  else
    if (select count(*) from farm_watch.home_gallery_uploads_v1 u
        where u.property_id=gallery.property_id)>=30 then
      raise exception 'staged photo limit reached' using errcode='PT409'; end if;
    if exists(select 1 from farm_watch.home_gallery_upload_deletions_v1 d
                where d.object_path=path)
      or exists(select 1 from farm_watch.home_gallery_uploads_v1 u
                where u.id=p_photo_id) then
      raise exception 'invalid upload' using errcode='22023'; end if;
    if p_action='prepare' then
      -- Only the user-scoped RPC can authorize uploads; the Edge Function
      -- generates IDs, processes bytes and performs service-only Storage I/O.
      return jsonb_build_object('object_path',path);
    end if;

    select * into object_row from storage.objects o
      where o.bucket_id='farm-watch-home-gallery-uploads' and o.name=path;
    if not found or object_row.created_at<now()-interval '15 minutes'
      or object_row.metadata->>'mimetype' is distinct from 'image/webp'
      or object_row.user_metadata->>'property_id' is distinct from gallery.property_id::text
      or object_row.user_metadata->>'photo_id' is distinct from p_photo_id::text
      or object_row.user_metadata->>'created_by' is distinct from actor::text
      or coalesce(object_row.metadata->>'size','')!~'^[0-9]{1,6}$'
      or coalesce(object_row.user_metadata->>'width','')!~'^[0-9]{1,4}$'
      or coalesce(object_row.user_metadata->>'height','')!~'^[0-9]{1,4}$'
    then raise exception 'invalid processed upload' using errcode='22023'; end if;
    insert into farm_watch.home_gallery_uploads_v1(
      id,property_id,object_path,created_by,width,height,bytes
    ) values(
      p_photo_id,gallery.property_id,path,actor,
      (object_row.user_metadata->>'width')::integer,
      (object_row.user_metadata->>'height')::integer,
      (object_row.metadata->>'size')::integer
    ) returning * into staged;
  end if;
  update farm_watch.home_gallery_v1 g set revision=g.revision+1,
    updated_at=clock_timestamp() where g.property_id=gallery.property_id
    returning * into gallery;
  return jsonb_build_object('revision',gallery.revision,
    'deleted',p_action='delete','staged_only',true,
    'photo',jsonb_build_object('id',staged.id,'width',staged.width,
      'height',staged.height,'bytes',staged.bytes));
end $$;
revoke all on function public.farm_watch_home_gallery_uploads_v1(text,text,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_home_gallery_uploads_v1(text,text,uuid,integer)
  to authenticated;

create function public.farm_watch_home_gallery_upload_cleanup_v1(
  p_ack_paths text[] default null,
  p_queue_path text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'not found' using errcode='42501'; end if;
  if p_queue_path is not null then
    if p_queue_path!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$'
       or exists(select 1 from farm_watch.home_gallery_uploads_v1 u
                 where u.object_path=p_queue_path) then
      raise exception 'invalid cleanup path' using errcode='22023'; end if;
    insert into farm_watch.home_gallery_upload_deletions_v1(object_path)
      values(p_queue_path) on conflict do nothing;
  end if;
  if p_ack_paths is not null then
    delete from farm_watch.home_gallery_upload_deletions_v1 d
      where d.object_path=any(p_ack_paths)
      and not exists(select 1 from farm_watch.home_gallery_uploads_v1 u
                     where u.object_path=d.object_path);
  end if;
  select coalesce(jsonb_agg(object_path),'[]'::jsonb) into result from (
    select d.object_path from farm_watch.home_gallery_upload_deletions_v1 d
     where not exists(select 1 from farm_watch.home_gallery_uploads_v1 u
                      where u.object_path=d.object_path)
    union
    select o.name from storage.objects o
     where o.bucket_id='farm-watch-home-gallery-uploads'
       and o.created_at<now()-interval '1 hour'
       and not exists(select 1 from farm_watch.home_gallery_uploads_v1 u
                      where u.object_path=o.name)
    limit 20
  ) q;
  return jsonb_build_object('paths',result);
end $$;
revoke all on function public.farm_watch_home_gallery_upload_cleanup_v1(text[],text)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_home_gallery_upload_cleanup_v1(text[],text)
  to service_role;

comment on table farm_watch.home_gallery_uploads_v1 is
  'Owner/admin-only staging of processed WMW WebP media. NOT included in legacy static home gallery list or viewer slideshow.';

commit;
