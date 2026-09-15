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

  if (type === 'school_district_portfolio') {
    return {
      contract_version: 'school_district_portfolio_map_v1', account_name: 'Scott County School District 2', district_key: 'IN-7255', nces_district_id: '1810020', dlgf_unit_id: '1288', dlgf_unit_code: '7255', scope: 'documented_public_school_roster', facility_source_slug: 'nces-edge-public-schools-2425', signal_source_slug: 'indiana-dlgf-school-capital-projects', relationship: 'district_membership', generated_at: '2026-09-15T12:00:00Z', facility_observed_at: '2026-09-06T05:21:27.854428Z', capital_plan_observed_at: '2026-09-06T05:06:41.657508Z',
      members: [
        ['181002001609','Johnson Elementary School','4235 E SR 256','Scottsburg','47170',-85.6989,38.7373],
        ['181002001610','Lexington Elementary School','7980 E Walnut St','Lexington','47138',-85.6264,38.6524],
        ['181002001608','Scottsburg Elem School','49 N Hyland St','Scottsburg','47170',-85.7757,38.6866],
        ['181002001611','Scottsburg Middle School','425 S 3rd St','Scottsburg','47170',-85.763562,38.680269],
        ['181002001612','Scottsburg Senior High School','500 S Gardner','Scottsburg','47170',-85.781081,38.680638],
        ['181002001614','Vienna-Finley Elementary School','445 Ivan Rogers Dr','Scottsburg','47170',-85.7661,38.6503],
      ].map(([id,name,address,city,zip,lon,lat]) => ({ id,name,address,city,state_code:'IN',zip,point:{type:'Point',coordinates:[lon,lat]},school_year:'2024-2025',observed_at:'2026-09-06T05:21:27.854428Z' })),
      capital_signals: [{ id:'dlgf:10695:roof-project',kind:'district_roof_capital_project',project_title:'Roof Project',estimated_cost:500000,start_date_text:'Summer of 2027',end_date_text:'Summer of 2029',plan_year:2027,plan_id:'10695',plan_submitted_at:'2026-08-12T08:28:01Z',extraction_confidence:'high',site_attribution:'district_only_unresolved',observed_at:'2026-09-06T05:06:41.657508Z' }],
    }
  }

  if (type === 'municipal_facilities_portfolio') {
    return {
      contract_version:'municipal_facilities_portfolio_map_v1',account_name:'Louisville Metro Government',organization_id:'1caf010b-5ac3-4fca-bf76-d6eefbb192ae',scope:'documented_civic_location_subset',facility_source_slug:'louisville-metro-government-locations',geometry_source_slug:'fema-usa-structures-current',signal_source_kind:'scout_opportunity_search_spine',relationship:'official_government_location_listing',generated_at:'2026-09-15T21:45:00Z',facility_observed_at:'2026-09-15T21:40:00Z',geometry_observed_at:'2026-09-06T04:27:38.317951Z',signal_observed_at:'2026-09-15T21:27:10.874840Z',
      members:[
        ['city-hall','City Hall','601 West Jefferson Street',-85.7608333212202,38.2546422629059,'no_site_signal_linked'],
        ['metrosafe-building','MetroSafe Building','410 S. 5th Street',-85.7592591792784,38.2529485594949,'no_site_signal_linked'],
        ['police-headquarters','Police Headquarters','601 W. Chestnut Street',-85.7619630633563,38.2497496557364,'no_site_signal_linked'],
        ['records-management-archives','Records Management & Archives','635 Industry Road',-85.7740749981969,38.2214560226262,'no_site_signal_linked'],
        ['health-wellness','Health & Wellness','400 East Gray Street',-85.7465172343292,38.246038944962,'no_site_signal_linked'],
        ['judicial-center','Judicial Center','700 West Jefferson Street',-85.761753796353,38.253918943988,'site_signal_present'],
      ].map(([id,name,address,lon,lat,signal_state])=>({id,name,address,city:'Louisville',state_code:'KY',point:{type:'Point',coordinates:[lon,lat]},geometry_source_slug:'fema-usa-structures-current',geometry_match_method:'exact_address',signal_state,observed_at:'2026-09-15T21:40:00Z'})),
      member_signals:[{id:'exterior_cleaning:7c890eed-6773-48be-b96e-0aecb646719b',kind:'member_cleaning_need_proxy',member_id:'judicial-center',member_name:'Judicial Center',signal_strength:'medium',confidence:0.52,why_now:'Moderate proximity to an operating distillery/ethanol-vapor anchor. Use as prospecting/inspection evidence only until visible staining is verified.',procurement_status:'procurement_route_available',buyer_contact_status:'durable_route_available',site_attribution:'judicial_center_only',observed_at:'2026-09-13T11:20:00.076105Z',refreshed_at:'2026-09-15T21:27:10.874840Z'}],
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
