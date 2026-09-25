begin;

create table if not exists farm_watch.mast_survey_reports_v1 (
  survey_year smallint primary key check (survey_year between 2007 and 2100),
  source_authority text not null,
  report_title text not null,
  report_url text not null,
  index_url text not null,
  publication_date date not null,
  methodology text not null,
  survey_route_count integer check (survey_route_count is null or survey_route_count > 0),
  county_count integer check (county_count is null or county_count > 0),
  tree_count integer check (tree_count is null or tree_count > 0),
  source_scope text not null,
  source_notes jsonb not null default '{}'::jsonb,
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists farm_watch.mast_survey_group_results_v1 (
  survey_year smallint not null references farm_watch.mast_survey_reports_v1(survey_year) on delete cascade,
  survey_scope text not null check (survey_scope in ('statewide','east','west')),
  tree_group text not null check (tree_group in ('white_oak','red_oak','hickory','beech')),
  trees_surveyed integer not null check (trees_surveyed > 0),
  pca_median_pct numeric not null check (pca_median_pct between 0 and 100),
  pca_iqr_low_pct numeric not null check (pca_iqr_low_pct between 0 and 100),
  pca_iqr_high_pct numeric not null check (pca_iqr_high_pct between 0 and 100),
  pba_pct numeric not null check (pba_pct between 0 and 100),
  rating text not null check (rating in ('failure','poor','average','good','bumper')),
  source_table text not null default 'Table 1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (survey_year,survey_scope,tree_group),
  check (pca_iqr_low_pct <= pca_median_pct and pca_median_pct <= pca_iqr_high_pct)
);

create table if not exists farm_watch.property_mast_survey_region_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  survey_region text not null check (survey_region in ('east','west')),
  evidence_class text not null check (evidence_class in ('derived_from_authoritative_map')),
  source_report_year smallint not null references farm_watch.mast_survey_reports_v1(survey_year),
  source_url text not null,
  source_figure text not null,
  basis text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists farm_watch.property_mast_resource_context_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  survey_year smallint not null check (survey_year between 2007 and 2100),
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature text not null,
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id,survey_year)
);

create index if not exists mast_survey_group_results_year_idx
  on farm_watch.mast_survey_group_results_v1(survey_year desc,survey_scope,tree_group);

create index if not exists property_mast_resource_context_year_idx
  on farm_watch.property_mast_resource_context_v1(survey_year desc,retrieved_at desc);

alter table farm_watch.mast_survey_reports_v1 enable row level security;
alter table farm_watch.mast_survey_group_results_v1 enable row level security;
alter table farm_watch.property_mast_survey_region_v1 enable row level security;
alter table farm_watch.property_mast_resource_context_v1 enable row level security;

revoke all on farm_watch.mast_survey_reports_v1 from public,anon,authenticated;
revoke all on farm_watch.mast_survey_group_results_v1 from public,anon,authenticated;
revoke all on farm_watch.property_mast_survey_region_v1 from public,anon,authenticated;
revoke all on farm_watch.property_mast_resource_context_v1 from public,anon,authenticated;

grant select,insert,update,delete on farm_watch.mast_survey_reports_v1 to service_role;
grant select,insert,update,delete on farm_watch.mast_survey_group_results_v1 to service_role;
grant select,insert,update,delete on farm_watch.property_mast_survey_region_v1 to service_role;
grant select,insert,update,delete on farm_watch.property_mast_resource_context_v1 to service_role;

