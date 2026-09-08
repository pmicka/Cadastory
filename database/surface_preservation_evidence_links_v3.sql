-- Research-only evidence anchors for the expanded surface-preservation survey.

update research.surface_work_signal_survey
set evidence_urls=array[
      'https://www.churchilldownsincorporated.com/churchill-downs-incorporated-reveals-grandstand-club-and-pavilion-renovation-plan-for-churchill-downs-racetrack/',
      'https://sah-archipedia.org/buildings/KY-01-111-0018'
    ] || array_remove(evidence_urls,'https://www.churchilldownsincorporated.com/churchill-downs-incorporated-reveals-grandstand-club-and-pavilion-renovation-plan-for-churchill-downs-racetrack/'),
    evidence_basis='Churchill Downs provides an anchor example of a high-visibility racetrack with a historically painted grandstand exterior and recurring major capital renovation cycles. This supports account-level asset-preservation research, not an inference that each renovation contains exterior cleaning.',
    reviewed_at=now(),updated_at=now()
where survey_key='racetrack_operator:grandstand_and_exposed_steel';

update research.surface_work_signal_survey
set evidence_urls=array['https://www.nps.gov/orgs/1739/upload/preservation-brief-01-cleaning-masonry.pdf'],
    reviewed_at=now(),updated_at=now()
where survey_key='institutional:masonry_clean_tuckpoint_seal';

update research.surface_work_signal_survey
set evidence_urls=array['https://www.nps.gov/orgs/1739/upload/preservation-brief-01-cleaning-masonry.pdf'],
    reviewed_at=now(),updated_at=now()
where survey_key='institutional:waterproofing_masonry_envelope';

update research.surface_work_signal_survey
set evidence_basis='Scout resolves public land-manager context and Kentucky procurement includes a Department of Parks contract record with a painting contractor, but the observed contract lacks enough scope text to prove the structure or cleaning relationship.',
    notes='Treat the Parks painting-contractor record as buyer/category evidence only. It supports surveying built park/lodge facilities, not promoting a specific cleaning opportunity.',
    reviewed_at=now(),updated_at=now()
where survey_key='public_recreation:park_lodge_facility_envelope';

revoke all on research.surface_work_signal_survey from anon,authenticated;
