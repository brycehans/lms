-- Harden the per-slot advisory lock that enforces "you can't be in two places at
-- once" for a person who is BOTH a student and a traveller.
--
-- Two related fixes, both to the same lock:
--
-- (1) reschedule_booking never took the lock. create_booking takes
--     pg_advisory_xact_lock on the slot precisely because the per-role unique
--     indexes (student_in_timeslot / traveller_in_timeslot) each only see ONE
--     column, so they cannot catch the same person landing on OPPOSITE sides of
--     the same slot (student on one booking, assigned traveller on another).
--     Because reschedule skipped the lock, a reschedule into slot S could run its
--     is_person_busy checks concurrently with a create at S and both commit —
--     re-opening exactly the race the lock exists to close. So reschedule now
--     takes the SAME lock on its target slot, before the busy-checks.
--
-- (2) The lock KEY was hashtextextended(p_starts_at::text, 0). timestamptz::text
--     renders in the session's TimeZone GUC, so two connections with different
--     TimeZone settings would hash the SAME instant to DIFFERENT keys, fail to
--     contend, and reopen the race. It happens to work today only because
--     Supabase defaults the database to UTC — correctness by configuration, not
--     by construction. extract(epoch ...) is absolute (TimeZone-independent), and
--     the is_bookable_start_time / top_of_hour domain guarantees a whole-second
--     value, so floor(...)::bigint is a stable, canonical lock key.
--
-- Both functions are recreated with `create or replace`, which preserves their
-- existing GRANTs (so no re-grant needed). Bodies are otherwise unchanged.

create or replace function public.create_booking(p_starts_at is_bookable_start_time, p_reason text, p_first_name text, p_last_name text)
  returns uuid -- the newly created booking's id
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  enrolled_university uuid;
  new_booking_id uuid;
  assigned_traveller uuid;
  -- normalise the client-supplied names once, up front
  v_first_name text := trim(p_first_name);
  v_last_name text := trim(p_last_name);
begin
  -- pure input validation first (cheap, no clock/lock/table access). the columns
  -- are NOT NULL and the route trims too, but the RPC is the trust boundary so it
  -- re-checks rather than relying on the caller.
  if coalesce(v_first_name, '') = '' or coalesce(v_last_name, '') = '' then
    raise exception 'first and last name are required';
  end if;
  if p_starts_at < now() then
    raise exception 'bookings cannot be created in the past';
  end if;
  -- lock on this slot so nobody else can book it in a race condition. keyed off
  -- the absolute epoch second (NOT ::text, which is TimeZone-dependent) so every
  -- session hashes a given instant to the same key. this is what guards the
  -- both-roles double-book that the per-role unique indexes can't see.
  perform
    pg_advisory_xact_lock(floor(extract(epoch from p_starts_at))::bigint);
  if private.is_person_busy(auth.uid(), p_starts_at) then
    raise exception 'student is already busy at % with another booking', p_starts_at;
  end if;
  select
    university_id
  into
    enrolled_university
  from
    public.student_enrolments
  where
    student_id = auth.uid();
  if enrolled_university is null then
    raise exception 'this student is not enrolled into any universities yet, so no booking can be made';
  end if;
  select
    (private.find_assignable_traveller(p_starts_at))
  into
    assigned_traveller;
  if assigned_traveller is null then
    raise exception 'cannot create booking: there are no time travellers available to book with';
  end if;
  begin
    insert into public.bookings(reason, student_id, time_traveller_id, starts_at, university_id, student_first_name, student_last_name)
      values (p_reason, auth.uid(), assigned_traveller, p_starts_at, enrolled_university, v_first_name, v_last_name)
    returning
      id
    into
      new_booking_id;
    return new_booking_id;
  exception
  -- make a nicer error message so we don't leak db internals about index constraints
    when unique_violation then
      raise exception 'that slot was just taken — please choose another time';
  end;
end;
$$;

create or replace function public.reschedule_booking(p_current_start timestamptz, p_new_start is_bookable_start_time)
  returns void
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  target_booking uuid;
begin
  if p_current_start = p_new_start then
    raise exception 'the booking is already at the time you are proposing to move it to: %. performing no action', p_current_start;
  end if;
  if p_new_start < now() then
    raise exception 'blocking attempt to reschedule this booking into the past';
  end if;
  -- take the SAME per-slot lock create_booking takes, on the DESTINATION slot,
  -- before the busy-checks below. without this, a reschedule into a slot and a
  -- create at that slot run their checks concurrently and can both commit,
  -- double-booking a person who is a student on one booking and the assigned
  -- traveller on the other (the per-role unique indexes can't catch that).
  perform
    pg_advisory_xact_lock(floor(extract(epoch from p_new_start))::bigint);
  select
    id
  into
    target_booking
  from
    public.bookings
  where
    public.bookings.starts_at = p_current_start
    and public.bookings.student_id = auth.uid()
    and public.bookings.deleted_at is null
    and public.bookings.cancelled_at is null
    and public.bookings.starts_at > now();
  if target_booking is null then
    raise exception 'no booking for this student is known for this time slot (or it has already passed, cancelled or deleted). reschedule denied!';
  end if;
  if private.is_person_busy(auth.uid(), p_new_start) then
    raise exception 'you are already busy with another booking on %', p_new_start;
  end if;
  if private.is_person_busy((
    select
      time_traveller_id
    from public.bookings
    where
      public.bookings.id = target_booking), p_new_start) then
    raise exception 'your assigned time traveller is already busy with another booking on %', p_new_start;
  end if;
  begin
    update
      public.bookings
    set
      starts_at = p_new_start
    where
      public.bookings.id = target_booking;
  exception
  -- make a nicer error message so we don't leak db internals about index constraints
    when unique_violation then
      raise exception 'that slot was just taken — please choose another time';
  end;
end;
$$;
