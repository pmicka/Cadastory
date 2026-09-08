-- Fix PostgreSQL POSIX regex compatibility in the physical facilities classifier.
-- Replaces the unsupported non-capturing group with a normal capture group.

create or replace view research.v_physical_facilities_contract_signals as
with base as (
  select
    f.*,
    coalesce(nullif(btrim(f.solicitation_number),''),'notice:' || f.source_native_id) as acquisition_native_key,
    coalesce(nullif(btrim(f.buyer_office),''),nullif(btrim(f.buyer_subtier),''),nullif(btrim(f.buyer_name),''),'unknown') as buyer_family_key,
    (f.corpus ~ '(facility|facilities|building|buildings|installation|installations|campus|campuses|base|bases|barracks|hangar|warehouse|real property|grounds|civil works|roof|roofs|building envelope|utility plant|wastewater treatment|water treatment|parking structure|parking garage|school|hospital|clinic)') as has_physical_asset_context,
    (f.corpus ~ '(maintenance|repair|renovation|construction|painting|repaint|coating|roofing|masonry|waterproof|janitorial|cleaning|groundskeeping|operations and maintenance|facility support|facilities support|base operations support)') as has_physical_work_context,
    (coalesce(f.naics_code,'') ~ '^(236|237|238)' or coalesce(f.naics_code,'') in ('561210','561720','561730')) as has_physical_trade_naics,
    (f.corpus ~ '(base operations support|facilit(y|ies) support services|facility maintenance|facilities maintenance|building maintenance|real property maintenance|medical facilities operations and maintenance|operations and maintenance.{0,60}(facilit(y|ies)|building|real property|installation|base)|(facilit(y|ies)|building|real property|installation|base).{0,60}operations and maintenance)') as has_broad_physical_fm_phrase,
    (f.corpus ~ '((construction|renovation|repair|roofing|painting|coating).{0,80}(various|multiple|all).{0,50}(facilit(y|ies)|buildings|installations|sites|locations))|((various|multiple|all).{0,50}(facilit(y|ies)|buildings|installations|sites|locations).{0,80}(construction|renovation|repair|roofing|painting|coating)))') as has_multi_site_physical_trade_phrase,
    (f.corpus ~ '(information technology|software|cyber|network operations|application support|identity management|help desk|cloud services|windows 11|technology upgrade|fire alarm reporting system|aerial target|aircraft maintenance|vehicle maintenance|generator repair|kitchen equipment|medical equipment|weapon systems|training services|administrative support|human resources)') as has_nonphysical_or_equipment_domain,
    (f.corpus ~ '(construction|renovation|roof|roofing|building envelope|real property|civil works|painting|coating|masonry|waterproof)') as has_hard_physical_trade_scope
  from procurement.v_facilities_contract_signals f
), classified as (
  select
    b.*,
    case
      when b.has_nonphysical_or_equipment_domain
           and not (b.has_physical_trade_naics and b.has_hard_physical_trade_scope)
        then 'nonphysical_om_or_equipment'
      when b.is_on_call_vehicle
           and b.has_multi_site_physical_trade_phrase
           and (b.has_physical_trade_naics or b.is_surface_work_scope or b.has_hard_physical_trade_scope)
        then 'multi_site_physical_trade_vehicle'
      when (b.is_on_call_vehicle or b.is_multi_asset_scope)
           and b.has_broad_physical_fm_phrase
           and (b.has_physical_asset_context or b.has_physical_trade_naics)
        then 'broad_physical_facilities_vehicle'
      when b.has_physical_asset_context and b.has_physical_work_context
        then 'specific_physical_facility_work'
      else 'scope_unresolved'
    end as physical_scope_class
  from base b
)
select
  c.*,
  (c.physical_scope_class in ('broad_physical_facilities_vehicle','multi_site_physical_trade_vehicle')) as is_physical_portfolio_unlock_candidate,
  case
    when c.physical_scope_class = 'broad_physical_facilities_vehicle' then 'strong'
    when c.physical_scope_class = 'multi_site_physical_trade_vehicle' then 'strong_trade_vehicle'
    when c.physical_scope_class = 'specific_physical_facility_work' then 'asset_specific_only'
    when c.physical_scope_class = 'nonphysical_om_or_equipment' then 'rejected_nonphysical'
    else 'unresolved'
  end as physical_scope_strength
from classified c;

revoke all on research.v_physical_facilities_contract_signals from anon,authenticated;
grant select on research.v_physical_facilities_contract_signals to service_role;
