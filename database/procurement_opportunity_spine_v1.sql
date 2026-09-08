-- Scout procurement opportunity spine v1
-- Internal evidence infrastructure for current solicitations/RFPs.
-- This does NOT expose procurement records to the model or score them as leads.

create schema if not exists procurement;

create table if not exists procurement.opportunities (
  id uuid primary key default gen_random_uuid(),
  source_record_id uuid not null references ingest.raw_records(id) on delete restrict,
  source_slug text not null references ingest.sources(slug) on update cascade on delete restrict,
  source_native_id text not null,
  jurisdiction text not null,
  solicitation_number text,
  title text not null,
  notice_type text,
  base_type text,
  buyer_name text,
  buyer_subtier text,
  buyer_office text,
  buyer_code text,
  naics_code text,
  psc_code text,
  set_aside text,
  posted_at timestamptz,
  response_deadline timestamptz,
  archive_at timestamptz,
  active boolean,
  place_city text,
  place_state text,
  place_zip text,
  place_country text,
  description text,
  canonical_url text,
  contact jsonb not null default '{}'::jsonb,
  award jsonb not null default '{}'::jsonb,
  attributes jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_slug, source_native_id)
);

create index if not exists procurement_opportunities_active_deadline_idx on procurement.opportunities(active, response_deadline);
create index if not exists procurement_opportunities_state_idx on procurement.opportunities(place_state, active);
create index if not exists procurement_opportunities_solicitation_idx on procurement.opportunities(solicitation_number);
create index if not exists procurement_opportunities_source_idx on procurement.opportunities(source_slug, last_observed_at desc);

comment on table procurement.opportunities is
  'Internal normalized current procurement notices. Raw source versions remain in ingest.raw_records; this table points to the latest observed version.';

insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,notes
) values
  ('indiana-idoa-current-opportunities','Indiana IDOA Current Business Opportunities','Indiana Department of Administration','procurement_opportunities','Indiana state government','official HTML current-opportunity table + linked bid documents','daily','state_authoritative','active','https://www.in.gov/idoa/procurement/current-business-opportunities/','Current solicitations. Pair solicitation numbers with indiana-idoa-award-recommendations for post-award vendor/contract evidence.'),
  ('louisville-renewable-contracts-archive','Louisville Metro Renewable Contracts Archive','Louisville Metro Government','procurement_contracts','Louisville Metro, Kentucky','official archived renewable-contract report','archived','local_authoritative','source_identified','https://louisvilleky.gov/government/procurement','Historical confirmed renewable-contract evidence; archived and not suitable as a live-current feed without a newer authoritative endpoint.'),
  ('ohiobuys-public-solicitations','OhioBuys Public Solicitations and Contracts','State of Ohio','procurement_opportunities','Ohio state government','official OhioBuys public portal; machine-readable endpoint pending','continuous','state_authoritative','source_identified','https://ohiobuys.ohio.gov/','Includes public solicitations, awarded RFP/ITB records and master maintenance agreements. Do not automate around anti-bot/security controls; resolve an approved machine-readable source first.')
