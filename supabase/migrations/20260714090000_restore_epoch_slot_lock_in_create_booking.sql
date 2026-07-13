-- Restore the canonical epoch-based per-slot advisory lock in create_booking.
--
-- REGRESSION being fixed:
--   20260713180000_harden_slot_advisory_lock.sql switched BOTH create_booking and
--   reschedule_booking onto an absolute, TimeZone-independent lock key:
--       pg_advisory_xact_lock(floor(extract(epoch from <slot>))::bigint)
--   But 20260713190300_trim_and_cap_text_inputs.sql later re-stated the whole
--   create_booking body (to add char_length caps) and carried forward the OLD
--   lock line from the pre-hardening implementation:
--       pg_advisory_xact_lock(hashtextextended(p_starts_at::text, 0))
--   reschedule_booking kept the epoch key. So the two write paths now hash the
--   same instant to DIFFERENT bigint keys and never contend — re-opening exactly
--   the both-roles double-book race the lock exists to close (a person who is the
--   student on one booking and the assigned traveller on another at the same slot;
--   the per-role unique indexes student_in_timeslot / traveller_in_timeslot each
--   see only one column and cannot catch it).
--
-- Why the epoch key is the correct one to keep:
--   (1) Cross-path contention — both create and reschedule must key off the same
--       value or they never block each other. reschedule already uses epoch.
--   (2) TimeZone-independence — timestamptz::text renders in the session's TimeZone
--       GUC, so two sessions with different TimeZone settings hash the same instant
--       to different keys (works today only because Supabase defaults to UTC:
--       correctness by configuration, not construction). extract(epoch ...) is
--       absolute, and the is_bookable_start_time / top_of_hour domain guarantees a
--       whole-second value, so floor(...)::bigint is exact and canonical.
--
-- Every other line is carried forward UNCHANGED from 20260713190300 (create or
-- replace rewrites the whole body, so the full definition is restated here — the
-- name/reason length caps and past-check must survive). Only the lock line changes.
-- create or replace preserves existing GRANTs, so no re-grant is needed.

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
  if char_length(v_first_name) > 100 or char_length(v_last_name) > 100 then
    raise exception 'first and last name must each be at most 100 characters';
  end if;
  if coalesce(char_length(p_reason), 0) > 2000 then
    raise exception 'reason must be at most 2000 characters';
  end if;
  if p_starts_at < now() then
    raise exception 'bookings cannot be created in the past';
  end if;
  -- lock on this slot so nobody else can book it in a race condition. keyed off
  -- the absolute epoch second (NOT ::text, which is TimeZone-dependent) so every
  -- session hashes a given instant to the same key — the SAME key reschedule_booking
  -- takes. this is what guards the both-roles double-book that the per-role unique
  -- indexes can't see.
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
