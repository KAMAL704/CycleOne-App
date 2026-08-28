-- Cycle placement and ride state must go through the capacity-checked RPCs.
revoke insert, update, delete on public.cycles from anon, authenticated;
revoke all on function public.sync_cycle_presence(uuid, text, boolean) from public, anon;
revoke all on function public.admin_add_cycle(text, uuid) from public, anon;
revoke all on function public.admin_assign_cycle(uuid, uuid) from public, anon;
revoke all on function public.admin_remove_cycle(uuid) from public, anon;
grant execute on function public.sync_cycle_presence(uuid, text, boolean) to authenticated;
grant execute on function public.admin_add_cycle(text, uuid) to authenticated;
grant execute on function public.admin_assign_cycle(uuid, uuid) to authenticated;
grant execute on function public.admin_remove_cycle(uuid) to authenticated;
