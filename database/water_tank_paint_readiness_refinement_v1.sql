-- Scout by Cadastory
-- Water-tank painting readiness refinement v1.
-- Research-only. The treatment-specific scheduled/due cues currently observed in Scout
-- all resolve to elevated tanks, so do not promote ground-storage forecast readiness by inheritance.

update research.painting_signal_target_readiness
set forecast_readiness='treatment_specific_now',
    observation_note=concat(
      'WRIS/project evidence is systematic. Current tank-level evidence includes ',
      (select count(*) from research.v_water_tank_paint_forecast_scaffold_v1 where tank_type='ELEVATED' and paint_signal_state='explicit_scheduled_treatment'),
      ' elevated tanks with explicit scheduled-treatment statements, ',
      (select count(*) from research.v_water_tank_paint_forecast_scaffold_v1 where tank_type='ELEVATED' and paint_signal_state='explicit_repaint_age_pressure'),
      ' with explicit repaint-age pressure, ',
      (select count(*) from research.v_water_tank_paint_forecast_scaffold_v1 where tank_type='ELEVATED' and paint_signal_state='documented_exterior_treatment_scope'),
      ' with documented exterior/both treatment scope, and ',
      (select count(*) from research.v_water_tank_paint_forecast_scaffold_v1 where tank_type='ELEVATED' and paint_signal_state='documented_treatment_surface_unresolved'),
      ' with documented treatment scope whose exterior/interior extent remains unresolved.'
    ),
    reviewed_at=now()
where survey_key='water_utility:elevated_water_tank_exterior';

update research.painting_signal_target_readiness
set forecast_readiness='partial_proxy',
    observation_note=concat(
      'Ground-storage treatment projects are extractable, but the currently observed explicit scheduled-treatment and repaint-age-pressure cues resolve to elevated tanks. Keep ground-storage forecast readiness partial until treatment-specific timing evidence is observed for this subtype.'
    ),
    reviewed_at=now()
where survey_key='water_utility:ground_storage_tank_exterior';
