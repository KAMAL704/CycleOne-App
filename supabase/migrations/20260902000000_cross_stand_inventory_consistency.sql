-- Cross-stand return consistency.
--
-- A cycle that an ESP has confirmed absent must not occupy a physical slot.
-- Previously sync_cycle_presence counted every assigned row, including stale
-- absent rows.  After a return this left two database rows under one stand and
-- the next inventory check raised "multiple cycles assigned".

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
    -- The ESP is authoritative for this physical slot. Clear all stale
    -- parked rows rather than failing because old absent rows remain linked.
    update public.cycles
    set physical_state = 'absent',
        last_verified_at = now(),
        last_verified_esp_mac = v_stand.esp_mac,
        esp_mac = v_stand.esp_mac
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled')
      and physical_state <> 'absent';

    return jsonb_build_object(
      'stand_id', p_stand_id,
      'cycle_id', null,
      'present', false,
      'verified_at', now()
    );
  end if;

  -- Ignore rows already confirmed absent. They are historical/missing
  -- inventory records and do not represent a cycle in this stand's slot.
  select count(*) into v_count
  from public.cycles
  where stand_id = p_stand_id
    and status in ('available', 'maintenance', 'disabled')
    and physical_state <> 'absent';

  if v_count > 1 then
    raise exception 'Stand has multiple physically present cycles assigned; administrator action required';
  end if;

  if v_count = 0 then
    -- If the database has only stale absent rows but the ESP now reports a
    -- bicycle, reuse the most recently maintained row. With no row at all,
    -- leave the physical finding unassigned for administrator review.
    select * into v_cycle
    from public.cycles
    where stand_id = p_stand_id
      and status in ('available', 'maintenance', 'disabled')
    order by updated_at desc nulls last, created_at desc
    limit 1
    for update;

    if not found then
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

grant execute on function public.sync_cycle_presence(uuid, text, boolean) to authenticated;

-- Protect the one-controller-per-stand invariant even when MACs differ only
-- by case or punctuation. Existing exact-text uniqueness remains in place.
create or replace function public.prevent_duplicate_stand_esp_mac()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.stands other
    where other.id <> new.id
      and replace(upper(other.esp_mac), ':', '') = replace(upper(new.esp_mac), ':', '')
  ) then
    raise exception 'ESP MAC already belongs to another stand';
  end if;
  return new;
end;
$$;

drop trigger if exists stands_prevent_duplicate_esp_mac on public.stands;
create trigger stands_prevent_duplicate_esp_mac
before insert or update of esp_mac on public.stands
for each row execute procedure public.prevent_duplicate_stand_esp_mac();

-- Keep the denormalized cycle ESP field correct when an administrator or a
-- ride RPC moves a cycle between stands. The stand's own MAC remains the
-- authoritative value used by the app and token function.
create or replace function public.sync_cycle_esp_mac()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stand_id is null then
    new.esp_mac := null;
  else
    select esp_mac into new.esp_mac
    from public.stands
    where id = new.stand_id;
  end if;
  return new;
end;
$$;

drop trigger if exists cycles_sync_esp_mac on public.cycles;
create trigger cycles_sync_esp_mac
before insert or update of stand_id on public.cycles
for each row execute procedure public.sync_cycle_esp_mac();
