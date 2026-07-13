-- DRY the "is this a bookable start time?" rule that list_available_slots and
-- list_reschedule_slots each spelled out inline.
--
-- note this is NOT the same mechanism as the is_bookable_start_time DOMAIN. the
-- domain REJECTS bad inputs at cast time (function args, table columns); these
-- list functions GENERATE candidate slots and need a boolean FILTER over a
-- generate_series. same rule, two jobs — so this helper mirrors the domain's
-- predicate rather than replacing it. (rewriting the domain to call this would
-- mean dropping it, which cascades to every column and function signature that
-- references is_bookable_start_time — not worth it.)
--
-- pure computation: no table access, so no security definer needed. marked
-- stable because `at time zone <name>` is stable (tz rules can change), not
-- immutable.
create function private.is_bookable_slot(p_slot timestamptz)
  returns boolean
  set search_path = ''
  language sql
  stable
  as $$
  select
    date_trunc('hour', p_slot) = p_slot -- top of the hour
    and extract(isodow from p_slot at time zone 'Australia/Melbourne') between 1 and 5 -- Mon–Fri
    and extract(hour from p_slot at time zone 'Australia/Melbourne') between 9 and 16; -- 9am–4pm start
$$;

-- match the private-schema convention: usable by definer RPCs (which run as the
-- owner), but no direct REST-reachable grant.
revoke execute on function private.is_bookable_slot(timestamptz) from public;

-- create or replace preserves each function's existing grants.
create or replace function public.list_available_slots(p_from timestamptz, p_to timestamptz)
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
  and private.is_bookable_slot(slot)
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

create or replace function public.list_reschedule_slots(p_current_start timestamptz, p_from timestamptz, p_to timestamptz)
  returns setof timestamptz
  security definer
  set search_path = ''
  language sql
  as $$
  -- resolve the booking the SAME way reschedule_booking does, so the two agree on
  -- which booking (and therefore which traveller) we're talking about. no match
  -- (wrong student / cancelled / deleted / already past) => empty CTE => the
  -- cross join below yields no rows => empty slot list.
  with target as (
    select
      b.time_traveller_id
    from
      public.bookings b
    where
      b.starts_at = p_current_start
      and b.student_id = auth.uid()
      and b.deleted_at is null
      and b.cancelled_at is null
      and b.starts_at > now())
  select
    slot
  from
    target,
    generate_series(date_trunc('hour', p_from, 'UTC'), -- align lower bound to the hour (tz-independent)
      p_to, interval '1 hour') as slot
where
  slot >= p_from
  and slot < p_to -- half-open window [p_from, p_to)
  and slot > now() -- don't offer the past
  and slot <> p_current_start -- a same-time move is a no-op reschedule_booking rejects
  and private.is_bookable_slot(slot)
  -- the two checks reschedule_booking enforces at commit time
  and not private.is_person_busy(auth.uid(), slot)
  and not private.is_person_busy(target.time_traveller_id, slot)
order by
  slot;
$$;
