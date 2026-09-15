-- Persist a verified first-party web root after the buyer evidence worker has
-- already established a durable organization identity. This makes subsequent
-- research deterministic and avoids repeated provider discovery.

create or replace function public.internal_attach_buyer_research_website_v1(
  p_job_id uuid,
  p_organization_id uuid,
  p_website_url text,
  p_source_url text,
  p_source_authority text,
  p_identity_confidence numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job research.document_evidence_jobs%rowtype;
  v_host text;
  v_source_host text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_identity_confidence,0) < .95 then raise exception 'identity confidence below website attachment threshold'; end if;
  if p_website_url !~ '^https?://' or p_source_url !~ '^https?://' then raise exception 'public website and source URLs required'; end if;

  select * into v_job from research.document_evidence_jobs where id=p_job_id for update;
  if not found
     or v_job.rule_pack <> 'buyer_organization_contact_v1'
     or v_job.state <> 'claimed'
     or nullif(v_job.context->>'organization_id','')::uuid is distinct from p_organization_id then
    raise exception 'claimed buyer evidence job must already resolve to organization';
  end if;

  v_host:=regexp_replace(split_part(regexp_replace(lower(p_website_url),'^https?://','','i'),'/',1),'^www\.','','i');
  v_source_host:=regexp_replace(split_part(regexp_replace(lower(p_source_url),'^https?://','','i'),'/',1),'^www\.','','i');
  if nullif(v_host,'') is null or v_host<>v_source_host then raise exception 'website root must match evidence source host'; end if;
  if v_host = any(array[
    'facebook.com','linkedin.com','instagram.com','x.com','twitter.com','yelp.com','bbb.org',
    'mapquest.com','buildzoom.com','manta.com','chamberofcommerce.com','yellowpages.com',
    'wikipedia.org','crunchbase.com','bloomberg.com','dnb.com','zoominfo.com','opencorporates.com','bizapedia.com'
  ]) then raise exception 'directory/social source cannot become organization website'; end if;

  update core.organizations
  set website_url=coalesce(website_url,p_website_url),
      attributes=attributes||jsonb_strip_nulls(jsonb_build_object(
        'website_evidence_source_url',p_source_url,
        'website_evidence_authority',p_source_authority,
        'website_identity_confidence',least(1,greatest(.95,p_identity_confidence)),
        'website_document_evidence_job_id',p_job_id
      )),updated_at=now()
  where id=p_organization_id and status='active';
  if not found then raise exception 'active organization not found'; end if;

  update research.document_evidence_jobs
  set source_roots=(
        select coalesce(jsonb_agg(x order by x),'[]'::jsonb)
        from (
          select distinct value as x
          from jsonb_array_elements_text(coalesce(source_roots,'[]'::jsonb)||jsonb_build_array(p_website_url))
        ) q
      ),updated_at=now()
  where id=p_job_id;

  return jsonb_build_object('organization_id',p_organization_id,'website_url',p_website_url,'attached',true);
end
$$;
revoke all on function public.internal_attach_buyer_research_website_v1(uuid,uuid,text,text,text,numeric) from public, anon, authenticated;
grant execute on function public.internal_attach_buyer_research_website_v1(uuid,uuid,text,text,text,numeric) to service_role;

-- Completion-time persistence uses only an already-completed documented finding.
-- It fails closed: mismatched hosts, weak identity evidence, or directory/social
-- roots are ignored rather than promoted.
create or replace function research.persist_completed_buyer_research_website_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_source_url text;
  v_website_url text;
  v_authority text;
  v_confidence numeric;
  v_host text;
  v_source_host text;
