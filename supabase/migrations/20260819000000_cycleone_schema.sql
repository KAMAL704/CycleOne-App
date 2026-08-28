-- CycleOne production schema. Works on a clean Supabase project and includes
-- a guarded cutover for the legacy prototype schema. All ride-state writes go
-- through the two RPCs at the end of this file.

create extension if not exists pgcrypto;

-- The first CycleOne prototype used a different schema (`mobile` instead of
-- `phone`, `total_slots` instead of `capacity`, text cycle ids, and
-- `return_stand_id` on rides). Keep those rows for audit, but move the legacy
-- relations out of the way before creating the production contract below.
-- This makes the migration safe to run against the currently linked project
-- as well as against a clean Supabase project.
do $$
begin
  if to_regclass('public.rides') is not null
     and to_regclass('public.rides_legacy') is null
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rides' and column_name = 'started_at') then
    alter table public.rides rename to rides_legacy;
  end if;
  if to_regclass('public.cycles') is not null
     and to_regclass('public.cycles_legacy') is null
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'cycles' and column_name = 'cycle_number') then
    alter table public.cycles rename to cycles_legacy;
  end if;
  if to_regclass('public.stands') is not null
     and to_regclass('public.stands_legacy') is null
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stands' and column_name = 'location') then
    alter table public.stands rename to stands_legacy;
  end if;
  if to_regclass('public.profiles') is not null
     and to_regclass('public.profiles_legacy') is null
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'registration_id') then
    alter table public.profiles rename to profiles_legacy;
  end if;
  if to_regclass('public.stand_activities') is not null
     and to_regclass('public.stand_activities_legacy') is null then
    alter table public.stand_activities rename to stand_activities_legacy;
  end if;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email text not null,
  phone text not null default '',
  registration_id text not null default '',
  role text not null default 'student' check (role in ('student', 'admin')),
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_registration_id_unique
  on public.profiles (registration_id) where registration_id <> '';