insert into farm_watch.mast_survey_reports_v1(
  survey_year,source_authority,report_title,report_url,index_url,publication_date,
  methodology,survey_route_count,county_count,tree_count,source_scope,source_notes
) values
(
  2024,
  'Kentucky Department of Fish and Wildlife Resources (KDFWR)',
  '2024 Mast Survey Report',
  'https://fw.ky.gov/Hunt/Documents/mast_report_2024.pdf',
  'https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx',
  date '2024-10-04',
  'KDFWR current mast survey method (post-2007): 30-second crown scan, PCA estimate, PBA presence/absence summary, published categorical rating',
  35,33,2853,
  'Kentucky statewide plus East/West mast-survey regions',
  jsonb_build_object(
    'beech_viability_caution',true,
    'pba_is_presence_not_abundance',true,
    'site_variability_material',true
  )
),
(
  2025,
  'Kentucky Department of Fish and Wildlife Resources (KDFWR)',
  '2025 Mast Survey Report',
  'https://fw.ky.gov/Hunt/Documents/2025-mast-report.pdf',
  'https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx',
  date '2025-09-29',
  'KDFWR current mast survey method (post-2007): 30-second crown scan, PCA estimate, PBA presence/absence summary, published categorical rating',
  35,32,2766,
  'Kentucky statewide plus East/West mast-survey regions',
  jsonb_build_object(
    'beech_viability_caution',true,
    'pba_is_presence_not_abundance',true,
    'site_variability_material',true
  )
)
on conflict(survey_year) do update set
  source_authority=excluded.source_authority,
  report_title=excluded.report_title,
  report_url=excluded.report_url,
  index_url=excluded.index_url,
  publication_date=excluded.publication_date,
  methodology=excluded.methodology,
  survey_route_count=excluded.survey_route_count,
  county_count=excluded.county_count,
  tree_count=excluded.tree_count,
  source_scope=excluded.source_scope,
  source_notes=excluded.source_notes,
  retrieved_at=now(),
  updated_at=now();

insert into farm_watch.mast_survey_group_results_v1(
  survey_year,survey_scope,tree_group,trees_surveyed,
  pca_median_pct,pca_iqr_low_pct,pca_iqr_high_pct,pba_pct,rating
) values
  (2024,'statewide','white_oak',822,0,0,10,42,'average'),
  (2024,'statewide','red_oak',838,30,5,70,79,'good'),
  (2024,'statewide','hickory',842,0,0,10,44,'average'),
  (2024,'statewide','beech',351,0,0,5,29,'poor'),
  (2024,'east','white_oak',314,0,0,5,33,'poor'),
  (2024,'east','red_oak',305,35,0,70,74,'good'),
  (2024,'east','hickory',311,0,0,5,32,'poor'),
  (2024,'east','beech',229,0,0,5,30,'poor'),
  (2024,'west','white_oak',508,0,0,10,47,'average'),
  (2024,'west','red_oak',533,30,5,70,82,'bumper'),
  (2024,'west','hickory',531,5,0,10,51,'average'),
  (2024,'west','beech',122,0,0,5,26,'poor'),
  (2025,'statewide','white_oak',797,10,0,30,62,'good'),
  (2025,'statewide','red_oak',809,10,0,30,66,'good'),
  (2025,'statewide','hickory',799,0,0,15,42,'average'),
  (2025,'statewide','beech',361,20,0,60,68,'good'),
  (2025,'east','white_oak',279,10,0,25,65,'good'),
  (2025,'east','red_oak',266,10,0,20,62,'good'),
  (2025,'east','hickory',277,0,0,10,40,'poor'),
  (2025,'east','beech',191,30,10,60,81,'bumper'),
  (2025,'west','white_oak',518,5,0,30,61,'good'),
  (2025,'west','red_oak',543,10,0,40,69,'good'),
  (2025,'west','hickory',522,0,0,20,43,'average'),
  (2025,'west','beech',170,5,0,47.5,54,'average')
on conflict(survey_year,survey_scope,tree_group) do update set
  trees_surveyed=excluded.trees_surveyed,
  pca_median_pct=excluded.pca_median_pct,
  pca_iqr_low_pct=excluded.pca_iqr_low_pct,
  pca_iqr_high_pct=excluded.pca_iqr_high_pct,
  pba_pct=excluded.pba_pct,
  rating=excluded.rating,
  source_table=excluded.source_table,
  updated_at=now();

