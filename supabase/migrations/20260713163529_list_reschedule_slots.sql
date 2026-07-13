-- slots we can offer when RESCHEDULING an existing booking.
--
-- why not reuse list_available_slots? that one answers the NEW-booking question:
-- "is there >= 1 traveller (other than me) free here, so create_booking can
-- assign someone?". reschedule is different: it deliberately keeps the SAME
-- assigned traveller (a student must not be able to swap travellers via a move),
-- and it also cares about the student's own calendar. so a slot is offerable for
-- THIS booking iff its predicate matches reschedule_booking's checks exactly:
--   * the student (auth.uid()) is free, and
--   * this booking's assigned traveller is free.
-- listing with the any-traveller predicate is what let the dropdown surface slots
-- that reschedule_booking then rejected.
create function public.list_reschedule_slots(p_current_start timestamptz, p_from timestamptz, p_to timestamptz)
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
  -- equiv to `is_bookable_start_time` domain type
  and extract(isodow from slot at time zone 'Australia/Melbourne') between 1 and 5 -- Mon–Fri
  and extract(hour from slot at time zone 'Australia/Melbourne') between 9 and 16 -- 9am–4pm start
  -- the two checks reschedule_booking enforces at commit time
  and not private.is_person_busy(auth.uid(), slot)
  and not private.is_person_busy(target.time_traveller_id, slot)
order by
  slot;
$$;

revoke execute on function public.list_reschedule_slots(timestamptz, timestamptz, timestamptz) from public, anon;

-- rescheduling is a student-only action, so (unlike list_available_slots) this is
-- not granted to anon.
grant execute on function public.list_reschedule_slots(timestamptz, timestamptz, timestamptz) to authenticated;
