-- Research-only clarification for surface-work survey v2.
update research.surface_work_signal_survey
set notes=regexp_replace(
  coalesce(notes,''),
  '1,253 roof lifecycle records are new-construction age proxies',
  '1,253 raw active roof anchor rows collapse to 920 current deduplicated roof-pressure records; all are new-construction age proxies'
), reviewed_at=now()
where survey_key='commercial_property:roof_recoating';
