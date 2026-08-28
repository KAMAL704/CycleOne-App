-- Physical inventory reconciliation and administrator-only lifecycle actions.

alter table public.cycles
  add column if not exists physical_state text not null default 'unknown',
  add column if not exists last_verified_at timestamptz,
  add column if not exists last_verified_esp_mac text;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.cycles'::regclass and conname = 'cycles_physical_state_check') then
    alter table public.cycles add constraint cycles_physical_state_check
      check (physical_state in ('present', 'absent', 'unknown'));
  end if;
end;
$$;

-- The imported prototype had two bicycles on one one-slot stand. Keep one
-- cycle parked there and leave the other cycle unassigned for an administrator
-- to place at another stand.
update public.cycles
set stand_id = null, status = 'maintenance', physical_state = 'unknown', last_verified_at = null, last_verified_esp_mac = null
where cycle_number = 'CYCLE_2'
  and stand_id = '3d6d8536-8cdb-4c48-b1c4-77789f480b54'::uuid;

create or replace function public.enforce_cycle_slot_capacity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_capacity integer;
  v_occupied integer;
begin
  if new.stand_id is null or new.status not in ('available', 'maintenance', 'disabled') then
    return new;
  end if;
  select capacity into v_capacity from public.stands where id = new.stand_id for update;
  if not found then raise exception 'Stand not found'; end if;
  select count(*) into v_occupied
  from public.cycles
  where stand_id = new.stand_id
    and id <> new.id
    and status in ('available', 'maintenance', 'disabled');
  if v_occupied >= v_capacity then
    raise exception 'Stand capacity is full';
  end if;
  return new;
end;
$$;

drop trigger if exists cycles_enforce_slot_capacity on public.cycles;
create trigger cycles_enforce_slot_capacity
before insert or update of stand_id, status on public.cycles
for each row execute procedure public.enforce_cycle_slot_capacity();

create or replace function public.sync_cycle_presence(p_stand_id uuid, p_esp_mac text, p_present boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_stand public.stands;
  v_cycle public.cycles;
  v_count integer;
  v_mac text := replace(upper(coalesce(p_esp_mac, '')), ':', '');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and status = 'active') then
    raise exception 'Account is not active';
  end if;
  select * into v_stand from public.stands where id = p_stand_id for share;
  if not found or v_stand.status <> 'active' or replace(upper(v_stand.esp_mac), ':', '') <> v_mac then
    raise exception 'Stand authorization failed';
  end if;
  select count(*) into v_count
  from public.cycles
  where stand_id = p_stand_id and status in ('available', 'maintenance', 'disabled');
  if v_count > 1 then raise exception 'Stand has multiple cycles assigned; administrator action required'; end if;
  if v_count = 0 then
    return jsonb_build_object('stand_id', p_stand_id, 'cycle_id', null, 'present', false, 'verified_at', now());
  end if;
  select * into v_cycle from public.cycles
  where stand_id = p_stand_id and status in ('available', 'maintenance', 'disabled') for update;
  update public.cycles
  set physical_state = case when p_present then 'present' else 'absent' end,
      last_verified_at = now(),
      last_verified_esp_mac = v_stand.esp_mac,
      status = case when p_present and status = 'maintenance' then 'available' else status end
  where id = v_cycle.id;
  return jsonb_build_object('stand_id', p_stand_id, 'cycle_id', v_cycle.id,
    'present', p_present, 'verified_at', now());
end;
$$;

drop function if exists public.start_cycle_ride(uuid, uuid);
create or replace function public.start_cycle_ride(p_cycle_id uuid, p_start_stand_id uuid, p_esp_mac text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cycle public.cycles;
  v_stand public.stands;
  v_ride public.rides;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and status = 'active') then raise exception 'Account is not active'; end if;
  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found then raise exception 'Cycle not found'; end if;
  select * into v_stand from public.stands where id = p_start_stand_id for share;
  if not found or v_stand.status <> 'active' or v_cycle.stand_id <> p_start_stand_id then raise exception 'Source stand is unavailable'; end if;
  if replace(upper(v_stand.esp_mac), ':', '') <> replace(upper(coalesce(p_esp_mac, '')), ':', '') then raise exception 'Wrong ESP selected'; end if;
  if v_cycle.status <> 'available' or v_cycle.physical_state = 'absent' then raise exception 'Cycle is no longer physically available at this stand'; end if;
  if exists (select 1 from public.rides where user_id = auth.uid() and status = 'active') then raise exception 'User already has an active ride'; end if;
  insert into public.rides (user_id, cycle_id, start_stand_id, status) values (auth.uid(), p_cycle_id, p_start_stand_id, 'active') returning * into v_ride;
  update public.cycles set status = 'in_use', stand_id = null, physical_state = 'absent', last_verified_at = now(), last_verified_esp_mac = v_stand.esp_mac where id = p_cycle_id;
  return to_jsonb(v_ride);
