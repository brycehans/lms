-- Make the runtime slot logic timezone-safe and give the business timezone a
-- single home.
--
-- Background: 'Australia/Melbourne' was hardcoded in several places, and the
-- "top of the hour" test in private.is_bookable_slot used a tz-naive
-- date_trunc('hour', slot). That only agrees with the tz-aware 9am–4pm / Mon–Fri
-- tests because Melbourne is a WHOLE-hour UTC offset (+10/+11): top-of-UTC-hour
-- and top-of-Melbourne-hour coincide. Point the business tz at a half-hour zone
-- (e.g. Australia/Adelaide, +9:30) and the naive test would silently reject the
-- very slots the other two tests accept. Likewise list_available_slots /
-- list_reschedule_slots aligned their generate_series lower bound to a UTC hour,
-- which for a half-hour zone would generate candidates that can never be a local
-- top-of-hour, yielding an empty list.
--
-- Fix: evaluate every slot rule in the business timezone explicitly, sourced from
-- one function, private.business_tz(). All changes below are behavioural NO-OPS
-- for Melbourne (whole-hour offset) — they only stop the logic from silently
-- breaking if the business tz ever moves to a fractional-hour offset.
--
-- SCOPE / remaining assumption: the is_bookable_start_time DOMAIN (and its
-- parents business_hours / top_of_hour) still embed the tz literal and a tz-naive
-- top_of_hour check. Those are the input-validation cast type on create_booking /
-- reschedule_booking, and redefining an applied domain cascades to every column
-- and function signature that references it (see 20260713163940). So the domain
-- stays as the ONE documented spot that still assumes a whole-hour business tz;
-- moving to a half-hour zone would need a deliberate domain migration. Everything
-- that runs at query time now goes through private.business_tz().

--------------------------------------------------------------------------------
-- Single source of truth for the business timezone used by all runtime slot
-- logic. IMMUTABLE: it returns a constant. No REST endpoint (private schema +
-- revoke), usable inside the definer RPCs and the RLS-free helper below.
create function private.business_tz()
  returns text
  immutable
  set search_path = ''
  language sql
  as $$
  select 'Australia/Melbourne'::text;
$$;

revoke execute on function private.business_tz() from public;

--------------------------------------------------------------------------------
-- Re-express the bookable-slot rule entirely in the business timezone. timezone(
-- zone, timestamptz) returns the local wall-clock timestamp; comparing/extracting
-- on THAT makes "top of the hour", the weekday, and the hour-of-day all agree for
-- any UTC offset, not just whole-hour ones. Still STABLE (tz rules can change),
-- still no table access.
create or replace function private.is_bookable_slot(p_slot timestamptz)
  returns boolean
  set search_path = ''
  language sql
  stable
  as $$
  select
    -- top of a business-tz hour (tz-explicit: correct for fractional offsets too)
    date_trunc('hour', timezone(private.business_tz(), p_slot))
      = timezone(private.business_tz(), p_slot)
    and extract(isodow from timezone(private.business_tz(), p_slot)) between 1 and 5 -- Mon–Fri
    and extract(hour from timezone(private.business_tz(), p_slot)) between 9 and 16; -- 9am–4pm start
$$;

--------------------------------------------------------------------------------
-- Align the candidate series to the top of a BUSINESS-tz hour (was UTC-aligned).
-- The round-trip timezone(tz, date_trunc('hour', timezone(tz, p_from))) snaps
-- p_from down to the local top-of-hour instant; stepping by 1 hour then lands on
-- local top-of-hour instants. is_bookable_slot still does the real filtering.
-- Both functions are otherwise unchanged; create or replace preserves grants.
create or replace function public.list_available_slots(p_from timestamptz, p_to timestamptz)
  returns setof timestamptz
  -- one row per bookable slot in [p_from, p_to) that has >= 1 free traveller.
  security definer
  set search_path = ''
  language sql
  as $$
  select
    slot
  from
    generate_series(
      timezone(private.business_tz(), date_trunc('hour', timezone(private.business_tz(), p_from))),
      p_to,
      interval '1 hour') as slot
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
    generate_series(
      timezone(private.business_tz(), date_trunc('hour', timezone(private.business_tz(), p_from))),
      p_to,
      interval '1 hour') as slot
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
