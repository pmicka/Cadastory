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

  const resolvedMembers = hotel
    ? [
        {
          id: '00000000-0000-4000-8000-000000000001',
          name: 'Residence Inn Louisville Airport',
          address: '700 Phillips Ln', city: 'Louisville', state_code: 'KY', brands: ['Residence Inn by Marriott'],
          point: { type: 'Point', coordinates: [-85.744392935, 38.190277203] },
          resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
          within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
        },
        {
          id: '00000000-0000-4000-8000-000000000002',
          name: 'Courtyard Cincinnati Airport',
          address: '3990 Olympic Blvd', city: 'Erlanger', state_code: 'KY', brands: ['Courtyard by Marriott'],
          point: { type: 'Point', coordinates: [-84.628490281, 39.052913717] },
          resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
          within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
        },
      ]
    : [
        {
          id: '00000000-0000-4000-8000-000000000001',
          name: 'Don Franklin Hardin County Ford',
          address: '461 S Dixie Blvd', city: 'Radcliff', state_code: 'KY', brands: ['Ford'],
          point: { type: 'Point', coordinates: [-85.934878659, 37.835096407] },
          resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
          within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
        },
        {
          id: '00000000-0000-4000-8000-000000000002',
          name: 'Don Franklin Campbellsville Chevrolet GMC',
          address: '200 N Bypass Rd', city: 'Campbellsville', state_code: 'KY', brands: ['Chevrolet', 'GMC'],
          point: { type: 'Point', coordinates: [-85.361848036, 37.345356171] },
          resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
          within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
        },
        {
          id: '00000000-0000-4000-8000-000000000003',
          name: 'Genesis of Lexington',
          address: '3390 Richmond Rd', city: 'Lexington', state_code: 'KY', brands: ['Genesis'],
          point: { type: 'Point', coordinates: [-84.441854524, 37.996077895] },
          resolution_state: 'single_building_resolved', resolved_building_count: 1, link_confidence: 0.99,
          within_pilot_radius: true, observed_at: '2026-09-15T11:00:00Z',
        },
      ]

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
      ...resolvedMembers,
      {
        id: '00000000-0000-4000-8000-000000000099',
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
