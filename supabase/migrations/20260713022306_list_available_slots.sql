create function public.list_available_slots(p_from timestamptz, p_to timestamptz)
  returns setof timestamptz
  -- one row per bookable slot in [p_from, p_to] that has >= 1 free traveller.
  security definer
  set search_path = ''
  language sql
  as $$
  select
    slot
  from
    generate_series(date_trunc('hour', p_from, 'UTC'), -- align lower bound to the hour (tz-independent)
      p_to, interval '1 hour') as slot
where
  slot >= p_from
  and slot < p_to -- half-open window [p_from, p_to)
  and slot > now() -- don't check in the past
  -- equiv to `is_bookable_start_time` domain type
  and extract(isodow from slot at time zone 'Australia/Melbourne') between 1 and 5 -- Mon–Fri
  and extract(hour from slot at time zone 'Australia/Melbourne') between 9 and 16 -- 9am–4pm start
  and exists(
    select
      1
    from
      public.user_roles ur
    where
      ur.role = 'traveller'::public.user_role
      and not private.is_person_busy(ur.user_id, slot)
      and ur.user_id is distinct from auth.uid())
order by
  slot;
$$;

revoke execute on function public.list_available_slots(timestamptz, timestamptz) from public;

-- TRAEDOFF OPPORTUNITY: why not just grant to public so everybody gets this public call?
grant execute on function public.list_available_slots(timestamptz, timestamptz) to anon, authenticated;

