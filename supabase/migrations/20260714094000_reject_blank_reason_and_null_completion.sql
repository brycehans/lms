-- Close two route-only guards that had no twin at the DB trust boundary.
--
-- The route handlers are NOT the write boundary — the anon key is public and the
-- RPCs are granted to `authenticated`, so a logged-in caller can hit
-- POST /rest/v1/rpc/<fn> directly and skip app/api/**/route.ts entirely. Every
-- invariant therefore has to live in the RPC. An audit of each route against its
-- RPC found two guards that existed only in the route:
--
-- (1) create_booking — blank reason. The route rejects a blank reason
--     (`!reason.trim()`), but the RPC only CAPPED its length; `reason` is
--     `text not null`, and '' satisfies NOT NULL, so a direct call with
--     p_reason: '' inserted a booking with an empty reason. Add a non-blank
--     guard and, while we're at it, normalise reason with trim() up front and
--     store the trimmed value — matching the existing name handling (the route
--     already trims; the RPC should own it, not depend on the caller).
--
-- (2) set_booking_completion — null p_is_complete. The route forces a real
--     boolean, but a direct call passing SQL NULL fell through `if
--     p_is_complete is true` to the else branch and silently un-completed the
--     booking. Reject NULL so the argument is always an explicit true/false.
--
-- Both bodies are restated in full because `create or replace` rewrites the
-- whole definition; only the noted lines are new. Every other line is carried
-- forward unchanged (create_booking from 20260714090000, set_booking_completion
-- from 20260712130454). `create or replace` preserves existing GRANTs, so no
-- re-grant is needed for either.

--------------------------------------------------------------------------------
-- (1) create_booking: reject a blank reason + trim-then-store it.
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
  -- normalise the client-supplied text once, up front
  v_first_name text := trim(p_first_name);
  v_last_name text := trim(p_last_name);
  v_reason text := trim(p_reason);
begin
  -- pure input validation first (cheap, no clock/lock/table access). the columns
  -- are NOT NULL and the route trims too, but the RPC is the trust boundary so it
  -- re-checks rather than relying on the caller.
  if coalesce(v_first_name, '') = '' or coalesce(v_last_name, '') = '' then
    raise exception 'first and last name are required';
  end if;
  if coalesce(v_reason, '') = '' then
    raise exception 'a reason is required';
  end if;
  if char_length(v_first_name) > 100 or char_length(v_last_name) > 100 then
    raise exception 'first and last name must each be at most 100 characters';
  end if;
  if char_length(v_reason) > 2000 then
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
      values (v_reason, auth.uid(), assigned_traveller, p_starts_at, enrolled_university, v_first_name, v_last_name)
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

--------------------------------------------------------------------------------
-- (2) set_booking_completion: reject a NULL flag (route sends a real boolean;
-- a direct call must too). Everything else carried forward from 20260712130454.
create or replace function public.set_booking_completion(p_booking_id uuid, p_is_complete boolean)
  returns void
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  existing_cancelled_at timestamptz;
  existing_completed_at timestamptz;
  matched_booking_id uuid;
  booking_starts_at timestamptz;
begin
  -- explicit intent required: NULL is neither "complete" nor "not complete", and
  -- would otherwise fall through to the else branch and silently un-complete.
  if p_is_complete is null then
    raise exception 'completion status must be true or false, not null';
  end if;
  select
    id,
    completed_at,
    cancelled_at,
    starts_at
  into
    matched_booking_id,
    existing_completed_at,
    existing_cancelled_at,
    booking_starts_at
  from
    public.bookings
  where
    public.bookings.id = p_booking_id
    and public.bookings.student_id = auth.uid()
    and public.bookings.deleted_at is null;
  if matched_booking_id is null then
    raise exception 'no booking found';
  end if;
  if existing_cancelled_at is not null then
    raise exception 'you cannot change the completion status of a cancelled booking';
  end if;
  if booking_starts_at > now() then
    raise exception 'you cannot change the completion status of an upcoming booking, only those that have passed';
  end if;
  -- idempotent (modulo timestamp): mark it complete as many times as you want and vice versa
  if p_is_complete is true then
    update
      public.bookings
    set
      completed_at = now()
    where
      public.bookings.id = p_booking_id;
  else
    update
      public.bookings
    set
      completed_at = null
    where
      public.bookings.id = p_booking_id;
  end if;
end;
$$;
