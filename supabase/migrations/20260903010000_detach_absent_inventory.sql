-- Do not keep a cycle assigned to a physical stand after that stand's ESP
-- has confirmed the slot empty.  The old row was retained with
-- physical_state='absent', which made Admin show two available cycles under a
-- one-slot stand and allowed the next return to look like a duplicate.
-- Existing rows are repaired from Admin → Cycles → Clear stale stand
-- assignment, so this migration does not guess a physical location in bulk.

create or replace function public.sync_cycle_presence(
  p_stand_id uuid,
  p_esp_mac text,
  p_present boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stand public.stands;
  v_cycle public.cycles;
  v_count integer;
  v_mac text := replace(upper(coalesce(p_esp_mac, '')), ':', '');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  ) then
    raise exception 'Account is not active';
  end if;

  select * into v_stand
  from public.stands
  where id = p_stand_id
  for share;
  if not found
     or v_stand.status <> 'active'
     or replace(upper(v_stand.esp_mac), ':', '') <> v_mac then
    raise exception 'Stand authorization failed';
  end if;

  if not p_present then
    -- Empty is authoritative.  Remove the stale location assignment so this
    -- cycle cannot be selected or counted at the empty stand.
    update public.cycles
    set stand_id = null,
        status = case when status = 'available' then 'maintenance' else status end,
        physical_state = 'absent',
        last_verified_at = now(),
        last_verified_esp_mac = v_stand.esp_mac,
        esp_mac = null
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled');

    return jsonb_build_object(
      'stand_id', p_stand_id,
      'cycle_id', null,
      'present', false,
      'verified_at', now()
    );
  end if;

  select count(*) into v_count
  from public.cycles
  where stand_id = p_stand_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent';

  if v_count > 1 then
    raise exception 'Stand has multiple physically present cycles assigned; administrator action required';
  end if;

  if v_count = 0 then
    return jsonb_build_object(
      'stand_id', p_stand_id,
      'cycle_id', null,
      'present', true,
      'verified_at', now()
    );
  end if;

  select * into v_cycle
  from public.cycles
  where stand_id = p_stand_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent'
  order by updated_at desc nulls last, created_at desc
  limit 1
  for update;

  update public.cycles
  set physical_state = 'present',
      last_verified_at = now(),
      last_verified_esp_mac = v_stand.esp_mac,
      esp_mac = v_stand.esp_mac,
      status = case when status = 'maintenance' then 'available' else status end
  where id = v_cycle.id;

  return jsonb_build_object(
    'stand_id', p_stand_id,
    'cycle_id', v_cycle.id,
    'present', true,
    'verified_at', now()
  );
end;
$$;

drop function if exists public.end_cycle_ride(uuid, uuid, uuid, text);
create or replace function public.end_cycle_ride(
  p_ride_id uuid,
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
  v_ride public.rides;
  v_cycle public.cycles;
  v_stand public.stands;
  v_occupied integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_end_stand_id::text, 0));

  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.user_id <> auth.uid() or v_ride.status <> 'active'
     or v_ride.cycle_id <> p_cycle_id then
    raise exception 'Active ride could not be verified';
  end if;

  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found or v_cycle.status <> 'in_use' then
    raise exception 'Cycle is not in use';
  end if;

  select * into v_stand from public.stands where id = p_end_stand_id for update;
  if not found or v_stand.status <> 'active' then
    raise exception 'Destination stand is unavailable';
  end if;
  if replace(upper(v_stand.esp_mac), ':', '') <>
     replace(upper(coalesce(p_esp_mac, '')), ':', '') then
    raise exception 'Wrong ESP selected';
  end if;

  -- Rows already confirmed absent are historical/misplaced records, not
  -- occupied slots. Detach them before placing the physically returned cycle.
  update public.cycles
  set stand_id = null,
      status = case when status = 'available' then 'maintenance' else status end,
      esp_mac = null
  where stand_id = p_end_stand_id
    and id <> p_cycle_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state = 'absent';

  select count(*) into v_occupied
  from public.cycles
  where stand_id = p_end_stand_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent';
  if v_occupied >= v_stand.capacity then
    raise exception 'Destination stand is full';
  end if;

  update public.cycles
  set status = 'available',
      stand_id = p_end_stand_id,
      physical_state = 'present',
      last_verified_at = now(),
      last_verified_esp_mac = v_stand.esp_mac,
      esp_mac = v_stand.esp_mac
  where id = p_cycle_id;
  update public.rides
  set status = 'completed',
      end_stand_id = p_end_stand_id,
      ended_at = now()
  where id = p_ride_id;
  return true;
end;
$$;

grant execute on function public.sync_cycle_presence(uuid, text, boolean) to authenticated;
grant execute on function public.end_cycle_ride(uuid, uuid, uuid, text) to authenticated;
