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

  const grouped = {
    bridge_agency_portfolio:{account:'Louisville Metro Department of Public Works',group_kind:'agency_asset_portfolio',source_kind:'bridge',relationship:'resolved transportation-agency relationship on current bridge evidence',geo:'Louisville / Jefferson County, Kentucky',role:'bridge_owner_or_transportation_agency',contact:'durable_route_available',procurement:'durable_contact_available',why:'Use the grouped condition and inspection evidence to prioritize account research across the agency bridge set without treating condition records as procurement or work availability.',guardrail:'Bridge condition and inspection evidence supports qualification only. The resolved buyer relationship is recorded as bridge owner or transportation agency and must not be narrowed to legal ownership without separate evidence. Scout is not making a structural-engineering determination or asserting procurement, access, buyer intent, or work availability.',bounds:[-85.883611,38.060556,-85.4225,38.317222],points:[[-85.883611,38.060556],[-85.4225,38.317222]],evidence:78,organization_type:'municipal_public_works'},
    railroad_crossing_network:{account:'Louisville & Indiana Railroad Company',group_kind:'railroad_crossing_network',source_kind:'rail_crossing_context',relationship:'resolved railroad relationship on current crossing evidence',geo:'Louisville-to-Indianapolis corridor crossing evidence',role:'railroad_or_public_road_owner',contact:'durable_route_available',procurement:'durable_contact_available',why:'Use crossing traffic, train-movement, protection, and incident-history context to prioritize account and inspection research across the documented crossing set.',guardrail:'FRA crossing records support account and inspection research only. Point membership does not define railroad property, track topology, right-of-way, safe operating airspace, maintenance need, access permission, procurement, or authorization to work near rail operations.',bounds:[-86.12255,38.28283,-85.74673,39.66493],points:[[-86.12255,38.28283],[-85.74673,39.66493]],evidence:22,organization_type:'railroad'},
    construction_contractor_portfolio:{account:'Miranda Construction LLC',group_kind:'contractor_project_portfolio',source_kind:'construction_window',relationship:'permit-named contractor relationship on current construction evidence',geo:'Louisville / Jefferson County construction projects',role:'owner_gc_or_project_team',contact:'durable_route_available',procurement:'durable_contact_available',why:'Use the deduplicated permit-derived project set to research repeat account potential and project timing without converting permit status into field-observed progress or buyer intent.',guardrail:'The relationship is based on contractor naming in permit-derived evidence. It does not prove prime-contract authority, project control, active drone scope, field-observed stage, procurement, site access, buyer intent, or work availability.',bounds:[-85.75361665,38.12908822,-85.44597496,38.26927504],points:[[-85.75361665,38.12908822],[-85.44597496,38.26927504]],evidence:23,organization_type:'general_contractor'},
    telecom_registration_portfolio:{account:'The Towers, LLC',group_kind:'telecom_registration_portfolio',source_kind:'telecom_change',relationship:'FCC-record owner/operator relationship on current registration evidence',geo:'Kentucky / Indiana FCC ASR registration evidence',role:'registered_owner_or_operator',contact:'durable_route_available',procurement:'durable_contact_available',why:'Use recent registration and construction timing as account-qualification context while keeping raw FCC status codes descriptive and unresolved unless separately decoded from authoritative evidence.',guardrail:'FCC registration and recent-construction records are qualifying signals only. The buyer role is registered owner or operator and must not be narrowed further without separate evidence. Scout is not asserting an inspection need, procurement, access, service radius, ownership boundary, guy-wire footprint, buyer intent, or work availability.',bounds:[-86.8950833333333,37.7318888888889,-85.0863611111111,39.1759166666667],points:[[-86.8950833333333,37.7318888888889],[-85.0863611111111,39.1759166666667]],evidence:3,organization_type:'tower_owner'},
  }[type]
  if(grouped){const [west,south,east,north]=grouped.bounds;return{contract_version:'spine_grouped_portfolio_map_v1',opportunity_type:type,group_kind:grouped.group_kind,source_kind:grouped.source_kind,relationship_label:grouped.relationship,geographic_label:grouped.geo,membership_basis:'resolved_buyer_organization_on_current_spine',dedupe_basis:'operational_target_key',account:{organization_id:'00000000-0000-4000-8000-000000000111',name:grouped.account,organization_type:grouped.organization_type,resolution_status:'organization_resolved',role_code:grouped.role,contact_status:grouped.contact,procurement_status:grouped.procurement},evidence_row_count:grouped.evidence,member_count:grouped.points.length,observed_at:'2026-09-16T12:00:00Z',bounds:{west,south,east,north},members:grouped.points.map(([lon,lat],idx)=>({member_key:`${grouped.source_kind}:target:${idx+1}`,candidate_key:`${grouped.source_kind}:candidate:${idx+1}`,name:`${grouped.account} member ${idx+1}`,point:{lon,lat,geometry_type:'Point',semantics:'source_opportunity_point'},signal_kind:'fixture_signal',signal_strength:idx?'medium':'high',confidence:idx ? .82 : .95,observed_at:'2026-09-16T12:00:00Z',facts:[{label:'Fixture',value:`Member ${idx+1}`}]})),why_investigate:grouped.why,guardrail:grouped.guardrail}}

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
