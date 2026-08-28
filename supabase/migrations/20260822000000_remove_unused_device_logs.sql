-- device_logs belonged to the prototype and is not read or written by the
-- CycleOne client or Edge Functions. Remove it from the public schema.
drop table if exists public.device_logs cascade;
