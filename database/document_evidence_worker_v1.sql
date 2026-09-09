-- Scout document evidence worker v1
-- Durable queue + provenance/findings for unattended public-document enrichment.
-- Source documents are processed transiently by GitHub runners; Scout retains
-- only derived textual evidence, fingerprints, and provenance.

create table if not exists research.document_evidence_jobs (
  id uuid primary key default gen_random_uuid(),
  rule_pack text not null,
  subject_type text not null,
  subject_id uuid not null,
  subject_key text,
  display_name text not null,
  organization_name text,
  priority integer not null default 100,
  state text not null default 'queued'
    check (state in ('queued','claimed','completed','needs_review','exhausted','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  lease_until timestamptz,
  completed_at timestamptz,
  last_error text,
  search_query text,
  source_roots jsonb not null default '[]'::jsonb,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(rule_pack, subject_type, subject_id),
  check (jsonb_typeof(source_roots) = 'array'),
  check (jsonb_typeof(context) = 'object')
);

create index if not exists document_evidence_jobs_claim_idx
  on research.document_evidence_jobs(state, next_attempt_at, priority, created_at)
  where state in ('queued','failed','claimed');

create table if not exists research.document_evidence_findings (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references research.document_evidence_jobs(id) on delete cascade,
  fingerprint text not null,
  source_url text not null,
  source_authority text,
  source_kind text not null default 'public_document',
  document_title text,
  page_number integer,
  evidence_excerpt text,
  evidence_codes text[] not null default '{}'::text[],
  extracted_values jsonb not null default '{}'::jsonb,
  confidence numeric not null default 0.5 check (confidence between 0 and 1),
  identity_confidence numeric not null default 0.5 check (identity_confidence between 0 and 1),
  decision_state text not null default 'signal_to_investigate'
    check (decision_state in ('documented','corroborated','signal_to_investigate','unknown')),
  auto_applied boolean not null default false,
  source_sha256 text,
  observed_at timestamptz,
  media_retained boolean not null default false,
  media_retention_policy text not null default 'transient_only_no_source_media_retention',
  created_at timestamptz not null default now(),
  unique(job_id, fingerprint)
);

create index if not exists document_evidence_findings_job_idx
  on research.document_evidence_findings(job_id, created_at desc);
create index if not exists document_evidence_findings_codes_gin
  on research.document_evidence_findings using gin(evidence_codes);

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,commercial_use_status,notes,updated_at
) values (
  'public-document-evidence-worker',
  'Scout Public Document Evidence Worker',
  'Varies by retained source provenance',
  'derived_public_document_evidence',
  'Scout operating coverage',
  'ephemeral document download and deterministic text extraction',
  'queue_driven',
  'inherits_source_authority',
  'active',
  'source_specific',
  'Worker source entry. Original public documents/media are not retained; only derived evidence and provenance are stored.',
  now()
)
on conflict(slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  acquisition_method=excluded.acquisition_method,
  status='active',
  notes=excluded.notes,
  updated_at=now();

create or replace function public.internal_seed_document_evidence_jobs()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','research','water','scout','decisioning','intelligence','ingest'
as $function$
declare
  v_water int := 0;
  v_facade int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,display_name,organization_name,
    priority,search_query,source_roots,context,updated_at
  )
  select
    'water_tank_morphology_v1',
    'water_tank',
    q.tank_id,
    q.wris_fid,
    q.tank_name,
    q.system_name,
    case when q.research_priority <= 0 then 0 else 10 end,
    q.suggested_research_query,
    coalesce((
      select jsonb_agg(distinct e.source_url)
      from water.tank_geometry_evidence e
      where e.tank_id=q.tank_id
        and e.active
        and e.source_url is not null
        and e.source_authority is distinct from 'Kentucky WRIS'
        and e.source_url <> 'https://wris.ky.gov/'
    ),'[]'::jsonb),
    jsonb_build_object(
      'tank_name',q.tank_name,
      'system_name',q.system_name,
      'wris_tank_type',q.wris_tank_type,
      'capacity_gallons',q.capacity_gallons,
      'morphology_research_status',q.morphology_research_status,
      'support_geometry',q.support_geometry,
      'cross_bracing_status',q.cross_bracing_status,
      'lat',q.lat,'lon',q.lon,
      'project_numbers',coalesce((
        select jsonb_agg(distinct tp.pnum)
        from water.tank_projects tp
        where tp.matched_tank_id=q.tank_id and tp.pnum is not null
      ),'[]'::jsonb)
    ),
    now()
  from scout.v_water_tank_geometry_research_queue q
  where q.active_opportunity and q.morphology_research_needed
  on conflict(rule_pack,subject_type,subject_id) do update set
    subject_key=excluded.subject_key,
    display_name=excluded.display_name,
    organization_name=excluded.organization_name,
    priority=excluded.priority,
    search_query=excluded.search_query,
    source_roots=excluded.source_roots,
    context=excluded.context,
    updated_at=now();
  get diagnostics v_water = row_count;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,display_name,organization_name,
    priority,search_query,source_roots,context,updated_at
  )
  select
    'facade_material_glazing_v1',
    'building',
    q.building_source_record_id,
    q.candidate_key,
    q.display_name,
    null,
    20,
    concat_ws(' ',quote_literal(q.display_name),q.county_name,q.state_code,'facade glazing curtain wall material specification renovation'),
    coalesce((
      select jsonb_agg(distinct u.url)
      from (
        select q.website_url as url
        union select q.building_lifecycle_source_url
        union
        select hr.source_url
        from decisioning.facade_verification_identity_context fic
        join intelligence.historic_resources hr on hr.id=fic.historic_resource_id
        where fic.building_source_record_id=q.building_source_record_id
          and coalesce(fic.historic_match_confidence,0) >= 0.95
      ) u
      where u.url is not null and u.url ~ '^https?://'
    ),'[]'::jsonb),
    jsonb_build_object(
      'candidate_key',q.candidate_key,
      'state_code',q.state_code,
      'county_name',q.county_name,
      'verification_needs',to_jsonb(q.verification_needs),
      'resolved_facade_material',q.resolved_facade_material,
      'glazing_extent',q.glazing_extent,
      'historic_resource_names',to_jsonb(q.historic_resource_names),
      'historic_reference_number',q.identity_historic_reference_number,
      'historic_address_text',q.identity_historic_address_text,
      'website_url',q.website_url,
      'building_lifecycle_source_url',q.building_lifecycle_source_url
    ),
    now()
  from decisioning.v_facade_visual_verification_queue_v4 q
  where q.effective_verification_priority='high'
    and coalesce(array_length(q.verification_needs,1),0) > 0
    and q.identity_status is distinct from 'hold_identity_review'
  on conflict(rule_pack,subject_type,subject_id) do update set
    subject_key=excluded.subject_key,
    display_name=excluded.display_name,
    priority=excluded.priority,
    search_query=excluded.search_query,
    source_roots=excluded.source_roots,
    context=excluded.context,
    updated_at=now();
  get diagnostics v_facade = row_count;

  return jsonb_build_object(
    'water_rows_upserted',v_water,
    'facade_rows_upserted',v_facade,
    'queued',(
      select count(*) from research.document_evidence_jobs
      where state in ('queued','failed') and attempt_count < max_attempts
    )
  );
