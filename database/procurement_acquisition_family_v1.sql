-- Scout procurement acquisition-family normalization v1
-- Deduplicates notice/amendment versions into one acquisition family and separates
-- market research, solicitation, and confirmed award evidence. Internal only.

create or replace view procurement.v_acquisition_families as
with flagged as (
  select
    f.*,
    coalesce(
      nullif(btrim(f.solicitation_number),''),
      'notice:' || f.source_native_id
    ) as acquisition_native_key,
    (nullif(f.award->>'number','') is not null or nullif(f.award->>'awardee','') is not null) as has_award_payload,
    lower(concat_ws(' ',f.notice_type,f.base_type,f.title)) as stage_corpus
  from procurement.v_facilities_contract_signals f
), grouped as (
  select
    source_slug,
    jurisdiction,
    acquisition_native_key,
    coalesce(nullif(btrim(buyer_office),''),nullif(btrim(buyer_subtier),''),nullif(btrim(buyer_name),''),'unknown') as buyer_family_key,
    md5(concat_ws('|',source_slug,coalesce(nullif(btrim(buyer_office),''),nullif(btrim(buyer_subtier),''),nullif(btrim(buyer_name),''),'unknown'),acquisition_native_key)) as acquisition_family_key,
    max(solicitation_number) filter (where nullif(btrim(solicitation_number),'') is not null) as solicitation_number,
    (array_agg(title order by posted_at desc nulls last,last_observed_at desc))[1] as title,
    (array_agg(notice_type order by posted_at desc nulls last,last_observed_at desc))[1] as latest_notice_type,
    (array_agg(base_type order by posted_at desc nulls last,last_observed_at desc))[1] as latest_base_type,
    (array_agg(buyer_name order by posted_at desc nulls last,last_observed_at desc))[1] as buyer_name,
    (array_agg(buyer_subtier order by posted_at desc nulls last,last_observed_at desc))[1] as buyer_subtier,
    (array_agg(buyer_office order by posted_at desc nulls last,last_observed_at desc))[1] as buyer_office,
    (array_agg(place_city order by posted_at desc nulls last,last_observed_at desc))[1] as place_city,
    (array_agg(place_state order by posted_at desc nulls last,last_observed_at desc))[1] as place_state,
    min(posted_at) as first_posted_at,
    max(posted_at) as latest_posted_at,
    max(response_deadline) as latest_response_deadline,
    max(archive_at) as latest_archive_at,
    min(first_observed_at) as first_observed_at,
    max(last_observed_at) as last_observed_at,
    count(*) as notice_version_count,
    count(distinct source_native_id) as distinct_notice_id_count,
    bool_or(is_facilities_management_scope) as is_facilities_management_scope,
    bool_or(is_on_call_vehicle) as is_on_call_vehicle,
    bool_or(is_multi_asset_scope) as is_multi_asset_scope,
    bool_or(is_surface_work_scope) as is_surface_work_scope,
    bool_or(is_federal_military) as is_federal_military,
    bool_or(is_portfolio_unlock_candidate) as is_portfolio_unlock_candidate,
    bool_or(has_award_payload) as has_confirmed_award_payload,
    bool_or(stage_corpus ~ '(award notice|award$|justification.*award)') as has_award_notice,
    bool_or(stage_corpus ~ '(solicitation|combined synopsis|invitation for bid|request for proposal|\mrfp\M|\mitb\M|\mifb\M)') as has_solicitation_notice,
    bool_or(stage_corpus ~ '(presolicitation|pre-solicitation)') as has_presolicitation_notice,
    bool_or(stage_corpus ~ '(sources sought|request for information|\mrfi\M|market research)') as has_market_research_notice,
    array_remove(array_agg(distinct nullif(award->>'number','')),null) as award_numbers,
    array_remove(array_agg(distinct nullif(award->>'awardee','')),null) as awardees,
    array_remove(array_agg(distinct source_native_id),null) as notice_ids
  from flagged
  group by
    source_slug,
    jurisdiction,
    acquisition_native_key,
    coalesce(nullif(btrim(buyer_office),''),nullif(btrim(buyer_subtier),''),nullif(btrim(buyer_name),''),'unknown')
)
select
  g.*,
  case
    when g.has_confirmed_award_payload or g.has_award_notice then 'awarded'
    when g.has_solicitation_notice then 'solicitation'
    when g.has_presolicitation_notice then 'presolicitation'
    when g.has_market_research_notice then 'market_research'
    else 'other_notice'
  end as procurement_stage,
  (g.latest_response_deadline is not null and g.latest_response_deadline >= now()) as response_window_open,
  case
    when not g.is_portfolio_unlock_candidate then 'not_portfolio_unlock'
    when g.has_confirmed_award_payload or g.has_award_notice then 'confirmed_awarded_vehicle'
    when g.has_solicitation_notice and g.latest_response_deadline >= now() then 'open_portfolio_solicitation'
    when g.has_solicitation_notice then 'closed_or_historical_portfolio_solicitation'
    when g.has_presolicitation_notice then 'presolicitation_portfolio_signal'
    when g.has_market_research_notice then 'market_research_portfolio_signal'
    else 'scope_requires_review'
  end as portfolio_unlock_stage,
  case
    when g.is_portfolio_unlock_candidate and (g.has_confirmed_award_payload or g.has_award_notice) then 'strong'
    when g.is_portfolio_unlock_candidate and g.has_solicitation_notice and g.latest_response_deadline >= now() then 'strong_preaward'
    when g.is_portfolio_unlock_candidate and (g.has_presolicitation_notice or g.has_market_research_notice) then 'early'
    when g.is_portfolio_unlock_candidate then 'historical_or_unresolved'
    else 'none'
  end as portfolio_evidence_strength
from grouped g;

comment on view procurement.v_acquisition_families is
  'Internal procurement evidence: one row per buyer+solicitation family, deduplicating SAM/other notice versions and preserving stage/award semantics.';

create or replace view procurement.v_portfolio_unlock_acquisitions as
select *
from procurement.v_acquisition_families
where is_portfolio_unlock_candidate;

comment on view procurement.v_portfolio_unlock_acquisitions is
  'Internal candidate portfolio-maintenance vehicles. A row is not permission to fan out to facilities; asset propagation requires explicit portfolio/site scope resolution.';

revoke all on procurement.v_acquisition_families from anon,authenticated;
revoke all on procurement.v_portfolio_unlock_acquisitions from anon,authenticated;
grant select on procurement.v_acquisition_families to service_role;
grant select on procurement.v_portfolio_unlock_acquisitions to service_role;
