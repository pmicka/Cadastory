-- Scout by Cadastory
-- Restore RLS invariants for internal surface-work research tables.
-- No new grants or policies are added; existing access remains owner/internal only.

alter table research.surface_work_signal_survey enable row level security;
alter table research.surface_work_source_capabilities enable row level security;
