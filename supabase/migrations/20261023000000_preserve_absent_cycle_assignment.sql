-- Inventory truth and ride movement.
--
-- An ESP reporting an empty slot must not erase the administrator's logical
-- assignment.  Keep the cycle linked to that stand, mark it physically
-- absent, and let the UI show "stand · absent".  Only a real ride moves the
-- cycle out of the source stand (status=in_use, stand_id=null).

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
    -- Keep the logical assignment.  An absent row is not counted as an
    -- occupied slot by the capacity trigger or by return_cycle_ride.
    update public.cycles
    set physical_state = 'absent',
        last_verified_at = now(),
        last_verified_esp_mac = v_stand.esp_mac,
        esp_mac = v_stand.esp_mac
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled');

    return jsonb_build_object(
      'stand_id', p_stand_id,
      'cycle_id', null,
      'present', false,
      'verified_at', now()
    );
  end if;

  -- A one-slot stand may contain one physically-present cycle. Rows already
  -- confirmed absent remain available for audit and can be reused when the
  -- ESP later reports a cycle at this stand.
  select count(*) into v_count
  from public.cycles
  where stand_id = p_stand_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent';

  if v_count > 1 then
    raise exception 'Stand has multiple physically present cycles assigned; administrator action required';
  end if;

  if v_count = 0 then
    select * into v_cycle
    from public.cycles
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled')
    order by updated_at desc nulls last, created_at desc
    limit 1
    for update;

    if not found then
      -- The ESP can prove a bicycle is present, but it cannot identify an
      -- unassigned cycle. Keep that finding for an administrator to repair.
      return jsonb_build_object(
        'stand_id', p_stand_id,
        'cycle_id', null,
        'present', true,
        'verified_at', now()
      );
    end if;
  else
    select * into v_cycle
    from public.cycles
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled')
      and physical_state <> 'absent'
    order by updated_at desc nulls last, created_at desc
    limit 1
    for update;
  end if;

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

-- Keep absent historical assignments linked to their last verified ESP when
-- an older deployment already detached them. This is conservative: only an
-- exact normalized MAC match and an empty physical stand are repaired.
do $$
declare
  v_row record;
begin
  for v_row in
    select c.id as cycle_id, s.id as stand_id
    from public.cycles c
    join public.stands s
      on replace(upper(coalesce(c.last_verified_esp_mac, '')), ':', '') =
         replace(upper(s.esp_mac), ':', '')
    where c.stand_id is null
      and c.status in ('available', 'maintenance', 'disabled')
      and c.physical_state = 'absent'
      and not exists (
        select 1
        from public.cycles occupied
        where occupied.stand_id = s.id
          and occupied.status in ('available', 'maintenance', 'disabled')
          and occupied.physical_state <> 'absent'
      )
  loop
    update public.cycles
    set stand_id = v_row.stand_id,
        esp_mac = (select esp_mac from public.stands where id = v_row.stand_id)
    where id = v_row.cycle_id
      and stand_id is null;
  end loop;
end;
$$;

-- The prior function detached absent rows before a return. That made a cycle
-- disappear from its assigned stand even though no ride had moved it. The
-- destination capacity check already ignores physical_state='absent', so the
-- stale-row cleanup is no longer needed.
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
  set status = 'completed', end_stand_id = p_end_stand_id, ended_at = now()
  where id = p_ride_id;
  return true;
end;
$$;

grant execute on function public.sync_cycle_presence(uuid, text, boolean) to authenticated;
grant execute on function public.end_cycle_ride(uuid, uuid, uuid, text) to authenticated;