end;
$function$;

create or replace function public.internal_claim_document_evidence_jobs(
  p_limit integer default 6,
  p_rule_pack text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','research'
as $function$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception 'p_limit must be between 1 and 50';
  end if;

  update research.document_evidence_jobs
  set state='queued', claimed_at=null, lease_until=null,
      last_error=coalesce(last_error,'') || case when last_error is null then '' else E'\n' end || 'claim lease expired',
      updated_at=now()
  where state='claimed' and lease_until < now();

  update research.document_evidence_jobs
  set state='exhausted', completed_at=coalesce(completed_at,now()), updated_at=now()
  where state in ('queued','failed') and attempt_count >= max_attempts;

  with picked as (
    select id
    from research.document_evidence_jobs
    where state in ('queued','failed')
      and attempt_count < max_attempts
      and next_attempt_at <= now()
      and (p_rule_pack is null or rule_pack=p_rule_pack)
    order by priority asc, next_attempt_at asc, created_at asc
    for update skip locked
    limit p_limit
  ), claimed as (
    update research.document_evidence_jobs j
    set state='claimed',
        attempt_count=j.attempt_count+1,
        claimed_at=now(),
        lease_until=now()+interval '45 minutes',
        last_error=null,
        updated_at=now()
    from picked
    where j.id=picked.id
    returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'rule_pack',c.rule_pack,
    'subject_type',c.subject_type,
    'subject_id',c.subject_id,
    'subject_key',c.subject_key,
    'display_name',c.display_name,
    'organization_name',c.organization_name,
    'priority',c.priority,
    'attempt_count',c.attempt_count,
    'max_attempts',c.max_attempts,
    'search_query',c.search_query,
    'source_roots',c.source_roots,
    'context',c.context
  ) order by c.priority,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c;

  return v_result;
end;
$function$;

create or replace function public.internal_complete_document_evidence_job(
  p_job_id uuid,
  p_outcome text,
  p_findings jsonb default '[]'::jsonb,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','research','water','decisioning','ingest'
as $function$
declare
  v_job research.document_evidence_jobs%rowtype;
  v_item jsonb;
  v_codes jsonb;
  v_auto_count int := 0;
  v_auto_applied boolean := false;
  v_finding_id uuid;
  v_source_id uuid;
  v_obs_id uuid;
  v_geom geometry;
  v_morph text;
  v_support text;
  v_bracing text;
  v_legs int;
  v_conf numeric;
  v_identity_conf numeric;
  v_material text;
  v_raw_material text;
  v_glazing text;
  v_glazing_signal text;
  v_source_native_id text;
  v_next_state text;
  v_next_attempt timestamptz;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_outcome not in ('completed','no_evidence','needs_review','failed') then
    raise exception 'invalid outcome: %',p_outcome;
  end if;
  if jsonb_typeof(coalesce(p_findings,'[]'::jsonb)) <> 'array' then
    raise exception 'p_findings must be a JSON array';
  end if;

  select * into v_job from research.document_evidence_jobs where id=p_job_id for update;
  if not found then raise exception 'document evidence job not found'; end if;
  if v_job.state <> 'claimed' then raise exception 'job is not currently claimed'; end if;

  select count(*) into v_auto_count
  from jsonb_array_elements(coalesce(p_findings,'[]'::jsonb)) x
  where coalesce((x->>'auto_apply')::boolean,false);
  if v_auto_count > 1 then
    raise exception 'at most one finding may be auto_apply';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_findings,'[]'::jsonb))
  loop
    if nullif(v_item->>'fingerprint','') is null or nullif(v_item->>'source_url','') is null then
      raise exception 'finding requires fingerprint and source_url';
    end if;

    insert into research.document_evidence_findings(
      job_id,fingerprint,source_url,source_authority,source_kind,document_title,page_number,
      evidence_excerpt,evidence_codes,extracted_values,confidence,identity_confidence,
      decision_state,source_sha256,observed_at,media_retained,media_retention_policy
    ) values (
      v_job.id,v_item->>'fingerprint',v_item->>'source_url',nullif(v_item->>'source_authority',''),
      coalesce(nullif(v_item->>'source_kind',''),'public_document'),nullif(v_item->>'document_title',''),
      nullif(v_item->>'page_number','')::integer,left(v_item->>'evidence_excerpt',4000),
      coalesce(array(select jsonb_array_elements_text(coalesce(v_item->'evidence_codes','[]'::jsonb))),'{}'::text[]),
      coalesce(v_item->'extracted_values','{}'::jsonb),
      least(1,greatest(0,coalesce(nullif(v_item->>'confidence','')::numeric,0.5))),
      least(1,greatest(0,coalesce(nullif(v_item->>'identity_confidence','')::numeric,0.5))),
      coalesce(nullif(v_item->>'decision_state',''),'signal_to_investigate'),
      nullif(v_item->>'source_sha256',''),nullif(v_item->>'observed_at','')::timestamptz,
      false,'transient_only_no_source_media_retention'
    )
    on conflict(job_id,fingerprint) do update set
      source_url=excluded.source_url,source_authority=excluded.source_authority,
      document_title=excluded.document_title,page_number=excluded.page_number,
      evidence_excerpt=excluded.evidence_excerpt,evidence_codes=excluded.evidence_codes,
      extracted_values=excluded.extracted_values,confidence=excluded.confidence,
      identity_confidence=excluded.identity_confidence,decision_state=excluded.decision_state,
      source_sha256=excluded.source_sha256,observed_at=excluded.observed_at
    returning id into v_finding_id;

    if not coalesce((v_item->>'auto_apply')::boolean,false) then
      continue;
    end if;

    v_codes := coalesce(v_item->'evidence_codes','[]'::jsonb);
    v_identity_conf := coalesce(nullif(v_item->>'identity_confidence','')::numeric,0);
    v_conf := least(0.995,greatest(0.5,coalesce(nullif(v_item->>'confidence','')::numeric,0.5)));
    if v_identity_conf < 0.95 then
      raise exception 'auto_apply requires identity_confidence >= 0.95';
    end if;

    if v_job.rule_pack='water_tank_morphology_v1' and v_job.subject_type='water_tank' then
      v_morph := null; v_support := null; v_bracing := null; v_legs := null;
      if v_codes ? 'tank.explicit_pedesphere' then
        v_morph:='pedesphere'; v_support:='single_pedestal'; v_bracing:='none';
      elsif v_codes ? 'tank.explicit_composite' then
        v_morph:='composite_elevated'; v_support:='single_pedestal'; v_bracing:='none';
      elsif v_codes ? 'tank.explicit_fluted_column' then
        v_morph:='fluted_column'; v_support:='single_pedestal'; v_bracing:='none';
      elsif v_codes ? 'tank.explicit_standpipe' then
        v_morph:='standpipe'; v_support:='ground_supported'; v_bracing:='not_applicable';
      elsif v_codes ? 'tank.explicit_ground_storage' then
        v_morph:='ground_storage'; v_support:='ground_supported'; v_bracing:='not_applicable';
      elsif (v_codes ? 'tank.explicit_multi_column' or v_codes ? 'tank.explicit_multiple_legs')
        and (v_codes ? 'tank.explicit_bracing' or v_codes ? 'tank.explicit_struts' or v_codes ? 'tank.explicit_windage_rods') then
        v_morph:='multi_column_cross_braced'; v_support:='multi_column'; v_bracing:='present';
      elsif (v_codes ? 'tank.explicit_multi_column' or v_codes ? 'tank.explicit_multiple_legs') then
        v_morph:='elevated_unknown'; v_support:='multi_column'; v_bracing:='unknown';
      else
        raise exception 'water auto_apply finding lacks a supported direct morphology code';
      end if;
      v_legs := nullif(v_item#>>'{extracted_values,support_leg_count}','')::integer;

      if exists(
        select 1 from water.tank_geometry_evidence e
        where e.tank_id=v_job.subject_id and e.active
          and e.evidence->>'document_evidence_fingerprint'=v_item->>'fingerprint'
      ) then
        update water.tank_geometry_evidence e set
          morphology_class=v_morph,support_geometry=v_support,cross_bracing_status=v_bracing,
          support_leg_count=v_legs,confidence=v_conf,source_url=v_item->>'source_url',
          source_authority=nullif(v_item->>'source_authority',''),observed_on=current_date,
          evidence=jsonb_build_object(
            'document_evidence_fingerprint',v_item->>'fingerprint',
            'document_title',v_item->>'document_title','page_number',v_item->>'page_number',
            'evidence_excerpt',left(v_item->>'evidence_excerpt',4000),'evidence_codes',v_codes,
            'source_sha256',v_item->>'source_sha256','identity_confidence',v_identity_conf,
            'extraction_method','scout_document_evidence_worker_v1','media_retained',false
          ) || coalesce(v_item->'extracted_values','{}'::jsonb),
          media_retained=false,media_retention_policy='transient_only_no_image_retention',updated_at=now()
        where e.tank_id=v_job.subject_id and e.active
          and e.evidence->>'document_evidence_fingerprint'=v_item->>'fingerprint';
      else
        insert into water.tank_geometry_evidence(
          tank_id,evidence_kind,morphology_class,support_geometry,cross_bracing_status,
          support_leg_count,confidence,source_url,source_authority,observed_on,evidence,
          active,media_retained,media_retention_policy
        ) values (
          v_job.subject_id,'engineering_document',v_morph,v_support,v_bracing,v_legs,v_conf,
          v_item->>'source_url',nullif(v_item->>'source_authority',''),current_date,
          jsonb_build_object(
            'document_evidence_fingerprint',v_item->>'fingerprint',
            'document_title',v_item->>'document_title','page_number',v_item->>'page_number',
            'evidence_excerpt',left(v_item->>'evidence_excerpt',4000),'evidence_codes',v_codes,
            'source_sha256',v_item->>'source_sha256','identity_confidence',v_identity_conf,
            'extraction_method','scout_document_evidence_worker_v1','media_retained',false
          ) || coalesce(v_item->'extracted_values','{}'::jsonb),
          true,false,'transient_only_no_image_retention'
        );
      end if;
      v_auto_applied := true;

    elsif v_job.rule_pack='facade_material_glazing_v1' and v_job.subject_type='building' then
      v_material := null; v_raw_material := null; v_glazing := null; v_glazing_signal := null;
      if v_codes ? 'facade.material.brick' then v_material:='brick'; v_raw_material:='brick';
      elsif v_codes ? 'facade.material.concrete' or v_codes ? 'facade.material.precast_concrete' then v_material:='concrete'; v_raw_material:=coalesce(v_item#>>'{extracted_values,raw_facade_material}','concrete');
      elsif v_codes ? 'facade.material.cmu' then v_material:='cement_block'; v_raw_material:=coalesce(v_item#>>'{extracted_values,raw_facade_material}','CMU');
      elsif v_codes ? 'facade.material.glass' then v_material:='glass'; v_raw_material:='glass';
      elsif v_codes ? 'facade.material.metal_panel' or v_codes ? 'facade.material.metal' then v_material:='metal'; v_raw_material:=coalesce(v_item#>>'{extracted_values,raw_facade_material}','metal');
      elsif v_codes ? 'facade.material.stucco' or v_codes ? 'facade.material.eifs' or v_codes ? 'facade.material.plaster' then v_material:='plaster'; v_raw_material:=coalesce(v_item#>>'{extracted_values,raw_facade_material}','stucco');
      elsif v_codes ? 'facade.material.stone' or v_codes ? 'facade.material.limestone' then v_material:='stone'; v_raw_material:=coalesce(v_item#>>'{extracted_values,raw_facade_material}','stone');
      elsif v_codes ? 'facade.material.wood' then v_material:='wood'; v_raw_material:='wood';
      end if;

      if v_codes ? 'facade.glazing.curtain_wall' or v_codes ? 'facade.glazing.window_wall'
        or v_codes ? 'facade.glazing.unitized' or v_codes ? 'facade.glazing.stick_built' then
        v_glazing:='facade_system'; v_glazing_signal:='glass_facade_present';
      elsif v_codes ? 'facade.glazing.storefront' then
        v_glazing:='localized'; v_glazing_signal:='glass_facade_present';
      end if;
      if v_material is null and v_glazing is null then
        raise exception 'facade auto_apply finding lacks a supported direct material/glazing code';
      end if;

      select id into v_source_id from ingest.sources where slug='public-document-evidence-worker';
      select geometry into v_geom from decisioning.building_candidates where source_record_id=v_job.subject_id;
      if v_source_id is null or v_geom is null then
        raise exception 'facade document evidence source or canonical building geometry unavailable';
      end if;
      v_source_native_id := 'doc:' || left(v_item->>'fingerprint',96);

      insert into decisioning.building_attribute_observations(
        source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
        height_m,height_status,story_count,story_status,facade_material,raw_facade_material,
        facade_material_status,glazing_signal,has_parts,confidence,attributes,updated_at,glazing_extent
      ) values (
        v_source_id,v_source_native_id,'document_evidence',now(),null,v_geom,
        null,'unknown',null,'unknown',v_material,v_raw_material,
        case when v_material is not null then 'documented' else 'unknown' end,
        v_glazing_signal,null,v_conf,
        jsonb_build_object(
          'document_evidence_fingerprint',v_item->>'fingerprint','source_url',v_item->>'source_url',
          'source_authority',v_item->>'source_authority','document_title',v_item->>'document_title',
          'page_number',v_item->>'page_number','evidence_excerpt',left(v_item->>'evidence_excerpt',4000),
          'evidence_codes',v_codes,'source_sha256',v_item->>'source_sha256',
          'identity_confidence',v_identity_conf,'extraction_method','scout_document_evidence_worker_v1',
          'media_retained',false
        ) || coalesce(v_item->'extracted_values','{}'::jsonb),
        now(),v_glazing
      )
      on conflict(source_id,source_native_id,source_feature_kind) do update set
        observed_at=excluded.observed_at,geometry=excluded.geometry,
        facade_material=excluded.facade_material,raw_facade_material=excluded.raw_facade_material,
        facade_material_status=excluded.facade_material_status,glazing_signal=excluded.glazing_signal,
        confidence=excluded.confidence,attributes=excluded.attributes,glazing_extent=excluded.glazing_extent,
        updated_at=now()
      returning id into v_obs_id;

      insert into decisioning.building_attribute_matches(
        building_source_record_id,observation_id,match_basis,overlap_ratio,centroid_distance_m,confidence,matched_at
      ) values (v_job.subject_id,v_obs_id,'document_identity_exact',1,0,v_identity_conf,now())
      on conflict(building_source_record_id,observation_id) do update set
        match_basis='document_identity_exact',overlap_ratio=1,centroid_distance_m=0,
        confidence=excluded.confidence,matched_at=now();
      v_auto_applied := true;
    else
      raise exception 'auto_apply is not supported for rule pack %',v_job.rule_pack;
    end if;

    update research.document_evidence_findings set auto_applied=true where id=v_finding_id;
  end loop;

  if p_outcome='completed' then
    v_next_state:='completed'; v_next_attempt:=v_job.next_attempt_at;
  elsif p_outcome='needs_review' then
    v_next_state:='needs_review'; v_next_attempt:=v_job.next_attempt_at;
  elsif p_outcome='no_evidence' then
    if v_job.attempt_count >= v_job.max_attempts then
      v_next_state:='exhausted'; v_next_attempt:=v_job.next_attempt_at;
    else
      v_next_state:='queued';
      v_next_attempt:=now()+case when v_job.attempt_count=1 then interval '6 hours' else interval '18 hours' end;
    end if;
  else
    if v_job.attempt_count >= v_job.max_attempts then
      v_next_state:='exhausted'; v_next_attempt:=v_job.next_attempt_at;
    else
      v_next_state:='failed'; v_next_attempt:=now()+interval '2 hours';
    end if;
  end if;

  update research.document_evidence_jobs set
    state=v_next_state,
    next_attempt_at=v_next_attempt,
    claimed_at=null,lease_until=null,
    completed_at=case when v_next_state in ('completed','needs_review','exhausted') then now() else null end,
    last_error=case when p_outcome='failed' then left(p_error,4000) else null end,
    updated_at=now()
  where id=v_job.id;

  return jsonb_build_object(
    'job_id',v_job.id,'state',v_next_state,'attempt_count',v_job.attempt_count,
    'auto_applied',v_auto_applied,'finding_count',jsonb_array_length(coalesce(p_findings,'[]'::jsonb))
  );
end;
$function$;

alter table research.document_evidence_jobs enable row level security;
alter table research.document_evidence_findings enable row level security;

revoke all on table research.document_evidence_jobs from public,anon,authenticated;
revoke all on table research.document_evidence_findings from public,anon,authenticated;
revoke all on function public.internal_seed_document_evidence_jobs() from public,anon,authenticated;
revoke all on function public.internal_claim_document_evidence_jobs(integer,text) from public,anon,authenticated;
revoke all on function public.internal_complete_document_evidence_job(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.internal_seed_document_evidence_jobs() to service_role;
grant execute on function public.internal_claim_document_evidence_jobs(integer,text) to service_role;
grant execute on function public.internal_complete_document_evidence_job(uuid,text,jsonb,text) to service_role;