create table if not exists public.stands (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text not null default '',
  latitude double precision,
  longitude double precision,
  esp_mac text not null unique check (esp_mac ~ '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'),
  esp_ssid text not null,
  esp_password text not null,
  esp_ip inet not null default '10.10.10.10',
  esp_port integer not null default 80 check (esp_port between 1 and 65535),
  capacity integer not null default 1 check (capacity > 0),
  status text not null default 'active' check (status in ('active', 'disabled', 'maintenance')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cycles (
  id uuid primary key default gen_random_uuid(),
  cycle_number text not null unique,
  qr_code text not null unique,
  status text not null default 'available' check (status in ('available', 'in_use', 'maintenance', 'disabled')),
  stand_id uuid references public.stands(id) on delete restrict,
  esp_mac text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint available_cycle_requires_stand check (status <> 'available' or stand_id is not null)
);

create index if not exists cycles_stand_status_index on public.cycles (stand_id, status);

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  cycle_id uuid not null references public.cycles(id) on delete restrict,
  start_stand_id uuid not null references public.stands(id) on delete restrict,
  end_stand_id uuid references public.stands(id) on delete restrict,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  constraint completed_ride_has_end check ((status = 'completed') = (ended_at is not null and end_stand_id is not null))
);

create unique index if not exists one_active_ride_per_user on public.rides (user_id) where status = 'active';
create unique index if not exists one_active_ride_per_cycle on public.rides (cycle_id) where status = 'active';
create index if not exists rides_history_index on public.rides (user_id, started_at desc);

-- Preserve rows from the prototype schema. The legacy tables are deliberately
-- retained with a `_legacy` suffix so an administrator can audit or export
-- them after the cutover.
do $$
declare
  legacy_table text;
begin
  if to_regclass('public.profiles_legacy') is not null then
    insert into public.profiles (id, name, email, phone, registration_id, role, status, created_at, updated_at)
    select
      p.id,
      coalesce(to_jsonb(p) ->> 'name', ''),
      coalesce(to_jsonb(p) ->> 'email', ''),
      coalesce(to_jsonb(p) ->> 'mobile', ''),
      coalesce(nullif(to_jsonb(p) ->> 'registration_id', ''), 'legacy-' || substr(md5(p.id::text), 1, 12)),
      case when lower(coalesce(to_jsonb(p) ->> 'role', 'student')) = 'admin' then 'admin' else 'student' end,
      case when lower(coalesce(to_jsonb(p) ->> 'is_blocked', 'false')) in ('true', 't', '1') then 'disabled' else 'active' end,
      coalesce((to_jsonb(p) ->> 'created_at')::timestamptz, now()),
      coalesce((to_jsonb(p) ->> 'updated_at')::timestamptz, now())
    from public.profiles_legacy p
    where exists (select 1 from auth.users u where u.id = p.id)
    on conflict (id) do nothing;
  end if;

  if to_regclass('public.stands_legacy') is not null then
    insert into public.stands (id, name, location, latitude, longitude, esp_mac, esp_ssid, esp_password, esp_ip, esp_port, capacity, status, created_at, updated_at)
    select
      s.id,
      coalesce(s.name, 'Unnamed stand'),
      coalesce((select b.name from public.blocks b where b.id = s.block_id), ''),
      s.latitude,
      s.longitude,
      case
        when upper(coalesce(s.esp_mac, '')) ~ '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' then upper(s.esp_mac)
        else '02:00:' || upper(substr(replace(s.id::text, '-', ''), 1, 2)) || ':' || upper(substr(replace(s.id::text, '-', ''), 3, 2)) || ':' || upper(substr(replace(s.id::text, '-', ''), 5, 2)) || ':' || upper(substr(replace(s.id::text, '-', ''), 7, 2))
      end,
      'UNCONFIGURED',
      'UNCONFIGURED',
      '10.10.10.10'::inet,
      80,
      greatest(coalesce(s.total_slots, 1), 1),
      'maintenance',
      coalesce(s.created_at, now()),
      now()
    from public.stands_legacy s
    on conflict (id) do nothing;
  end if;

  if to_regclass('public.cycles_legacy') is not null then
    insert into public.cycles (id, cycle_number, qr_code, status, stand_id, esp_mac, created_at, updated_at)
    select
      gen_random_uuid(),
      s.id::text,
      'cycleone://cycle/' || gen_random_uuid()::text,
      case
        when lower(coalesce(s.status, 'maintenance')) = 'available'
             and exists (select 1 from public.stands st where st.id = s.stand_id) then 'available'
        when lower(coalesce(s.status, 'maintenance')) = 'in_use' then 'in_use'
        when lower(coalesce(s.status, 'maintenance')) = 'disabled' then 'disabled'
        else 'maintenance'
      end,
      case
        when lower(coalesce(s.status, 'maintenance')) = 'available'
             and exists (select 1 from public.stands st where st.id = s.stand_id) then s.stand_id
        else null
      end,
      nullif(s.mac_address, ''),
      coalesce(s.created_at, now()),
      now()
    from public.cycles_legacy s
    where not exists (select 1 from public.cycles c where c.cycle_number = s.id::text);

    -- The QR value above must contain the generated UUID, not a second random
    -- UUID. Normalize it after insertion so every QR resolves to its row.
    update public.cycles c
    set qr_code = 'cycleone://cycle/' || c.id::text
    where c.qr_code like 'cycleone://cycle/%';
  end if;

  if to_regclass('public.rides_legacy') is not null then
    insert into public.rides (id, user_id, cycle_id, start_stand_id, end_stand_id, started_at, ended_at, status, created_at)
    select
      r.id,
      r.user_id,
      c.id,
      r.start_stand_id,
      case when r.return_stand_id is not null and exists (select 1 from public.stands st where st.id = r.return_stand_id) then r.return_stand_id else null end,
      coalesce(r.start_time, now()),
      case when lower(coalesce(r.status, 'cancelled')) = 'completed' and r.end_time is not null and r.return_stand_id is not null then r.end_time else null end,
      case
        when lower(coalesce(r.status, 'cancelled')) = 'active' then 'active'
        when lower(coalesce(r.status, 'cancelled')) = 'completed'
             and r.end_time is not null
             and r.return_stand_id is not null
             and exists (select 1 from public.stands st where st.id = r.return_stand_id) then 'completed'
        else 'cancelled'
      end,
      coalesce(r.created_at, now())
    from public.rides_legacy r
    join public.cycles c on c.cycle_number = r.cycle_id::text
    where exists (select 1 from public.profiles p where p.id = r.user_id)
      and exists (select 1 from public.stands st where st.id = r.start_stand_id)
    on conflict do nothing;
  end if;

  -- Legacy rows stay available to service-role operators for audit, but they
  -- must not remain part of the client-facing API after the cutover.
  for legacy_table in select unnest(array['profiles_legacy', 'stands_legacy', 'cycles_legacy', 'rides_legacy', 'stand_activities_legacy']) loop
    if to_regclass('public.' || legacy_table) is not null then
      execute format('revoke all on table public.%I from anon, authenticated', legacy_table);
    end if;
  end loop;
end;
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute procedure public.set_updated_at();
drop trigger if exists stands_set_updated_at on public.stands;
create trigger stands_set_updated_at before update on public.stands for each row execute procedure public.set_updated_at();
drop trigger if exists cycles_set_updated_at on public.cycles;
create trigger cycles_set_updated_at before update on public.cycles for each row execute procedure public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, phone, registration_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'registration_id', '')
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