insert into farm_watch.property_mast_survey_region_v1(
  property_id,survey_region,evidence_class,source_report_year,source_url,source_figure,basis
)
select
  p.id,
  'west',
  'derived_from_authoritative_map',
  2025,
  'https://fw.ky.gov/Hunt/Documents/2025-mast-report.pdf',
  'Figure 4',
  'Validation-property center near Frankfort is west of the East/West boundary shown in KDFWR Figure 4. This is a derived regional classification, not a KDFWR property-level survey observation.'
from farm_watch.properties p
where p.slug='validation-property-01'
on conflict(property_id) do update set
  survey_region=excluded.survey_region,
  evidence_class=excluded.evidence_class,
  source_report_year=excluded.source_report_year,
  source_url=excluded.source_url,
  source_figure=excluded.source_figure,
  basis=excluded.basis,
  active=true,
  updated_at=now();

create or replace function farm_watch.farm_watch_mast_resource_context_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','kdfwr-mast-survey-context-v1',
    'output_schema_version','mast-resource-context-v1',
    'evidence_class','deterministic_derived',
    'annual_proxy_evidence_class','authoritative_regional_proxy',
    'operator_observation_kind','mast_resource',
    'survey_authority','Kentucky Department of Fish and Wildlife Resources (KDFWR)',
    'survey_index_url','https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx',
    'group_order',jsonb_build_array('white_oak','red_oak','hickory','beech'),
    'interpretation_rules',jsonb_build_array(
      'preserve modeled mast capacity separately from annual survey state',
      'preserve statewide/regional survey evidence as proxy for unsurveyed property',
      'do not carry prior-year survey ratings into a missing current survey year',
      'preserve property field observations separately',
      'do not calculate a composite food or deer score'
    )
  );
$$;

