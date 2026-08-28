-- A cycle confirmed absent by the ESP no longer occupies a physical slot.
create or replace function public.enforce_cycle_slot_capacity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_capacity integer;
  v_occupied integer;
begin
  if new.stand_id is null or new.status not in ('available', 'maintenance', 'disabled') then return new; end if;
  select capacity into v_capacity from public.stands where id = new.stand_id for update;
  if not found then raise exception 'Stand not found'; end if;
  select count(*) into v_occupied
  from public.cycles
  where stand_id = new.stand_id and id <> new.id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent';
  if v_occupied >= v_capacity then raise exception 'Stand capacity is full'; end if;
  return new;
end;
$$;

drop function if exists public.end_cycle_ride(uuid, uuid, uuid, text);
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
  select count(*) into v_occupied from public.cycles
  where stand_id = p_end_stand_id and status in ('available', 'maintenance', 'disabled') and physical_state <> 'absent';
  if v_occupied >= v_stand.capacity then raise exception 'Destination stand is full'; end if;
  update public.cycles set status = 'available', stand_id = p_end_stand_id, physical_state = 'present', last_verified_at = now(), last_verified_esp_mac = v_stand.esp_mac where id = p_cycle_id;
  update public.rides set status = 'completed', end_stand_id = p_end_stand_id, ended_at = now() where id = p_ride_id;
  return true;
end;
$$;

grant execute on function public.end_cycle_ride(uuid, uuid, uuid, text) to authenticated;