begin
  if new.rule_pack <> 'buyer_organization_contact_v1' or new.state <> 'completed' then return new; end if;
  v_org_id:=nullif(new.outcome_metadata->>'organization_id','')::uuid;
  if v_org_id is null then return new; end if;

  select f.source_url,
         nullif(f.extracted_values->>'website_url',''),
         f.source_authority,
         f.identity_confidence
  into v_source_url,v_website_url,v_authority,v_confidence
  from research.document_evidence_findings f
  where f.job_id=new.id
    and f.decision_state='documented'
    and f.identity_confidence>=.95
    and nullif(f.extracted_values->>'website_url','') is not null
  order by f.observed_at desc
  limit 1;

  if v_source_url is null or v_website_url is null or v_source_url !~ '^https?://' or v_website_url !~ '^https?://' then return new; end if;
  v_host:=regexp_replace(split_part(regexp_replace(lower(v_website_url),'^https?://','','i'),'/',1),'^www\.','','i');
  v_source_host:=regexp_replace(split_part(regexp_replace(lower(v_source_url),'^https?://','','i'),'/',1),'^www\.','','i');
  if nullif(v_host,'') is null or v_host<>v_source_host then return new; end if;
  if v_host = any(array[
    'facebook.com','linkedin.com','instagram.com','x.com','twitter.com','yelp.com','bbb.org',
    'mapquest.com','buildzoom.com','manta.com','chamberofcommerce.com','yellowpages.com',
    'wikipedia.org','crunchbase.com','bloomberg.com','dnb.com','zoominfo.com','opencorporates.com','bizapedia.com'
  ]) then return new; end if;

  update core.organizations
  set website_url=coalesce(website_url,v_website_url),
      attributes=attributes||jsonb_strip_nulls(jsonb_build_object(
        'website_evidence_source_url',v_source_url,
        'website_evidence_authority',v_authority,
        'website_identity_confidence',v_confidence,
        'website_document_evidence_job_id',new.id
      )),updated_at=now()
  where id=v_org_id and status='active';

  update research.document_evidence_jobs
  set source_roots=(
        select coalesce(jsonb_agg(x order by x),'[]'::jsonb)
        from (
          select distinct value as x
          from jsonb_array_elements_text(coalesce(source_roots,'[]'::jsonb)||jsonb_build_array(v_website_url))
        ) q
      ),updated_at=now()
  where id=new.id;

  return new;
end
$$;

revoke all on function research.persist_completed_buyer_research_website_v1() from public, anon, authenticated, service_role;
grant execute on function research.persist_completed_buyer_research_website_v1() to postgres;

drop trigger if exists trg_persist_completed_buyer_research_website_v1 on research.document_evidence_jobs;
create trigger trg_persist_completed_buyer_research_website_v1
after update of state,outcome_metadata on research.document_evidence_jobs
for each row
when (
  new.rule_pack='buyer_organization_contact_v1'
  and new.state='completed'
  and (old.state is distinct from new.state or old.outcome_metadata is distinct from new.outcome_metadata)
)
execute function research.persist_completed_buyer_research_website_v1();

-- Backfill only the newly verified Woodbine root from the completed finding that
-- exercised the autonomous search-discovery path. The evidence row is the source
-- of truth; this is not a guessed URL.
with f as (
  select j.id job_id,
         nullif(j.outcome_metadata->>'organization_id','')::uuid organization_id,
         f.source_url,
         nullif(f.extracted_values->>'website_url','') website_url,
         f.source_authority,
         f.identity_confidence
  from research.document_evidence_jobs j
  join research.document_evidence_findings f on f.job_id=j.id
  where j.id='ce1f491c-b539-477d-82c5-a5d1b593c708'::uuid
    and j.state='completed'
    and f.decision_state='documented'
    and f.identity_confidence>=.95
  order by f.observed_at desc
  limit 1
)
update core.organizations o
set website_url=coalesce(o.website_url,f.website_url),
    attributes=o.attributes||jsonb_strip_nulls(jsonb_build_object(
      'website_evidence_source_url',f.source_url,
      'website_evidence_authority',f.source_authority,
      'website_identity_confidence',f.identity_confidence,
      'website_document_evidence_job_id',f.job_id
    )),updated_at=now()
from f
where o.id=f.organization_id and o.status='active' and f.website_url ~ '^https?://';