end;
$$;

drop function if exists public.end_cycle_ride(uuid, uuid, uuid);
create or replace function public.end_cycle_ride(p_ride_id uuid, p_cycle_id uuid, p_end_stand_id uuid, p_esp_mac text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_ride public.rides;
  v_cycle public.cycles;
  v_stand public.stands;
  v_occupied integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_end_stand_id::text, 0));
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.user_id <> auth.uid() or v_ride.status <> 'active' or v_ride.cycle_id <> p_cycle_id then raise exception 'Active ride could not be verified'; end if;
  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found or v_cycle.status <> 'in_use' then raise exception 'Cycle is not in use'; end if;
  select * into v_stand from public.stands where id = p_end_stand_id for update;
  if not found or v_stand.status <> 'active' then raise exception 'Destination stand is unavailable'; end if;
  if replace(upper(v_stand.esp_mac), ':', '') <> replace(upper(coalesce(p_esp_mac, '')), ':', '') then raise exception 'Wrong ESP selected'; end if;
  select count(*) into v_occupied from public.cycles where stand_id = p_end_stand_id and status in ('available', 'maintenance', 'disabled');
  if v_occupied >= v_stand.capacity then raise exception 'Destination stand is full'; end if;
  update public.cycles set status = 'available', stand_id = p_end_stand_id, physical_state = 'present', last_verified_at = now(), last_verified_esp_mac = v_stand.esp_mac where id = p_cycle_id;
  update public.rides set status = 'completed', end_stand_id = p_end_stand_id, ended_at = now() where id = p_ride_id;
  return true;
end;
$$;

revoke all on function public.start_cycle_ride(uuid, uuid, text) from public, anon;
revoke all on function public.end_cycle_ride(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.start_cycle_ride(uuid, uuid, text) to authenticated;
grant execute on function public.end_cycle_ride(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.sync_cycle_presence(uuid, text, boolean) to authenticated;

create or replace function public.admin_add_cycle(p_cycle_number text, p_stand_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cycle public.cycles;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if trim(coalesce(p_cycle_number, '')) = '' then raise exception 'Cycle number is required'; end if;
  insert into public.cycles (cycle_number, qr_code, status, stand_id, physical_state)
  values (trim(p_cycle_number), 'cycleone://cycle/' || gen_random_uuid()::text, 'maintenance', p_stand_id, 'unknown') returning * into v_cycle;
  update public.cycles set qr_code = 'cycleone://cycle/' || id::text where id = v_cycle.id returning * into v_cycle;
  return to_jsonb(v_cycle);
end;
$$;

create or replace function public.admin_assign_cycle(p_cycle_id uuid, p_stand_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cycle public.cycles;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found then raise exception 'Cycle not found'; end if;
  if v_cycle.status = 'in_use' then raise exception 'An in-use cycle cannot be moved'; end if;
  if p_stand_id is not null and not exists (select 1 from public.stands where id = p_stand_id and status = 'active') then raise exception 'Stand is not active'; end if;
  update public.cycles set stand_id = p_stand_id, status = case when p_stand_id is null then 'maintenance' else 'maintenance' end, physical_state = 'unknown', last_verified_at = null, last_verified_esp_mac = null where id = p_cycle_id returning * into v_cycle;
  return to_jsonb(v_cycle);
end;
$$;

create or replace function public.admin_remove_cycle(p_cycle_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if exists (select 1 from public.rides where cycle_id = p_cycle_id and status = 'active') then raise exception 'Cannot remove a cycle with an active ride'; end if;
  update public.cycles set stand_id = null, status = 'disabled', physical_state = 'unknown', last_verified_at = null, last_verified_esp_mac = null where id = p_cycle_id;
  if not found then raise exception 'Cycle not found'; end if;
  return true;
end;
$$;

grant execute on function public.admin_add_cycle(text, uuid) to authenticated;
grant execute on function public.admin_assign_cycle(uuid, uuid) to authenticated;
grant execute on function public.admin_remove_cycle(uuid) to authenticated;

-- Explicit administrator requested by the product owner.
alter table public.profiles disable trigger profiles_protect_access_fields;
update public.profiles set role = 'admin' where lower(email) = lower('kamal_254034051@sliet.ac.in');
alter table public.profiles enable trigger profiles_protect_access_fields;

-- Remove prototype-only relations after their data has been migrated.
drop table if exists public.stand_activities_legacy cascade;
drop table if exists public.rides_legacy cascade;
drop table if exists public.cycles_legacy cascade;
drop table if exists public.stands_legacy cascade;
drop table if exists public.profiles_legacy cascade;
drop table if exists public.blocks cascade;
