export function makePortfolioPayload(type) {
  if (type === 'water_utility_portfolio') {
    return {
      contract_version: 'water_utility_portfolio_map_v1',
      account_name: 'Warren County Water District',
      organization_id: '046baf25-53b3-4524-91d0-b115bb62161e',
      pwsid: 'KY1140487',
      scope: 'documented_roster',
      source_slug: 'ky-kia-water-tanks',
      relationship: 'system_membership',
      generated_at: '2026-09-15T12:00:00Z',
      source_modified_at: '2023-06-12T10:17:05Z',
      members: [
        { id: 'WRIS-1', name: 'Tank One', pwsid: 'KY1140487', morphology: 'elevated', point: { type: 'Point', coordinates: [-86.604253186103, 36.9089936423351] }, service_state: 'unverified', within_pilot_radius: true, source_modified_at: '2023-06-12T10:17:05Z', signals: [] },
        { id: 'WRIS-2', name: 'Tank Two', pwsid: 'KY1140487', morphology: 'ground_storage', point: { type: 'Point', coordinates: [-86.1720916450137, 37.1328579829601] }, service_state: 'documented_not_in_service', within_pilot_radius: true, source_modified_at: '2023-06-12T10:17:05Z', signals: [{ id: 'water_tank:2', kind: 'historical_rehab_record', observed_at: '2021-12-10T09:40:38Z' }] },
      ],
    }
  }

  const hotel = type === 'hotel_management_portfolio'
  if (!hotel && type !== 'dealership_group_portfolio') throw new Error(`No portfolio fixture registered for ${type}`)
  return {
    contract_version: hotel ? 'hotel_management_portfolio_map_v1' : 'dealership_group_portfolio_map_v1',
    account_name: hotel ? 'Commonwealth Hotels' : 'Don Franklin Auto',
    organization_id: hotel ? '6513f69a-bb53-4706-854b-bf9f7ba3064b' : '046baf25-53b3-4524-91d0-b115bb62161e',
    scope: 'documented_operating_roster',
    source_slug: hotel ? 'commonwealth-hotels-managed-portfolio' : 'don-franklin-auto-locations',
    relationship: hotel ? 'manages' : 'operates',
    target_kind: 'site_member',
    map_semantics: hotel ? 'documented_operating_hotel_portfolio' : 'documented_operating_site_portfolio',
    evidence_boundary: hotel ? 'first-party hotel-management roster plus resolved building crosswalks' : 'first-party dealership roster plus resolved building crosswalks',
    generated_at: '2026-09-15T12:00:00Z',
    observed_at: '2026-09-15T11:00:00Z',
    contact_route_available: true,
    operations_route_available: hotel,
    procurement_route_available: hotel,
    vendor_route_proven: false,
    current_need_scan_complete: true,
    members: [
      {
        id: '00000000-0000-4000-8000-000000000001',
        name: hotel ? 'Hampton Inn Louisville Airport' : 'Don Franklin Lexington Nissan',
        address: '1 Resolved Way', city: hotel ? 'Louisville' : 'Lexington', state_code: 'KY',
        brands: hotel ? ['Hampton by Hilton'] : ['Nissan'],
        point: { type: 'Point', coordinates: hotel ? [-85.743168701, 38.190898942] : [-84.442756947, 37.996630551] },
        resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
        within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
      },
      {
        id: '00000000-0000-4000-8000-000000000002',
        name: hotel ? 'Tru by Hilton Louisville Airport' : 'Don Franklin Lexington Hyundai',
        address: '2 Unresolved Way', city: hotel ? 'Louisville' : 'Lexington', state_code: 'KY',
        brands: hotel ? ['Tru by Hilton'] : ['Hyundai'],
        point: { type: 'unresolved' },
        resolution_state: 'unresolved', resolved_building_count: 0, link_confidence: null,
        within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
      },
    ],
  }
}