create or replace function farm_watch.farm_watch_resolve_mast_resource_context_v1_internal(
  p_slug text,
  p_survey_year integer default extract(year from current_date)::integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_algorithm text;
  v_schema text;

  v_capacity record;
  v_capacity_status text;
  v_capacity jsonb;

  v_report farm_watch.mast_survey_reports_v1%rowtype;
  v_latest_report_year integer;
  v_statewide jsonb;
  v_region text;
  v_region_relation farm_watch.property_mast_survey_region_v1%rowtype;
  v_regional jsonb;
  v_annual_status text;
  v_annual jsonb;

  v_observations jsonb;
  v_status text;
  v_source_fingerprint jsonb;
  v_source_fingerprint_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_survey_year is null or p_survey_year < 2007 or p_survey_year > 2100 then
    raise exception 'invalid mast survey year';
  end if;

  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'survey_year',p_survey_year,
      'context',null
    );
  end if;

  v_contract := farm_watch.farm_watch_mast_resource_context_contract_v1();
  v_algorithm := v_contract->>'algorithm_version';
  v_schema := v_contract->>'output_schema_version';
  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );

  select
    m.product_kind,
    m.identity_sha256,
    m.artifact_sha256,
    m.summary,
    m.source_provenance,
    m.completed_at,
    m.expires_at
  into v_capacity
  from farm_watch.property_materializations_v1 m
  where m.property_id=v_property_id
    and m.product_kind='mast-capacity'
    and m.completed_at is not null
  order by m.completed_at desc,m.created_at desc
  limit 1;

  v_capacity_status := case
    when v_capacity.product_kind is null then 'unavailable'
    when v_capacity.expires_at is not null and v_capacity.expires_at <= now() then 'stale'
    else 'available'
  end;

  v_capacity := case
    when v_capacity_status='unavailable' then
      jsonb_build_object(
        'status','unavailable',
        'product_kind','mast-capacity',
        'reason','no mast-capacity materialization is available for this property'
      )
    else
      jsonb_build_object(
        'status',v_capacity_status,
        'product_kind','mast-capacity',
        'identity_sha256',v_capacity.identity_sha256,
        'artifact_sha256',v_capacity.artifact_sha256,
        'completed_at',v_capacity.completed_at,
        'expires_at',v_capacity.expires_at,
        'summary',v_capacity.summary,
        'interpretation_boundary',
          'Mast Capacity v1 is modeled/imputed species biomass capacity at 30 m. It is not annual mast production or a property tree inventory.'
      )
  end;

  select max(r.survey_year)::integer
  into v_latest_report_year
  from farm_watch.mast_survey_reports_v1 r
  where r.survey_year <= p_survey_year;

  select *
  into v_report
  from farm_watch.mast_survey_reports_v1 r
  where r.survey_year=p_survey_year
  limit 1;

  select *
  into v_region_relation
  from farm_watch.property_mast_survey_region_v1 r
  where r.property_id=v_property_id and r.active
  limit 1;
  v_region := v_region_relation.survey_region;

  if v_report.survey_year is not null then
    select jsonb_object_agg(
      g.tree_group,
      jsonb_build_object(
        'trees_surveyed',g.trees_surveyed,
        'pca_median_pct',g.pca_median_pct,
        'pca_iqr_low_pct',g.pca_iqr_low_pct,
        'pca_iqr_high_pct',g.pca_iqr_high_pct,
        'pba_pct',g.pba_pct,
        'rating',g.rating
      )
      order by case g.tree_group
        when 'white_oak' then 1
        when 'red_oak' then 2
        when 'hickory' then 3
        when 'beech' then 4
        else 99 end
    )
    into v_statewide
    from farm_watch.mast_survey_group_results_v1 g
    where g.survey_year=p_survey_year and g.survey_scope='statewide';

    if v_region is not null then
      select jsonb_object_agg(
        g.tree_group,
        jsonb_build_object(
          'trees_surveyed',g.trees_surveyed,
          'pca_median_pct',g.pca_median_pct,
          'pca_iqr_low_pct',g.pca_iqr_low_pct,
          'pca_iqr_high_pct',g.pca_iqr_high_pct,
          'pba_pct',g.pba_pct,
          'rating',g.rating
        )
        order by case g.tree_group
          when 'white_oak' then 1
          when 'red_oak' then 2
          when 'hickory' then 3
          when 'beech' then 4
          else 99 end
      )
      into v_regional
      from farm_watch.mast_survey_group_results_v1 g
      where g.survey_year=p_survey_year and g.survey_scope=v_region;
    end if;

    v_annual_status := 'available';
    v_annual := jsonb_strip_nulls(jsonb_build_object(
      'status','available',
      'evidence_class','authoritative_regional_proxy',
      'survey_year',v_report.survey_year,
      'source_authority',v_report.source_authority,
      'report_title',v_report.report_title,
      'report_url',v_report.report_url,
      'index_url',v_report.index_url,
      'publication_date',v_report.publication_date,
      'methodology',v_report.methodology,
      'survey_route_count',v_report.survey_route_count,
      'county_count',v_report.county_count,
      'tree_count',v_report.tree_count,
      'statewide',jsonb_build_object(
        'scope','statewide',
        'groups',coalesce(v_statewide,'{}'::jsonb)
      ),
      'property_region_relation',case
        when v_region is null then null
        else jsonb_build_object(
          'region',v_region,
          'evidence_class',v_region_relation.evidence_class,
          'source_report_year',v_region_relation.source_report_year,
          'source_url',v_region_relation.source_url,
          'source_figure',v_region_relation.source_figure,
          'basis',v_region_relation.basis
        ) end,
      'regional',case
        when v_region is null or v_regional is null then null
        else jsonb_build_object(
          'region',v_region,
          'scope','kdfwr_'||v_region||'_mast_survey_region',
          'groups',v_regional
        ) end,
      'applied_prior_year',false,
      'interpretation_boundary',
        'KDFWR annual mast results are authoritative at the reported statewide/regional survey scope. For an unsurveyed property they remain a regional proxy; PBA is presence of any mast on surveyed trees, not mast abundance at the property.'
    ));
  else
    v_annual_status := 'unavailable';
    v_annual := jsonb_build_object(
      'status','unavailable',
      'requested_survey_year',p_survey_year,
      'latest_available_survey_year',v_latest_report_year,
      'applied_prior_year',false,
      'reason','no canonical KDFWR mast survey report is stored for the requested survey year; prior-year ratings are not carried forward',
      'survey_index_url',v_contract->>'survey_index_url'
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'observation_key',o.observation_key,
      'observation_state',o.observation_state,
      'timing_status',o.timing_status,
      'observed_at',o.observed_at,
      'observed_date_start',o.observed_date_start,
      'observed_date_end',o.observed_date_end,
      'geometry_basis',o.geometry_basis,
      'geometry_precision_m',o.geometry_precision_m,
      'source_context',o.source_context,
      'notes',o.notes,
      'evidence_class','operator_field_observation',
      'updated_at',o.updated_at
    ))
    order by o.observation_key
  ),'[]'::jsonb)
  into v_observations
  from farm_watch.property_operator_observations_v1 o
  where o.property_id=v_property_id
    and o.active
    and o.observation_kind='mast_resource'
    and (
      (o.observed_at is not null and extract(year from o.observed_at)::integer=p_survey_year)
      or
      (
        o.observed_date_start is not null
        and o.observed_date_start <= make_date(p_survey_year,12,31)
        and coalesce(o.observed_date_end,o.observed_date_start) >= make_date(p_survey_year,1,1)
      )
    );

  v_status := case
    when v_capacity_status='available' and v_annual_status='available' then 'available'
    when v_capacity_status in ('available','stale') or v_annual_status='available' then 'partial'
    else 'unavailable'
  end;

  v_source_fingerprint := jsonb_build_object(
    'survey_year',p_survey_year,
    'mast_capacity',jsonb_build_object(
      'status',v_capacity_status,
      'identity_sha256',v_capacity.identity_sha256,
      'artifact_sha256',v_capacity.artifact_sha256
    ),
    'annual_mast_proxy',case
      when v_report.survey_year is null then jsonb_build_object(
        'status','unavailable',
        'latest_available_survey_year',v_latest_report_year
      )
      else jsonb_build_object(
        'status','available',
        'survey_year',v_report.survey_year,
        'report_url',v_report.report_url,
        'publication_date',v_report.publication_date,
        'property_region',v_region
      )
    end,
    'property_observation_keys',coalesce((
      select jsonb_agg(x->>'observation_key' order by x->>'observation_key')
      from jsonb_array_elements(v_observations) x
    ),'[]'::jsonb)
  );
  v_source_fingerprint_sha256 := encode(
    extensions.digest(convert_to(v_source_fingerprint::text,'UTF8'),'sha256'),'hex'
  );

  v_source_signature := concat_ws(
    '|',
    'product=mast-resource-context',
    'survey_year='||p_survey_year::text,
    'mast_capacity_identity='||coalesce(v_capacity.identity_sha256,'unavailable'),
    'annual_report='||coalesce(v_report.report_url,'unavailable'),
    'property_region='||coalesce(v_region,'unresolved'),
    'source_fingerprint_sha256='||v_source_fingerprint_sha256
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(concat_ws(
        '|',v_property_id::text,p_survey_year::text,v_algorithm,v_schema,
        v_boundary_sha256,v_source_signature_sha256
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_context := jsonb_build_object(
    'schema',v_schema,
    'method',v_algorithm,
    'evidence_class','deterministic_derived',
    'survey_year',p_survey_year,
    'mast_capacity',v_capacity,
    'annual_mast_proxy',v_annual,
    'property_observations',v_observations,
    'source_fingerprint',v_source_fingerprint,
    'source_fingerprint_sha256',v_source_fingerprint_sha256,
    'scoring_performed',false,
    'behavioral_inference_performed',false,
    'deer_mast_response_inferred',false,
    'interpretation_boundary',
      'Mast Resource Context v1 keeps modeled mast-species capacity, KDFWR annual survey proxy, and property field observations as separate evidence streams. It does not create a food score or infer deer use.'
  );

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'survey_year',p_survey_year,
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version',v_algorithm,
      'output_schema_version',v_schema,
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
  p_slug text,
  p_survey_year integer default extract(year from current_date)::integer
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_resolved jsonb;
  v_property_id uuid;
begin
  v_resolved := farm_watch.farm_watch_resolve_mast_resource_context_v1_internal(
    p_slug,p_survey_year
  );
  if v_resolved->>'status'='missing' then return v_resolved; end if;

  v_property_id := nullif(v_resolved->'property'->>'id','')::uuid;
  if v_property_id is null then
    raise exception 'resolved mast-resource property identity is unavailable';
  end if;

  insert into farm_watch.property_mast_resource_context_v1(
    property_id,survey_year,status,context,boundary_sha256,source_signature,
    source_signature_sha256,algorithm_version,output_schema_version,identity_sha256,
    retrieved_at,updated_at
  ) values (
    v_property_id,p_survey_year,v_resolved->>'status',v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),now()
  )
  on conflict(property_id,survey_year) do update set
    status=excluded.status,
    context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    updated_at=now();

  return farm_watch.farm_watch_get_mast_resource_context_v1_internal(p_slug,p_survey_year);
end;
$$;

create or replace function farm_watch.farm_watch_get_mast_resource_context_v1_internal(
  p_slug text,
  p_survey_year integer default extract(year from current_date)::integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_row farm_watch.property_mast_resource_context_v1%rowtype;
begin
  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'survey_year',p_survey_year,
      'context',null
    );
  end if;

  select *
  into v_row
  from farm_watch.property_mast_resource_context_v1 c
  where c.property_id=v_property_id and c.survey_year=p_survey_year
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'survey_year',p_survey_year,
      'context',null
    );
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );
  v_contract := farm_watch.farm_watch_mast_resource_context_contract_v1();

  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object(
      'status','stale',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'survey_year',p_survey_year,
      'context',null,
      'invalidation_reason','property_boundary_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  if v_row.algorithm_version is distinct from (v_contract->>'algorithm_version')
     or v_row.output_schema_version is distinct from (v_contract->>'output_schema_version') then
    return jsonb_build_object(
      'status','stale',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'survey_year',p_survey_year,
      'context',null,
      'invalidation_reason','mast_resource_context_contract_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  return jsonb_build_object(
    'status',v_row.status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'survey_year',v_row.survey_year,
    'context',v_row.context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_row.boundary_sha256,
      'source_signature_sha256',v_row.source_signature_sha256,
      'algorithm_version',v_row.algorithm_version,
      'output_schema_version',v_row.output_schema_version,
      'identity_sha256',v_row.identity_sha256
    ),
    'retrieved_at',v_row.retrieved_at
  );
