-- Allow administrators to rename a cycle without opening direct cycle writes
-- to normal authenticated users.
create or replace function public.admin_rename_cycle(
  p_cycle_id uuid,
  p_cycle_number text
)
returns public.cycles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cycle public.cycles;
  v_name text := trim(coalesce(p_cycle_number, ''));
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if v_name = '' then
    raise exception 'Cycle name is required';
  end if;
  update public.cycles
  set cycle_number = v_name, updated_at = now()
  where id = p_cycle_id
  returning * into v_cycle;
  if not found then
    raise exception 'Cycle not found';
  end if;
  return v_cycle;
exception
  when unique_violation then
    raise exception 'A cycle with this name already exists';
end;
$$;

revoke all on function public.admin_rename_cycle(uuid, text) from public, anon;
grant execute on function public.admin_rename_cycle(uuid, text) to authenticated;