create table if not exists public.settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.settings enable row level security;
drop policy if exists "public reads app settings" on public.settings;
create policy "public reads app settings" on public.settings for select to anon, authenticated using (true);
drop policy if exists "admin manages app settings" on public.settings;
create policy "admin manages app settings" on public.settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
insert into public.settings (key, value) values ('maintenance_mode', 'false') on conflict (key) do nothing;

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.feedback enable row level security;
drop policy if exists "users submit feedback" on public.feedback;
create policy "users submit feedback" on public.feedback for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "users or admins view feedback" on public.feedback;
create policy "users or admins view feedback" on public.feedback for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- RLS alone cannot stop a user changing role/status in a row they own, so this
-- trigger protects those columns even if broad update privileges are granted.
create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and (
    new.role is distinct from old.role or
    new.status is distinct from old.status or
    new.email is distinct from old.email
  ) then
    raise exception 'Only an administrator can change account access fields';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_access_fields on public.profiles;
create trigger profiles_protect_access_fields before update on public.profiles
for each row execute procedure public.protect_profile_fields();

alter table public.profiles enable row level security;
alter table public.stands enable row level security;
alter table public.cycles enable row level security;
alter table public.rides enable row level security;

drop policy if exists "profiles own or admin select" on public.profiles;
create policy "profiles own or admin select" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists "profiles own or admin update" on public.profiles;
create policy "profiles own or admin update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

drop policy if exists "authenticated users view active stands" on public.stands;
create policy "authenticated users view active stands" on public.stands for select to authenticated
  using (status = 'active' or public.is_admin());
drop policy if exists "admin manages stands" on public.stands;
create policy "admin manages stands" on public.stands for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "authenticated users view cycles" on public.cycles;
create policy "authenticated users view cycles" on public.cycles for select to authenticated using (true);
drop policy if exists "admin manages cycles" on public.cycles;
create policy "admin manages cycles" on public.cycles for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "users view their rides or admin" on public.rides;
create policy "users view their rides or admin" on public.rides for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "admin manages rides" on public.rides;
create policy "admin manages rides" on public.rides for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Hardware has already confirmed the unlock when this RPC runs. The cycle row
-- lock plus partial indexes makes races fail atomically rather than creating a
-- duplicate active ride.
create or replace function public.start_cycle_ride(p_cycle_id uuid, p_start_stand_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cycle public.cycles;
  v_stand public.stands;
  v_ride public.rides;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and status = 'active') then
    raise exception 'Account is not active';
  end if;
  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found then raise exception 'Cycle not found'; end if;
  if v_cycle.status <> 'available' or v_cycle.stand_id <> p_start_stand_id then
    raise exception 'Cycle is no longer available at this stand';
  end if;
  select * into v_stand from public.stands where id = p_start_stand_id for share;
  if not found or v_stand.status <> 'active' then raise exception 'Source stand is unavailable'; end if;
  if exists (select 1 from public.rides where user_id = auth.uid() and status = 'active') then
    raise exception 'User already has an active ride';
  end if;
  insert into public.rides (user_id, cycle_id, start_stand_id, status)
  values (auth.uid(), p_cycle_id, p_start_stand_id, 'active') returning * into v_ride;
  -- A cycle is no longer parked at its source stand once the lock opens.
  update public.cycles set status = 'in_use', stand_id = null where id = p_cycle_id;
  return to_jsonb(v_ride);
end;
$$;

-- Same transaction moves the only database representation of a returned cycle
-- and completes the ride. Advisory locking serializes capacity checks for a
-- destination stand without allowing two concurrent returns to overfill it.
create or replace function public.end_cycle_ride(p_ride_id uuid, p_cycle_id uuid, p_end_stand_id uuid)
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
  if not found or v_ride.user_id <> auth.uid() or v_ride.status <> 'active' or v_ride.cycle_id <> p_cycle_id then
    raise exception 'Active ride could not be verified';
  end if;
  select * into v_cycle from public.cycles where id = p_cycle_id for update;
  if not found or v_cycle.status <> 'in_use' then raise exception 'Cycle is not in use'; end if;
  select * into v_stand from public.stands where id = p_end_stand_id for update;
  if not found or v_stand.status <> 'active' then raise exception 'Destination stand is unavailable'; end if;
  -- A stand slot is occupied by a parked cycle even when that cycle is in
  -- maintenance/disabled. An in-use cycle has physically left the stand.
  select count(*) into v_occupied
  from public.cycles
  where stand_id = p_end_stand_id and status in ('available', 'maintenance', 'disabled');
  if v_occupied >= v_stand.capacity then raise exception 'Destination stand is full'; end if;
  update public.cycles set status = 'available', stand_id = p_end_stand_id where id = p_cycle_id;
  update public.rides set status = 'completed', end_stand_id = p_end_stand_id, ended_at = now() where id = p_ride_id;
  return true;
end;
$$;

revoke all on function public.start_cycle_ride(uuid, uuid) from public, anon;
revoke all on function public.end_cycle_ride(uuid, uuid, uuid) from public, anon;
grant execute on function public.start_cycle_ride(uuid, uuid) to authenticated;
grant execute on function public.end_cycle_ride(uuid, uuid, uuid) to authenticated;