on conflict (slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  notes=excluded.notes,
  updated_at=now();

create or replace function public.internal_ingest_procurement_opportunity_batch(
  p_source_slug text,
  p_records jsonb,
  p_observed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source_id uuid;
  v_raw_inserted integer := 0;
  v_upserted integer := 0;
begin
  select id into v_source_id from ingest.sources where slug=p_source_slug;
  if v_source_id is null then
    raise exception 'Unknown procurement source slug: %',p_source_slug;
  end if;
  if p_records is null or jsonb_typeof(p_records)<>'array' then
    raise exception 'p_records must be a JSON array';
  end if;

  with incoming as (
    select * from jsonb_to_recordset(p_records) as x(
      source_native_id text, source_url text, content_hash text,
      normalized jsonb, source_payload jsonb
    )
  )
  insert into ingest.raw_records(
    source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,
    parser_version,parse_status,provisional_entity_type,within_pilot_radius,raw_payload
  )
  select
    v_source_id,i.source_native_id,i.source_url,now(),p_observed_at,i.content_hash,
    'procurement-opportunity-v1','normalized','procurement_opportunity',
    case
      when upper(coalesce(i.normalized->>'place_state','')) in ('KY','IN','OH') then true
      when p_source_slug='indiana-idoa-current-opportunities' then true
      else false
    end,
    jsonb_build_object(
      'normalized',coalesce(i.normalized,'{}'::jsonb),
      'source',coalesce(i.source_payload,'{}'::jsonb)
    )
  from incoming i
  where nullif(btrim(i.source_native_id),'') is not null
    and nullif(btrim(i.content_hash),'') is not null
  on conflict(source_id,source_native_id,content_hash) do nothing;
  get diagnostics v_raw_inserted=row_count;

  with incoming as (
    select * from jsonb_to_recordset(p_records) as x(
      source_native_id text, source_url text, content_hash text,
      normalized jsonb, source_payload jsonb
    )
  ), resolved as (
    select distinct on(i.source_native_id) i.*,r.id raw_id
    from incoming i
    join ingest.raw_records r
      on r.source_id=v_source_id
     and r.source_native_id=i.source_native_id
     and r.content_hash=i.content_hash
    where nullif(btrim(i.source_native_id),'') is not null
    order by i.source_native_id,r.retrieved_at desc,r.created_at desc
  )
  insert into procurement.opportunities(
    source_record_id,source_slug,source_native_id,jurisdiction,solicitation_number,
    title,notice_type,base_type,buyer_name,buyer_subtier,buyer_office,buyer_code,
    naics_code,psc_code,set_aside,posted_at,response_deadline,archive_at,active,
    place_city,place_state,place_zip,place_country,description,canonical_url,
    contact,award,attributes,first_observed_at,last_observed_at,updated_at
  )
  select
    r.raw_id,p_source_slug,r.source_native_id,
    coalesce(nullif(r.normalized->>'jurisdiction',''),'unknown'),
    nullif(r.normalized->>'solicitation_number',''),
    coalesce(nullif(r.normalized->>'title',''),r.source_native_id),
    nullif(r.normalized->>'notice_type',''),nullif(r.normalized->>'base_type',''),
    nullif(r.normalized->>'buyer_name',''),nullif(r.normalized->>'buyer_subtier',''),
    nullif(r.normalized->>'buyer_office',''),nullif(r.normalized->>'buyer_code',''),
    nullif(r.normalized->>'naics_code',''),nullif(r.normalized->>'psc_code',''),
    nullif(r.normalized->>'set_aside',''),
    nullif(r.normalized->>'posted_at','')::timestamptz,
    nullif(r.normalized->>'response_deadline','')::timestamptz,
    nullif(r.normalized->>'archive_at','')::timestamptz,
    case when r.normalized ? 'active' then (r.normalized->>'active')::boolean else null end,
    nullif(r.normalized->>'place_city',''),nullif(upper(r.normalized->>'place_state'),''),
    nullif(r.normalized->>'place_zip',''),nullif(r.normalized->>'place_country',''),
    nullif(r.normalized->>'description',''),
    coalesce(nullif(r.normalized->>'canonical_url',''),nullif(r.source_url,'')),
    coalesce(r.normalized->'contact','{}'::jsonb),
    coalesce(r.normalized->'award','{}'::jsonb),
    coalesce(r.normalized->'attributes','{}'::jsonb),
    p_observed_at,p_observed_at,now()
  from resolved r
  on conflict(source_slug,source_native_id) do update set
    source_record_id=excluded.source_record_id,
    jurisdiction=excluded.jurisdiction,
    solicitation_number=excluded.solicitation_number,
    title=excluded.title,
    notice_type=excluded.notice_type,
    base_type=excluded.base_type,
    buyer_name=excluded.buyer_name,
    buyer_subtier=excluded.buyer_subtier,
    buyer_office=excluded.buyer_office,
    buyer_code=excluded.buyer_code,
    naics_code=excluded.naics_code,
    psc_code=excluded.psc_code,
    set_aside=excluded.set_aside,
    posted_at=excluded.posted_at,
    response_deadline=excluded.response_deadline,
    archive_at=excluded.archive_at,
    active=excluded.active,
    place_city=excluded.place_city,
    place_state=excluded.place_state,
    place_zip=excluded.place_zip,
    place_country=excluded.place_country,
    description=excluded.description,
    canonical_url=excluded.canonical_url,
    contact=excluded.contact,
    award=excluded.award,
    attributes=excluded.attributes,
    last_observed_at=excluded.last_observed_at,
    updated_at=now();
  get diagnostics v_upserted=row_count;

  return jsonb_build_object(
    'source_slug',p_source_slug,
    'received',jsonb_array_length(p_records),
    'raw_inserted',v_raw_inserted,
    'opportunities_upserted',v_upserted
  );
end;
$$;

revoke all on function public.internal_ingest_procurement_opportunity_batch(text,jsonb,timestamptz) from public;
revoke all on function public.internal_ingest_procurement_opportunity_batch(text,jsonb,timestamptz) from anon,authenticated;
grant execute on function public.internal_ingest_procurement_opportunity_batch(text,jsonb,timestamptz) to service_role;

create or replace view procurement.v_facilities_contract_signals as
with base as (
  select o.*,
    lower(concat_ws(' ',o.title,o.description,o.notice_type,o.base_type,o.buyer_name,o.buyer_subtier,o.buyer_office)) corpus
  from procurement.opportunities o
), flags as (
  select b.*,
    (b.corpus ~ '(facilit(y|ies) (management|maintenance|support|operations)|base operations support|operations and maintenance|operations & maintenance|building maintenance|maintenance and repair|repair and maintenance|property management)') is_facilities_management_scope,
    (b.corpus ~ '(on[- ]call|as[- ]needed|indefinite delivery|indefinite quantity|\midiq\M|\mmatoc\M|\msatoc\M|job order contract|job[- ]order contracting|\mjoc\M|task order|requirements contract|blanket purchase|\mbpa\M)') is_on_call_vehicle,
    (b.corpus ~ '(statewide|multiple (sites|facilities|locations)|multi[- ]site|all (facilities|buildings|locations)|campus[- ]wide|base[- ]wide|installation[- ]wide|portfolio|district[- ]wide|system[- ]wide)') is_multi_asset_scope,
    (b.corpus ~ '(paint(ing)?|repaint|coat(ing)?|pressure wash|power wash|exterior clean|facade|façade|masonry|tuckpoint|waterproof|sealant|caulk|roof|building envelope|concrete clean)') is_surface_work_scope,
    (b.source_slug='sam-opportunities' and b.corpus ~ '(department of defense|department of the army|dept of the army|department of the navy|dept of the navy|department of the air force|dept of the air force|defense logistics agency|u\.s\. army|us army|u\.s\. navy|us navy|u\.s\. air force|us air force|marine corps|army corps of engineers|usace|space force)') is_federal_military
  from base b
)
select f.*,
  (f.is_facilities_management_scope and (f.is_on_call_vehicle or f.is_multi_asset_scope)) is_portfolio_unlock_candidate,
  case
    when f.is_facilities_management_scope and f.is_multi_asset_scope then 'portfolio_or_multi_asset'
    when f.is_facilities_management_scope and f.is_on_call_vehicle then 'on_call_vehicle_scope_unresolved'
    when f.is_facilities_management_scope then 'facility_scope_unresolved'
    when f.is_surface_work_scope then 'surface_work_only'
    else 'other'
  end scope_interpretation
from flags f;

create or replace view procurement.v_indiana_opportunity_award_bridge as
select
  o.id opportunity_id,o.source_record_id,o.source_native_id current_event_id,
  o.solicitation_number,o.title opportunity_title,o.response_deadline,
  a.id award_event_id,a.award_date,a.title award_title,a.recommendation_status,
  a.estimated_contract_value,a.maximum_contract_value,
  s.vendor_name,s.vendor_organization_id,s.selected_value,s.maximum_value,
  s.selection_status,s.incumbent_signal,
  case when a.id is not null then 'solicitation_number_exact' else null end match_method
from procurement.opportunities o
left join procurement.award_events a
  on o.source_slug='indiana-idoa-current-opportunities'
 and nullif(o.solicitation_number,'') is not null
 and a.event_number=o.solicitation_number
left join procurement.award_selections s on s.award_event_id=a.id
where o.source_slug='indiana-idoa-current-opportunities';

revoke all on procurement.opportunities from anon,authenticated;
revoke all on procurement.v_facilities_contract_signals from anon,authenticated;
revoke all on procurement.v_indiana_opportunity_award_bridge from anon,authenticated;
grant select,insert,update on procurement.opportunities to service_role;
grant select on procurement.v_facilities_contract_signals to service_role;
grant select on procurement.v_indiana_opportunity_award_bridge to service_role;

insert into ingest.source_quality_gates(
  source_slug,status,reason,validated_at,validation_version,metadata,updated_at
) values
  ('sam-opportunities','degraded','Registered source is unpopulated until the first bulk-extract collector validation passes.',null,'sam-opportunities-v1','{}'::jsonb,now()),
  ('indiana-idoa-current-opportunities','degraded','Current-opportunity source is unpopulated until the first live collector validation passes.',null,'indiana-idoa-current-v1','{}'::jsonb,now())
on conflict(source_slug) do update set
  status=excluded.status,
  reason=excluded.reason,
  validation_version=excluded.validation_version,
  updated_at=now();
