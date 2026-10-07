-- Repair legacy stand records that reused one ESP BSSID for multiple stands.
--
-- A BSSID identifies one physical ESP access point, so it must belong to one
-- stand only.  Older data could contain duplicate values because the original
-- table was created before the unique constraint/trigger was installed.  Do
-- not silently guess the real hardware for the duplicate row: keep one
-- canonical stand, disable the other row, and give it a clearly local,
-- temporary MAC which the administrator must replace with that stand's real
-- Serial Monitor BSSID.

-- The repair has to be able to change a duplicate row before the guard is
-- recreated.  The exact-text unique constraint (when present) is not a
-- problem because every repaired value is unique.
drop trigger if exists stands_prevent_duplicate_esp_mac on public.stands;

do $$
declare
  v_group record;
  v_duplicate_id uuid;
  v_placeholder text;
  v_suffix text;
begin
  -- For each normalized MAC, retain the active/oldest stand as canonical.
  -- A duplicate stand is disabled until its real ESP BSSID is entered.
  for v_group in
    select
      replace(upper(esp_mac), ':', '') as mac_key,
      (array_agg(id order by (status = 'active') desc, created_at asc nulls last, id))[1] as keep_id,
      (array_agg(id order by (status = 'active') desc, created_at asc nulls last, id))[2:] as duplicate_ids
    from public.stands
    group by replace(upper(esp_mac), ':', '')
    having count(*) > 1
  loop
    if v_group.duplicate_ids is null then continue; end if;
    foreach v_duplicate_id in array v_group.duplicate_ids
    loop
      -- These rows cannot be trusted to describe a physical location while
      -- their stand has no verified controller.  Put the cycles into an
      -- explicit admin-repair state instead of attaching them to a guessed
      -- stand or leaving a false available count.
      update public.cycles
      set stand_id = null,
          status = 'maintenance',
          physical_state = 'unknown',
          last_verified_at = null,
          last_verified_esp_mac = null,
          esp_mac = null
      where stand_id = v_duplicate_id;

      -- 02 is locally administered/unicast.  Derive the remaining bytes from
      -- the UUID and retry with a salt if an extremely unlikely collision is
      -- found.  The value is intentionally not a usable hardware BSSID.
      v_suffix := upper(substr(md5(v_duplicate_id::text), 1, 10));
      v_placeholder := '02:' || substr(v_suffix, 1, 2) || ':' ||
        substr(v_suffix, 3, 2) || ':' || substr(v_suffix, 5, 2) || ':' ||
        substr(v_suffix, 7, 2) || ':' || substr(v_suffix, 9, 2);
      while exists (
        select 1 from public.stands where esp_mac = v_placeholder
      ) loop
        v_suffix := upper(substr(md5(v_duplicate_id::text || v_placeholder), 1, 10));
        v_placeholder := '02:' || substr(v_suffix, 1, 2) || ':' ||
          substr(v_suffix, 3, 2) || ':' || substr(v_suffix, 5, 2) || ':' ||
          substr(v_suffix, 7, 2) || ':' || substr(v_suffix, 9, 2);
      end loop;

      update public.stands
      set esp_mac = v_placeholder,
          status = 'disabled',
          updated_at = now()
      where id = v_duplicate_id;
    end loop;
  end loop;

  -- Canonical and non-duplicate rows are stored in one stable format.
  update public.stands
  set esp_mac = upper(esp_mac)
  where esp_mac <> upper(esp_mac);
end;
$$;

-- This index closes the case/punctuation loophole left by the old exact-text
-- unique constraint.  The table check already restricts values to six octets.
create unique index if not exists stands_esp_mac_normalized_unique
  on public.stands (replace(upper(esp_mac), ':', ''));

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

create trigger stands_prevent_duplicate_esp_mac
before insert or update of esp_mac on public.stands
for each row execute procedure public.prevent_duplicate_stand_esp_mac();
