-- Harden the definer slot/assignment RPCs. They bypass RLS (SECURITY DEFINER),
-- so any guard RLS would give a read has to be re-encoded inside the function.
-- Two such guards were missing.
--
-- (A) ABUSE VECTOR — unbounded windows. list_available_slots is granted to anon;
--     neither it nor list_reschedule_slots bounded [p_from, p_to). generate_series
--     materialises the WHOLE range at 1-hour steps BEFORE the slot > now() filter
--     prunes anything, and each surviving slot runs is_person_busy per traveller.
--     p_from = 1970, p_to = 3000 → a multi-million-row series per unauthenticated
--     request. Fix: clamp the SERIES BOUNDS themselves (not just the WHERE, which
--     runs too late) — floor the start at now(), cap the span at 60 days. The
--     client only ever asks for 28 (BOOKING_WINDOW_DAYS), so nothing legitimate
--     changes. An oversize or garbage window now yields a short or empty series
--     instead of a DoS lever. The existing slot >= p_from / slot < p_to / slot >
--     now() predicates stay as belt-and-suspenders around the clamp.
--
-- (B) MODEL VIOLATION — soft-deleted travellers stayed assignable. Both the
--     roster exists() check here and find_assignable_traveller selected from
--     user_roles alone. RLS hides a soft-deleted traveller from the public
--     roster, but these definer functions don't — so a deleted traveller still
--     showed a slot as open AND could be assigned to a brand-new booking. Fix:
--     one `join profiles … deleted_at is null` in each, restoring the
--     listing/assignment parity (a slot is only offered if it can actually be
--     filled by a live traveller).

--------------------------------------------------------------------------------
-- (B) assignment: never hand new work to a soft-deleted traveller.
create or replace function private.find_assignable_traveller(p_booking_start_time timestamptz)
  returns uuid
  security definer
  set search_path = ''
  language plpgsql
  as $$
begin
  return(
    select
      user_roles.user_id
    from
      public.user_roles
      join public.profiles p on p.id = user_roles.user_id
        and p.deleted_at is null -- soft-deleted travellers take no new bookings
    where
      user_roles.role = 'traveller'::public.user_role
      and not private.is_person_busy(user_roles.user_id, p_booking_start_time)
      -- and don't assign a session to meet with yourself!
      and not auth.uid() = user_roles.user_id
    order by
      random()
    limit 1);
end;
$$;

--------------------------------------------------------------------------------
-- (A) clamp + (B) live-traveller check on the public roster.
create or replace function public.list_available_slots(p_from timestamptz, p_to timestamptz)
  returns setof timestamptz
  -- one row per bookable slot in [p_from, p_to) that has >= 1 free LIVE traveller.
  security definer
  set search_path = ''
  language sql
  as $$
  select
    slot
  from
    generate_series(
      -- floor the aligned start at now(): never build the past half of the series
      timezone(private.business_tz(), date_trunc('hour', timezone(private.business_tz(), greatest(p_from, now())))),
      -- cap the span at 60 days so a huge p_to can't force a giant series
      least(p_to, p_from + interval '60 days'),
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
      join public.profiles p on p.id = ur.user_id
        and p.deleted_at is null -- a soft-deleted traveller can't fill the slot
    where
      ur.role = 'traveller'::public.user_role
      and not private.is_person_busy(ur.user_id, slot)
      and ur.user_id is distinct from auth.uid())
order by
  slot;
$$;

--------------------------------------------------------------------------------
-- (A) clamp only. Reschedule keeps the already-assigned traveller (it never
-- reassigns), so the soft-deleted-traveller check in (B) does not apply here.
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
      timezone(private.business_tz(), date_trunc('hour', timezone(private.business_tz(), greatest(p_from, now())))),
      least(p_to, p_from + interval '60 days'),
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
