create or replace function public.scout_get_component_sandbox_grouped_portfolio_v1_internal(p_opportunity_type text)
returns jsonb language sql stable security definer set search_path to 'pg_catalog' as $function$
with cfg as(
 select * from (values
  ('bridge_agency_portfolio','bridge','Louisville Metro Department of Public Works','agency_asset_portfolio','resolved transportation-agency relationship on current bridge evidence','Louisville / Jefferson County, Kentucky','Use the grouped condition and inspection evidence to prioritize account research across the agency bridge set without treating condition records as procurement or work availability.','Bridge condition and inspection evidence supports qualification only. The resolved buyer relationship is recorded as bridge owner or transportation agency and must not be narrowed to legal ownership without separate evidence. Scout is not making a structural-engineering determination or asserting procurement, access, buyer intent, or work availability.'),
  ('railroad_crossing_network','rail_crossing_context','Louisville & Indiana Railroad Company','railroad_crossing_network','resolved railroad relationship on current crossing evidence','Louisville-to-Indianapolis corridor crossing evidence','Use crossing traffic, train-movement, protection, and incident-history context to prioritize account and inspection research across the documented crossing set.','FRA crossing records support account and inspection research only. Point membership does not define railroad property, track topology, right-of-way, safe operating airspace, maintenance need, access permission, procurement, or authorization to work near rail operations.'),
  ('construction_contractor_portfolio','construction_window','Miranda Construction LLC','contractor_project_portfolio','permit-named contractor relationship on current construction evidence','Louisville / Jefferson County construction projects','Use the deduplicated permit-derived project set to research repeat account potential and project timing without converting permit status into field-observed progress or buyer intent.','The relationship is based on contractor naming in permit-derived evidence. It does not prove prime-contract authority, project control, active drone scope, field-observed stage, procurement, site access, buyer intent, or work availability.'),
  ('telecom_registration_portfolio','telecom_change','The Towers, LLC','telecom_registration_portfolio','FCC-record owner/operator relationship on current registration evidence','Kentucky / Indiana FCC ASR registration evidence','Use recent registration and construction timing as account-qualification context while keeping raw FCC status codes descriptive and unresolved unless separately decoded from authoritative evidence.','FCC registration and recent-construction records are qualifying signals only. The buyer role is registered owner or operator and must not be narrowed further without separate evidence. Scout is not asserting an inspection need, procurement, access, service radius, ownership boundary, guy-wire footprint, buyer intent, or work availability.')
 ) as v(opportunity_type,source_kind,account_name,group_kind,relationship_label,geographic_label,why_investigate,guardrail)
 where v.opportunity_type=p_opportunity_type
), raw as(
 select o.*,c.opportunity_type,c.group_kind,c.relationship_label,c.geographic_label,c.why_investigate,c.guardrail
 from scout.opportunity_search_spine o join cfg c on o.source_kind=c.source_kind and o.buyer_name=c.account_name
 where o.buyer_resolution_status='organization_resolved' and o.buyer_organization_id is not null and o.operational_target_key is not null and o.location is not null and extensions.st_geometrytype(o.location::extensions.geometry)='ST_Point'
 and (c.opportunity_type<>'construction_contractor_portfolio' or pg_catalog.lower(o.details->>'contractor_name')=pg_catalog.lower(c.account_name))
 and (c.opportunity_type<>'telecom_registration_portfolio' or pg_catalog.lower(o.details->>'owner_name')=pg_catalog.lower(c.account_name))
), ranked as(
 select raw.*,row_number() over(partition by operational_target_key order by confidence desc nulls last,observed_at desc nulls last,refreshed_at desc nulls last,candidate_key) rn from raw
), selected as(select * from ranked where rn=1), checks as(
 select count(*) member_count,(select count(*) from raw) evidence_row_count,count(distinct buyer_organization_id) buyer_org_count,min(extensions.st_x(location::extensions.geometry)) west,min(extensions.st_y(location::extensions.geometry)) south,max(extensions.st_x(location::extensions.geometry)) east,max(extensions.st_y(location::extensions.geometry)) north,max(observed_at) observed_at from selected
), account as(
 select buyer_organization_id,buyer_name,buyer_organization_type,buyer_role_code,buyer_contact_status,procurement_status from selected order by observed_at desc nulls last,refreshed_at desc nulls last limit 1
), members as(
 select jsonb_agg(jsonb_build_object(
  'member_key',s.operational_target_key,'candidate_key',s.candidate_key,'name',coalesce(s.target_name,s.display_name,s.operational_target_key),
  'point',jsonb_build_object('lon',extensions.st_x(s.location::extensions.geometry),'lat',extensions.st_y(s.location::extensions.geometry),'geometry_type','Point','semantics','source_opportunity_point'),
  'signal_kind',s.signal_kind,'signal_strength',s.signal_strength,'confidence',s.confidence,'observed_at',s.observed_at,
  'facts',case s.opportunity_type
   when 'bridge_agency_portfolio' then jsonb_build_array(jsonb_build_object('label','Structure','value',coalesce(s.details->>'structure_number',s.operational_target_key)),jsonb_build_object('label','Condition','value',coalesce(s.details->>'effective_condition_band',s.signal_strength)),jsonb_build_object('label','Inspection','value',coalesce(s.details->>'inspection_date','Unknown')))
   when 'railroad_crossing_network' then jsonb_build_array(jsonb_build_object('label','Crossing','value',coalesce(s.details->>'crossing_id',s.operational_target_key)),jsonb_build_object('label','Road traffic','value',coalesce(s.details->>'annual_avg_daily_traffic','Unknown')),jsonb_build_object('label','Train movements','value',coalesce(s.details->>'trains_day','Unknown')))
   when 'construction_contractor_portfolio' then jsonb_build_array(jsonb_build_object('label','Address','value',coalesce(s.details->>'address',s.display_name)),jsonb_build_object('label','Project type','value',coalesce(s.details->>'project_type','Unknown')),jsonb_build_object('label','Stage','value',coalesce(s.details->>'current_stage','Permit-derived stage unresolved')),jsonb_build_object('label','Project value','value',coalesce(s.details->>'project_value','Unknown')))
   when 'telecom_registration_portfolio' then jsonb_build_array(jsonb_build_object('label','Registration','value',coalesce(s.details->>'registration_number',s.operational_target_key)),jsonb_build_object('label','Structure type','value',coalesce(s.details->>'structure_type','Unknown')),jsonb_build_object('label','AGL meters','value',coalesce(s.details->>'overall_height_agl_m','Unknown')),jsonb_build_object('label','FCC status code','value',coalesce(s.details->'event_current_state'->>'status_code','Unknown')))
  end
 ) order by s.observed_at desc nulls last,s.operational_target_key) members from selected s
)
select jsonb_build_object(
 'contract_version','spine_grouped_portfolio_map_v1','opportunity_type',c.opportunity_type,'group_kind',c.group_kind,'source_kind',c.source_kind,'relationship_label',c.relationship_label,'geographic_label',c.geographic_label,
 'membership_basis','resolved_buyer_organization_on_current_spine','dedupe_basis','operational_target_key',
 'account',jsonb_build_object('organization_id',a.buyer_organization_id,'name',a.buyer_name,'organization_type',a.buyer_organization_type,'resolution_status','organization_resolved','role_code',a.buyer_role_code,'contact_status',coalesce(a.buyer_contact_status,'unresolved'),'procurement_status',coalesce(a.procurement_status,'unresolved')),
 'evidence_row_count',k.evidence_row_count,'member_count',k.member_count,'observed_at',k.observed_at,
 'bounds',jsonb_build_object('west',k.west,'south',k.south,'east',k.east,'north',k.north),'members',m.members,'why_investigate',c.why_investigate,'guardrail',c.guardrail
) from cfg c cross join checks k cross join account a cross join members m
where k.member_count>=2 and k.evidence_row_count>=k.member_count and k.buyer_org_count=1 and m.members is not null;
$function$;
revoke all on function public.scout_get_component_sandbox_grouped_portfolio_v1_internal(text) from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_grouped_portfolio_v1_internal(text) to service_role;
