-- Keep cycle creation consistent with assignment: disabled/maintenance stands
-- must never receive a usable inventory record.
create or replace function public.admin_add_cycle(p_cycle_number text, p_stand_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cycle public.cycles;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if trim(coalesce(p_cycle_number, '')) = '' then raise exception 'Cycle number is required'; end if;
  if p_stand_id is not null and not exists (select 1 from public.stands where id = p_stand_id and status = 'active') then
    raise exception 'Stand is not active';
  end if;
  insert into public.cycles (cycle_number, qr_code, status, stand_id, physical_state)
  values (trim(p_cycle_number), 'cycleone://cycle/' || gen_random_uuid()::text, 'maintenance', p_stand_id, 'unknown')
  returning * into v_cycle;
  update public.cycles set qr_code = 'cycleone://cycle/' || id::text where id = v_cycle.id returning * into v_cycle;
  return to_jsonb(v_cycle);
end;
$$;

grant execute on function public.admin_add_cycle(text, uuid) to authenticated;
