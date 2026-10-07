-- Test assignments are visible to the assigned user and can use a real ESP
-- endpoint without changing the cycle table or creating a real ride.  This is
-- intentionally an admin-only test mode; it is not a replacement for the
-- normal inventory/ride state machine.

alter table public.admin_test_cycle_assignments
  add column if not exists stand_id uuid references public.stands(id) on delete restrict,
  add column if not exists phase text not null default 'assigned';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'admin_test_cycle_assignments_phase_check'
      and conrelid = 'public.admin_test_cycle_assignments'::regclass
  ) then
    alter table public.admin_test_cycle_assignments
      add constraint admin_test_cycle_assignments_phase_check
      check (phase in ('assigned', 'unlocked'));
  end if;
end;
$$;

create index if not exists admin_test_cycle_assignments_stand_index
  on public.admin_test_cycle_assignments (stand_id, status, created_at desc);

drop policy if exists "users view own active test assignment"
  on public.admin_test_cycle_assignments;
create policy "users view own active test assignment"
  on public.admin_test_cycle_assignments
  for select to authenticated
  using (user_id = auth.uid() and status = 'assigned');

grant select on public.admin_test_cycle_assignments to authenticated;

-- Four-argument version kept for API compatibility.  The stand is optional;
-- the updated app lets the user choose the ESP at unlock time.
create or replace function public.admin_test_assign_cycle(
  p_user_id uuid,
  p_cycle_id uuid,
  p_stand_id uuid,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.admin_test_cycle_assignments;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_user_id is null or p_cycle_id is null then
    raise exception 'User and cycle are required';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found';
  end if;
  if not exists (select 1 from public.cycles where id = p_cycle_id) then
    raise exception 'Cycle not found';
  end if;
  if p_stand_id is not null and not exists (
    select 1 from public.stands
    where id = p_stand_id and status = 'active' and nullif(esp_mac, '') is not null
  ) then
    raise exception 'Test ESP stand is not active or has no MAC';
  end if;

  update public.admin_test_cycle_assignments
  set status = 'removed', removed_at = now()
  where status = 'assigned'
    and (user_id = p_user_id or cycle_id = p_cycle_id);

  insert into public.admin_test_cycle_assignments
    (user_id, cycle_id, stand_id, assigned_by, status, phase, note)
  values
    (p_user_id, p_cycle_id, p_stand_id, auth.uid(), 'assigned', 'assigned', left(coalesce(p_note, ''), 500))
  returning * into v_assignment;

  return to_jsonb(v_assignment);
end;
$$;

-- Keep the old three-argument RPC working.  It is the normal admin path:
-- only a user and cycle are assigned, with no stand number stored.
create or replace function public.admin_test_assign_cycle(
  p_user_id uuid,
  p_cycle_id uuid,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_user_id is null or p_cycle_id is null then
    raise exception 'User and cycle are required';
  end if;
  update public.admin_test_cycle_assignments
  set status = 'removed', removed_at = now()
  where status = 'assigned'
    and (user_id = p_user_id or cycle_id = p_cycle_id);
  insert into public.admin_test_cycle_assignments
    (user_id, cycle_id, assigned_by, status, phase, note)
  values
    (p_user_id, p_cycle_id, auth.uid(), 'assigned', 'assigned', left(coalesce(p_note, ''), 500));
  return jsonb_build_object('legacy', true, 'user_id', p_user_id, 'cycle_id', p_cycle_id);
end;
$$;

create or replace function public.admin_test_start_cycle(
  p_cycle_id uuid,
  p_stand_id uuid,
  p_esp_mac text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.admin_test_cycle_assignments;
  v_stand public.stands;
  v_mac text := replace(upper(coalesce(p_esp_mac, '')), ':', '');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.profiles where id = auth.uid() and status = 'active'
  ) then raise exception 'Account is not active'; end if;

  select * into v_assignment
  from public.admin_test_cycle_assignments
  where user_id = auth.uid()
    and cycle_id = p_cycle_id
    and status = 'assigned'
  for update;
  if not found
     or v_assignment.phase <> 'assigned'
     or (v_assignment.stand_id is not null and v_assignment.stand_id <> p_stand_id) then
    raise exception 'Test cycle assignment is not ready for this stand';
  end if;

  if exists (select 1 from public.rides where user_id = auth.uid() and status = 'active') then
    raise exception 'Finish your real ride before starting a test cycle';
  end if;

  select * into v_stand from public.stands where id = p_stand_id and status = 'active';
  if not found or replace(upper(coalesce(v_stand.esp_mac, '')), ':', '') <> v_mac then
    raise exception 'Wrong ESP selected';
  end if;

  update public.admin_test_cycle_assignments
  set phase = 'unlocked', stand_id = p_stand_id
  where id = v_assignment.id;
  return jsonb_build_object(
    'id', v_assignment.id,
    'cycle_id', v_assignment.cycle_id,
    'start_stand_id', p_stand_id,
    'test_mode', true,
    'test_phase', 'unlocked',
    'started_at', now()
  );
end;
$$;

create or replace function public.admin_test_end_cycle(
  p_cycle_id uuid,
  p_end_stand_id uuid,
  p_esp_mac text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.admin_test_cycle_assignments;
  v_stand public.stands;
  v_mac text := replace(upper(coalesce(p_esp_mac, '')), ':', '');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.profiles where id = auth.uid() and status = 'active'
  ) then raise exception 'Account is not active'; end if;
  select * into v_assignment
  from public.admin_test_cycle_assignments
  where user_id = auth.uid()
    and cycle_id = p_cycle_id
    and status = 'assigned'
  for update;
  if not found or v_assignment.phase <> 'unlocked' then
    raise exception 'No unlocked test cycle is active';
  end if;
  select * into v_stand from public.stands where id = p_end_stand_id and status = 'active';
  if not found or replace(upper(coalesce(v_stand.esp_mac, '')), ':', '') <> v_mac then
    raise exception 'Wrong ESP selected';
  end if;

  update public.admin_test_cycle_assignments
  set status = 'removed', removed_at = now()
  where id = v_assignment.id;
  return true;
end;
$$;

revoke all on function public.admin_test_assign_cycle(uuid, uuid, uuid, text) from public, anon;
revoke all on function public.admin_test_assign_cycle(uuid, uuid, text) from public, anon;
revoke all on function public.admin_test_start_cycle(uuid, uuid, text) from public, anon;
revoke all on function public.admin_test_end_cycle(uuid, uuid, text) from public, anon;
grant execute on function public.admin_test_assign_cycle(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.admin_test_assign_cycle(uuid, uuid, text) to authenticated;
grant execute on function public.admin_test_start_cycle(uuid, uuid, text) to authenticated;
grant execute on function public.admin_test_end_cycle(uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
