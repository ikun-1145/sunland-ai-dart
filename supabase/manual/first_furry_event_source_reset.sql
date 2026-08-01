-- Run manually exactly once during the first production source cutover.
-- Do not add this statement to a migration, workflow, Edge Function, or RPC.
truncate public.furry_events restart identity;
