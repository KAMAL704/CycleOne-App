-- A small server-side activity feed lets students see stand usage without
-- exposing every rider's email or bypassing the rides table RLS policy.
create or replace function public.get_stand_activity(p_stand_id uuid, p_limit integer default 5)
returns table (
  activity_id uuid,
  stand_id uuid,
  cycle_id uuid,
  cycle_number text,
  user_label text,
  action text,
  activity_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select activity_id, stand_id, cycle_id, cycle_number, user_label, action, activity_at
  from (
    select
      r.id as activity_id,
      r.start_stand_id as stand_id,
      r.cycle_id,
      c.cycle_number,
      coalesce(nullif(trim(p.name), ''), 'CycleOne rider') as user_label,
      'Checkout'::text as action,
      r.started_at as activity_at
    from public.rides r
    join public.cycles c on c.id = r.cycle_id
    left join public.profiles p on p.id = r.user_id
    where r.start_stand_id = p_stand_id
      and exists (select 1 from public.profiles viewer where viewer.id = auth.uid() and viewer.status = 'active')

    union all

    select
      r.id as activity_id,
      r.end_stand_id as stand_id,
      r.cycle_id,
      c.cycle_number,
      coalesce(nullif(trim(p.name), ''), 'CycleOne rider') as user_label,
      'Return'::text as action,
      r.ended_at as activity_at
    from public.rides r
    join public.cycles c on c.id = r.cycle_id
    left join public.profiles p on p.id = r.user_id
    where r.end_stand_id = p_stand_id
      and r.ended_at is not null
      and exists (select 1 from public.profiles viewer where viewer.id = auth.uid() and viewer.status = 'active')
  ) activity
  order by activity_at desc
  limit greatest(1, least(coalesce(p_limit, 5), 5));
$$;

revoke all on function public.get_stand_activity(uuid, integer) from public, anon;
grant execute on function public.get_stand_activity(uuid, integer) to authenticated;
