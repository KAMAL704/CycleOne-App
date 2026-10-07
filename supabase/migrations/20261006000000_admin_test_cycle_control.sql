-- Administrator-only test controls. These assignments intentionally do not
-- change cycles, stands, ESP inventory, or real rides. They let an operator
-- simulate a user having a cycle while testing inconsistent hardware states.

create table if not exists public.admin_test_cycle_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  cycle_id uuid not null references public.cycles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'assigned'
    check (status in ('assigned', 'removed')),
  note text not null default '',
  created_at timestamptz not null default now(),
  removed_at timestamptz
);

create index if not exists admin_test_cycle_assignments_user_index
  on public.admin_test_cycle_assignments (user_id, created_at desc);
create index if not exists admin_test_cycle_assignments_cycle_index
  on public.admin_test_cycle_assignments (cycle_id, created_at desc);
create unique index if not exists one_active_admin_test_assignment_per_user
  on public.admin_test_cycle_assignments (user_id)
  where status = 'assigned';
create unique index if not exists one_active_admin_test_assignment_per_cycle
  on public.admin_test_cycle_assignments (cycle_id)
  where status = 'assigned';

alter table public.admin_test_cycle_assignments enable row level security;
drop policy if exists "admins manage test cycle assignments"
  on public.admin_test_cycle_assignments;
create policy "admins manage test cycle assignments"
  on public.admin_test_cycle_assignments
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

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

  -- Replace prior test assignments for either resource. This guarantees that
  -- the test panel never displays the same user/cycle as assigned twice.
  update public.admin_test_cycle_assignments
  set status = 'removed', removed_at = now()
  where status = 'assigned'
    and (user_id = p_user_id or cycle_id = p_cycle_id);

  insert into public.admin_test_cycle_assignments
    (user_id, cycle_id, assigned_by, note)
  values
    (p_user_id, p_cycle_id, auth.uid(), left(coalesce(p_note, ''), 500))
  returning * into v_assignment;

  return to_jsonb(v_assignment);
end;
$$;

create or replace function public.admin_test_unassign_cycle(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  update public.admin_test_cycle_assignments
  set status = 'removed', removed_at = now()
  where user_id = p_user_id and status = 'assigned';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.admin_test_assign_cycle(uuid, uuid, text)
  to authenticated;
grant execute on function public.admin_test_unassign_cycle(uuid)
  to authenticated;

-- Use a security-definer RPC for blocking/unblocking. The existing profile
-- protection trigger correctly rejects direct service-role updates because
-- service-role requests have no auth.uid(); this RPC preserves the caller's
-- administrator identity while performing the protected update.
create or replace function public.admin_set_user_status(
  p_user_id uuid,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot disable your own admin account';
  end if;
  if p_status not in ('active', 'disabled') then
    raise exception 'Invalid account status';
  end if;
  update public.profiles
  set status = p_status
  where id = p_user_id;
  if not found then
    raise exception 'User not found';
  end if;
  return p_status;
end;
$$;

grant execute on function public.admin_set_user_status(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';
