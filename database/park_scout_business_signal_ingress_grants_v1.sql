-- Keep Scout business-signal ingestion parked at both behavior and API privilege layers.
-- The function remains fail-closed and available only to trusted internal roles.

revoke execute on function public.scout_submit_connection_business_signal_v1(uuid,text,jsonb,jsonb) from public;
revoke execute on function public.scout_submit_connection_business_signal_v1(uuid,text,jsonb,jsonb) from anon;
revoke execute on function public.scout_submit_connection_business_signal_v1(uuid,text,jsonb,jsonb) from authenticated;

grant execute on function public.scout_submit_connection_business_signal_v1(uuid,text,jsonb,jsonb) to service_role;
