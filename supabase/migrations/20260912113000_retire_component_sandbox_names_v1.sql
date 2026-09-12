-- Retire the names-only sandbox handshake after the v16 component/gateway runtime
-- is deployed. The v16 discriminated result no longer consumes this RPC.
--
-- Deployment ordering is intentional: do not apply this migration before the
-- aligned v16 Edge Functions are live, because the currently deployed v15
-- component server still calls this function.

drop function if exists public.scout_get_component_sandbox_names_v1_internal();
