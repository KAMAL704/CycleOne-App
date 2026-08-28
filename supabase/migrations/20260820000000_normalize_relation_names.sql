-- The legacy tables left similarly named foreign-key constraints behind.
-- Normalize the canonical ride constraints so PostgREST can expose the
-- expected embedded relation names to clients that still use them.
do $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_start_stand_id_fkey1')
     and not exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_start_stand_id_fkey') then
    alter table public.rides rename constraint rides_start_stand_id_fkey1 to rides_start_stand_id_fkey;
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_cycle_id_fkey1')
     and not exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_cycle_id_fkey') then
    alter table public.rides rename constraint rides_cycle_id_fkey1 to rides_cycle_id_fkey;
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_user_id_fkey1')
     and not exists (select 1 from pg_constraint where conrelid = 'public.rides'::regclass and conname = 'rides_user_id_fkey') then
    alter table public.rides rename constraint rides_user_id_fkey1 to rides_user_id_fkey;
  end if;
end;
$$;
