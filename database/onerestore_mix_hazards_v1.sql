-- Scout OneRestore mix hazards v1
-- Mirrors production migration 20260908225807 onerestore_mix_hazards_v1.
-- Encodes product-specific do-not-mix rules without assuming sequential-use safety.

with d as (
  insert into knowledge.documents(
    title,document_type,publisher,source_url,authority_tier,review_status,
    attributes,lifecycle_status,canonical_source_key,reviewed_at,updated_at
  ) values (
    'CDC Chemical Disinfectants — Hypochlorite Acid Mixing Hazard','regulatory_guidance','CDC',
    'https://www.cdc.gov/infection-control/hcp/disinfection-sterilization/chemical-disinfectants.html',
    'regulatory','reviewed',jsonb_build_object('captured_on','2026-09-08','evidence_role','acid_hypochlorite_mix_hazard'),
    'reference_only','cdc:hypochlorite:acid:chlorine-gas',now(),now()
  ) on conflict (canonical_source_key) where canonical_source_key is not null
  do update set title=excluded.title,source_url=excluded.source_url,attributes=excluded.attributes,
                review_status='reviewed',reviewed_at=now(),updated_at=now()
  returning id
), doc as (
  select id from d union all select id from knowledge.documents where canonical_source_key='cdc:hypochlorite:acid:chlorine-gas' limit 1
)
insert into knowledge.claims(document_id,claim_type,statement,structured_value,source_location,applicability,hard_stop,confidence,status,reviewed_at,updated_at)
select doc.id,'safety_absolute',
 'CDC states that sodium hypochlorite can release toxic chlorine gas when mixed with acid. OneRestore current SDS discloses hydrochloric acid, so simultaneous mixing with sodium hypochlorite is prohibited in Scout.',
 jsonb_build_object('mix_disposition','prohibited','acid_hypochlorite_chlorine_gas_hazard',true,'oneRestore_contains_hydrochloric_acid',true),
 'CDC chlorine/hypochlorite guidance',jsonb_build_object('product_slug','eaco-chem-onerestore'),true,1.0,'active',now(),now()
from doc where not exists(select 1 from knowledge.claims c where c.document_id=doc.id and c.statement like 'CDC states that sodium hypochlorite can release toxic chlorine gas%');

with p as (select id from cleaning.products where slug='eaco-chem-onerestore'),
     cdc as (select c.id from knowledge.claims c join knowledge.documents d on d.id=c.document_id where d.canonical_source_key='cdc:hypochlorite:acid:chlorine-gas' and c.claim_type='safety_absolute' limit 1),
     sds as (select c.id from knowledge.claims c join knowledge.documents d on d.id=c.document_id where d.canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1' and c.claim_type='incompatibility' limit 1),
     x as (
       select * from (values
         ('sodium-hypochlorite'::text,'prohibited'::text,
          jsonb_build_object('do_not_mix',true,'simultaneous_contact_prohibited',true,'sequential_use_requires_complete_separation_and_job_specific_procedure',true),
          'OneRestore SDS discloses hydrochloric acid. CDC states that hypochlorite mixed with acid can release toxic chlorine gas.',1.0::numeric,'cdc'::text,
          jsonb_build_object('rule_version','onerestore_mix_hazards_v1','hazard','chlorine_gas_release')),
         ('sodium-hydroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),
          'OneRestore SDS identifies strong alkali as incompatible; sodium hydroxide is treated as a strong-alkali mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true)),
         ('potassium-hydroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),
          'OneRestore SDS identifies strong alkali as incompatible; potassium hydroxide is treated as a strong-alkali mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true)),
         ('hydrogen-peroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),
          'OneRestore SDS identifies oxidizing compounds as incompatible; hydrogen peroxide is treated as an oxidizer mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true))
       ) v(agent_slug,disposition,requirements,rationale,confidence,evidence_kind,attributes)
     )
insert into cleaning.product_mix_rules(product_id,other_chemical_agent_id,disposition,requirements,rationale,evidence_claim_id,confidence,attributes,created_at,updated_at)
select p.id,a.id,x.disposition,x.requirements,x.rationale,case when x.evidence_kind='cdc' then cdc.id else sds.id end,x.confidence,x.attributes,now(),now()
from p cross join cdc cross join sds join x on true join cleaning.chemical_agents a on a.slug=x.agent_slug
where not exists(select 1 from cleaning.product_mix_rules r where r.product_id=p.id and r.other_chemical_agent_id=a.id);

update cleaning.product_mix_rules r
set disposition=x.disposition,requirements=x.requirements,rationale=x.rationale,
    evidence_claim_id=case when x.evidence_kind='cdc' then cdc.id else sds.id end,
    confidence=x.confidence,attributes=x.attributes,updated_at=now()
from cleaning.products p,
     (select c.id from knowledge.claims c join knowledge.documents d on d.id=c.document_id where d.canonical_source_key='cdc:hypochlorite:acid:chlorine-gas' and c.claim_type='safety_absolute' limit 1) cdc,
     (select c.id from knowledge.claims c join knowledge.documents d on d.id=c.document_id where d.canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1' and c.claim_type='incompatibility' limit 1) sds,
     (values
       ('sodium-hypochlorite'::text,'prohibited'::text,jsonb_build_object('do_not_mix',true,'simultaneous_contact_prohibited',true,'sequential_use_requires_complete_separation_and_job_specific_procedure',true),'OneRestore SDS discloses hydrochloric acid. CDC states that hypochlorite mixed with acid can release toxic chlorine gas.',1.0::numeric,'cdc'::text,jsonb_build_object('rule_version','onerestore_mix_hazards_v1','hazard','chlorine_gas_release')),
       ('sodium-hydroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),'OneRestore SDS identifies strong alkali as incompatible; sodium hydroxide is treated as a strong-alkali mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true)),
       ('potassium-hydroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),'OneRestore SDS identifies strong alkali as incompatible; potassium hydroxide is treated as a strong-alkali mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true)),
       ('hydrogen-peroxide','prohibited',jsonb_build_object('do_not_mix',true,'basis','OneRestore SDS §10.5 incompatible material class'),'OneRestore SDS identifies oxidizing compounds as incompatible; hydrogen peroxide is treated as an oxidizer mix prohibition.',0.99::numeric,'sds',jsonb_build_object('rule_version','onerestore_mix_hazards_v1','class_based_from_product_sds',true))
     ) x(agent_slug,disposition,requirements,rationale,confidence,evidence_kind,attributes), cleaning.chemical_agents a
where p.slug='eaco-chem-onerestore' and a.slug=x.agent_slug and r.product_id=p.id and r.other_chemical_agent_id=a.id;
