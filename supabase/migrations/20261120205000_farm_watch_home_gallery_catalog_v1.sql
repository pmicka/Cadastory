begin;

-- Homepage gallery catalog v1: metadata for the ten existing static WMW assets.
-- This does not move, delete, expose or replace any files. Media upload/storage
-- is deliberately a separate, independently authorized build unit.
create table farm_watch.home_gallery_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default clock_timestamp()
);

create table farm_watch.home_gallery_photos_v1 (
  property_id uuid not null references farm_watch.home_gallery_v1(property_id) on delete cascade,
  photo_number smallint not null check (photo_number between 1 and 10),
  sort_index smallint not null check (sort_index between 1 and 10),
  caption text check (caption is null or char_length(caption) <= 240),
  alt_text text check (alt_text is null or char_length(alt_text) between 1 and 240),
  focal_x smallint not null default 50 check (focal_x between 0 and 100),
  focal_y smallint not null default 50 check (focal_y between 0 and 100),
  is_visible boolean not null default true,
  primary key (property_id, photo_number)
);
create index home_gallery_photos_v1_order on farm_watch.home_gallery_photos_v1(property_id,sort_index);

alter table farm_watch.home_gallery_v1 enable row level security;
alter table farm_watch.home_gallery_v1 force row level security;
alter table farm_watch.home_gallery_photos_v1 enable row level security;
alter table farm_watch.home_gallery_photos_v1 force row level security;
revoke all on farm_watch.home_gallery_v1,farm_watch.home_gallery_photos_v1
  from public,anon,authenticated,service_role;

-- Only the WMW property currently has this exact ten-file static asset catalog.
-- The initial order is the existing slideshow order, with wmw_06.jpg as cover.
insert into farm_watch.home_gallery_v1(property_id)
select id from farm_watch.properties where slug='validation-property-01' and status='active'
on conflict do nothing;
insert into farm_watch.home_gallery_photos_v1(property_id,photo_number,sort_index)
select p.id, numbered.photo_number, numbered.position
from farm_watch.properties p
cross join lateral unnest(array[6,1,2,3,4,5,7,8,9,10]::smallint[])
  with ordinality as numbered(photo_number,position)
where p.slug='validation-property-01' and p.status='active'
on conflict do nothing;