end;
$$;

revoke all on function farm_watch.farm_watch_mast_resource_context_contract_v1()
  from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_mast_resource_context_v1_internal(text,integer)
  from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(text,integer)
  from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_mast_resource_context_v1_internal(text,integer)
  from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_mast_resource_context_contract_v1()
  to postgres,service_role;
grant execute on function farm_watch.farm_watch_resolve_mast_resource_context_v1_internal(text,integer)
  to service_role;
grant execute on function farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(text,integer)
  to service_role;
grant execute on function farm_watch.farm_watch_get_mast_resource_context_v1_internal(text,integer)
  to service_role;

create or replace function public.farm_watch_refresh_mast_resource_context_v1_internal(
  p_slug text,
  p_survey_year integer default extract(year from current_date)::integer
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(p_slug,p_survey_year);
$$;

create or replace function public.farm_watch_get_mast_resource_context_v1_internal(
  p_slug text,
  p_survey_year integer default extract(year from current_date)::integer
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_mast_resource_context_v1_internal(p_slug,p_survey_year);
$$;

revoke all on function public.farm_watch_refresh_mast_resource_context_v1_internal(text,integer)
  from public,anon,authenticated;
revoke all on function public.farm_watch_get_mast_resource_context_v1_internal(text,integer)
  from public,anon,authenticated;
grant execute on function public.farm_watch_refresh_mast_resource_context_v1_internal(text,integer)
  to service_role;
grant execute on function public.farm_watch_get_mast_resource_context_v1_internal(text,integer)
  to service_role;

create or replace function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_products jsonb;
  v_surface_water jsonb;
  v_mast_resource jsonb;
  v_available_count integer := 0;
  v_stale_count integer := 0;
  v_unavailable_count integer := 0;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then
    raise exception 'evidence-stack as-of date is required';
  end if;

  select p.id
  into v_property_id
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'schema','deer-evidence-stack-v1',
      'as_of_date',p_as_of_date,
      'property',jsonb_build_object('slug',p_slug),
      'products','{}'::jsonb,
      'surface_water_state',jsonb_build_object('status','missing'),
      'mast_resource_context',jsonb_build_object('status','missing')
    );
  end if;

  with wanted(product_kind,display_name,category,sort_order) as (
    values
      ('lidar-physical-structure','LiDAR physical vertical structure','physical_structure',10),
      ('landscape-structure-context','Landscape physical structure','physical_structure',20),
      ('terrain-form-permeability','Terrain form / permeability','terrain',30),
      ('spatial-edge-patch-context','Spatial edge / patch context','terrain',40),
      ('solar-exposure-context','Potential solar exposure','thermal_light',50),
      ('thermal-exposure-context','Thermal exposure context','thermal_light',60),
      ('horizontal-visibility-context','Horizontal visibility / obstruction','visibility',70),
      ('mast-capacity','Mast-producing species capacity','resources',80)
  ),
  latest as (
    select distinct on (m.product_kind)
      m.product_kind,
      m.algorithm_version,
      m.output_schema_version,
      m.identity_sha256,
      m.evidence_class,
      m.summary,
      m.source_provenance,
      m.limitations,
      m.artifact_sha256,
      m.completed_at,
      m.expires_at
    from farm_watch.property_materializations_v1 m
    where m.property_id=v_property_id
      and m.product_kind in (select product_kind from wanted)
      and m.completed_at is not null
    order by m.product_kind,m.completed_at desc,m.created_at desc
  ),
  rows as (
    select
      w.product_kind,
      w.display_name,
      w.category,
      w.sort_order,
      case
        when l.product_kind is null then 'unavailable'
        when l.expires_at is not null and l.expires_at <= now() then 'stale'
        else 'available'
      end as state,
      l.algorithm_version,
      l.output_schema_version,
      l.identity_sha256,
      l.evidence_class,
      l.summary,
      l.source_provenance,
      l.limitations,
      l.artifact_sha256,
      l.completed_at,
      l.expires_at
    from wanted w
    left join latest l using(product_kind)
  )
  select
    coalesce(
      jsonb_object_agg(
        r.product_kind,
        jsonb_strip_nulls(jsonb_build_object(
          'product_kind',r.product_kind,
          'display_name',r.display_name,
          'category',r.category,
          'sort_order',r.sort_order,
          'status',r.state,
          'algorithm_version',r.algorithm_version,
          'output_schema_version',r.output_schema_version,
          'identity_sha256',r.identity_sha256,
          'evidence_class',r.evidence_class,
          'summary',r.summary,
          'source_provenance',r.source_provenance,
          'limitations',r.limitations,
          'artifact_sha256',r.artifact_sha256,
          'completed_at',r.completed_at,
          'expires_at',r.expires_at
        ))
        order by r.sort_order
      ),
      '{}'::jsonb
    ),
    count(*) filter (where r.state='available'),
    count(*) filter (where r.state='stale'),
    count(*) filter (where r.state='unavailable')
  into v_products,v_available_count,v_stale_count,v_unavailable_count
  from rows r;

  if to_regclass('farm_watch.property_surface_water_state_v1') is not null then
    execute $sql$
      select jsonb_strip_nulls(jsonb_build_object(
        'status',s.status,
        'as_of_date',s.as_of_date,
        'identity_sha256',s.identity_sha256,
        'algorithm_version',s.algorithm_version,
        'output_schema_version',s.output_schema_version,
        'retrieved_at',s.retrieved_at,
        'context',s.context
      ))
      from farm_watch.property_surface_water_state_v1 s
      where s.property_id=$1
        and s.as_of_date=$2
      limit 1
    $sql$
    into v_surface_water
    using v_property_id,p_as_of_date;
  end if;

  if v_surface_water is null then
    v_surface_water := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_surface_water_state_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'as_of_date',p_as_of_date,
      'interpretation_boundary',
        'Surface Water State v1 is not available for this date. Existing mapped hydrography and Seasonal State evidence remain separate inputs.'
    );
  end if;

  if to_regclass('farm_watch.property_mast_resource_context_v1') is not null then
    execute $sql$
      select jsonb_strip_nulls(jsonb_build_object(
        'status',m.status,
        'survey_year',m.survey_year,
        'identity_sha256',m.identity_sha256,
        'algorithm_version',m.algorithm_version,
        'output_schema_version',m.output_schema_version,
        'retrieved_at',m.retrieved_at,
        'context',m.context
      ))
      from farm_watch.property_mast_resource_context_v1 m
      where m.property_id=$1
        and m.survey_year=$2
      limit 1
    $sql$
    into v_mast_resource
    using v_property_id,extract(year from p_as_of_date)::integer;
  end if;

  if v_mast_resource is null then
    v_mast_resource := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_mast_resource_context_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'survey_year',extract(year from p_as_of_date)::integer,
      'interpretation_boundary',
        'Mast Resource Context v1 is not materialized for this survey year. Mast Capacity remains a separate neutral product and no annual mast state is inferred.'
    );
  end if;

  return jsonb_build_object(
    'status',case
      when v_available_count > 0 then 'available'
      when v_stale_count > 0 then 'stale'
      else 'unavailable'
    end,
    'schema','deer-evidence-stack-v1',
    'as_of_date',p_as_of_date,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'counts',jsonb_build_object(
      'available',v_available_count,
      'stale',v_stale_count,
      'unavailable',v_unavailable_count
    ),
    'products',v_products,
    'surface_water_state',v_surface_water,
    'mast_resource_context',v_mast_resource,
    'interpretation_boundary',
      'Neutral Farm Watch evidence inventory for UI review. Availability here does not mean a deer relationship is applicable, a coefficient is transferable, or a deer-use prediction has been made.'
  );