-- The one authenticated data interface. Authentication and the *current*
-- account role are verified inside Postgres for every read/write; the UI's
-- "technical"/"viewer preview" setting has no authority here.
create function public.farm_watch_home_gallery_v1(
  p_property_slug text,
  p_action text default 'list',
  p_photo_number integer default null,
  p_expected_revision integer default null,
  p_caption text default null,
  p_alt_text text default null,
  p_focal_x integer default null,
  p_focal_y integer default null,
  p_is_visible boolean default null,
  p_order integer[] default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  account_role text;
  target_property_id uuid;
  state farm_watch.home_gallery_v1%rowtype;
  photo farm_watch.home_gallery_photos_v1%rowtype;
  photos jsonb;
begin
  if actor is null
    or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists(select 1 from auth.users where id=actor)
    or not public.farm_watch_authorize_user_v1_internal(actor) then
    raise exception 'not found' using errcode='42501';
  end if;
  account_role := public.farm_watch_get_account_role_v1_internal(actor);
  if account_role not in ('owner','admin','viewer') or account_role is null then
    raise exception 'not found' using errcode='42501';
  end if;
  select id into target_property_id from farm_watch.properties
  where slug=p_property_slug and status='active';
  if target_property_id is null then raise exception 'not found' using errcode='42501'; end if;

  if p_action='list' then
    if p_photo_number is not null or p_expected_revision is not null
      or p_caption is not null or p_alt_text is not null
      or p_focal_x is not null or p_focal_y is not null
      or p_is_visible is not null or p_order is not null then
      raise exception 'invalid list' using errcode='22023';
    end if;
    select * into state from farm_watch.home_gallery_v1 where property_id=target_property_id;
    -- Property column is explicitly qualified in queries below to avoid shadowing.
    if not found then raise exception 'not found' using errcode='42501'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'photo_number',p.photo_number,'sort_index',p.sort_index,
      'caption',p.caption,'alt_text',p.alt_text,
      'focal_x',p.focal_x,'focal_y',p.focal_y,
      'is_visible',p.is_visible
    ) order by p.sort_index,p.photo_number),'[]'::jsonb)
      into photos
    from farm_watch.home_gallery_photos_v1 p
    where p.property_id=state.property_id and (account_role in ('owner','admin') or p.is_visible);
    return jsonb_build_object('revision',state.revision,'photos',photos,
      'can_edit',account_role in ('owner','admin'),'source','legacy-static-v1');
  end if;

  if account_role not in ('owner','admin') then raise exception 'not found' using errcode='42501'; end if;
  if p_action not in ('update','reorder') or p_action is null then
    raise exception 'invalid action' using errcode='22023';
  end if;
  select * into state from farm_watch.home_gallery_v1 g
  where g.property_id=target_property_id for update;
  if not found then raise exception 'not found' using errcode='42501'; end if;
  if p_expected_revision is null or p_expected_revision<>state.revision then
    raise exception 'gallery changed; reload' using errcode='PT409';
  end if;

  if p_action='update' then
    if p_photo_number is null or p_photo_number not between 1 and 10
      or p_order is not null
      or (p_caption is null and p_alt_text is null and p_focal_x is null
          and p_focal_y is null and p_is_visible is null)
      or (p_caption is not null and char_length(btrim(p_caption))>240)
      or (p_alt_text is not null and char_length(btrim(p_alt_text))>240)
      or (p_focal_x is not null and p_focal_x not between 0 and 100)
      or (p_focal_y is not null and p_focal_y not between 0 and 100) then
      raise exception 'invalid gallery update' using errcode='22023';
    end if;
    select * into photo from farm_watch.home_gallery_photos_v1 p
      where p.property_id=state.property_id and p.photo_number=p_photo_number for update;
    if not found then raise exception 'not found' using errcode='42501'; end if;
    if p_is_visible=false and photo.is_visible and
      (select count(*) from farm_watch.home_gallery_photos_v1 p
        where p.property_id=state.property_id and p.is_visible)=1 then
      raise exception 'at least one photo must remain visible' using errcode='PT409';
    end if;
    update farm_watch.home_gallery_photos_v1 p set
      caption=case when p_caption is null then p.caption else nullif(btrim(p_caption),'') end,
      alt_text=case when p_alt_text is null then p.alt_text else nullif(btrim(p_alt_text),'') end,
      focal_x=coalesce(p_focal_x,p.focal_x),
      focal_y=coalesce(p_focal_y,p.focal_y),
      is_visible=coalesce(p_is_visible,p.is_visible)
    where p.property_id=state.property_id and p.photo_number=p_photo_number;
  else
    if p_photo_number is not null or p_caption is not null or p_alt_text is not null
      or p_focal_x is not null or p_focal_y is not null or p_is_visible is not null
      or p_order is null or cardinality(p_order)<>10
      or exists(select 1 from unnest(p_order) n where n is null or n not between 1 and 10)
      or (select count(distinct n) from unnest(p_order) n)<>10
      or (select count(*) from farm_watch.home_gallery_photos_v1 p
          where p.property_id=state.property_id)<>10 then
      raise exception 'invalid gallery order' using errcode='22023';
    end if;
    update farm_watch.home_gallery_photos_v1 p
      set sort_index=array_position(p_order,p.photo_number)
      where p.property_id=state.property_id;
  end if;
  update farm_watch.home_gallery_v1 g
    set revision=g.revision+1,updated_at=clock_timestamp()
    where g.property_id=state.property_id returning * into state;
  return jsonb_build_object('revision',state.revision,'updated',true);
end $$;

revoke all on function public.farm_watch_home_gallery_v1(
  text,text,integer,integer,text,text,integer,integer,boolean,integer[]
) from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_home_gallery_v1(
  text,text,integer,integer,text,text,integer,integer,boolean,integer[]
) to authenticated;

comment on table farm_watch.home_gallery_photos_v1 is
  'Editable metadata only for ten pre-existing WMW website photos. Not a Storage bucket, public API, or scientific observation.';
commit;