end;
$$;

revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  to service_role;

comment on table farm_watch.mast_survey_reports_v1 is
'Canonical KDFWR annual mast-survey report metadata. Stores normalized authoritative report facts, not the source PDF.';
comment on table farm_watch.mast_survey_group_results_v1 is
'Published KDFWR annual mast survey Table 1 values by statewide/East/West scope and mast-producing tree group.';
comment on table farm_watch.property_mast_survey_region_v1 is
'Private property-to-KDFWR mast-survey-region relation with explicit derivation basis. This is not a property mast observation.';
comment on table farm_watch.property_mast_resource_context_v1 is
'Annual neutral mast resource context. Keeps modeled species capacity, KDFWR annual survey proxy, and property mast observations separate; no wildlife-use inference.';

select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
  'validation-property-01',2024
);
select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
  'validation-property-01',2025
);
select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
  'validation-property-01',2026
);

do $$
begin
  if exists(select 1 from cron.job where jobname='farm-watch-mast-resource-context-pilot-v1') then
    perform cron.unschedule('farm-watch-mast-resource-context-pilot-v1');
  end if;
  perform cron.schedule(
    'farm-watch-mast-resource-context-pilot-v1',
    '35 14 * * *',
    $cron$
      select farm_watch.farm_watch_refresh_mast_resource_context_v1_internal(
        'validation-property-01',
        extract(year from current_date)::integer
      );
    $cron$
  );
end;
$$;

commit;
