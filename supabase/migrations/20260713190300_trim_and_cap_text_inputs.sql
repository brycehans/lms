-- Small consistency fixes at the write boundary (the RPCs).
--
-- (1) update_profile stored UNTRIMMED names. It rejected blank-after-trim but
--     then wrote the raw values, so "  Ada  " persisted with its padding —
--     whereas create_booking already normalises with trim() up front. Align on
--     the create_booking pattern: trim once, validate, store the trimmed value.
--
-- (2) No length caps anywhere. The route and both RPCs accepted an arbitrarily
--     large reason / name (a 10 MB reason would insert fine). One char_length
--     guard in each RPC — the trust boundary — bounds it without depending on
--     any client-side maxlength. Caps are generous (names 100, reason 2000):
--     comfortably above any real input, low enough to stop an abusive payload.

--------------------------------------------------------------------------------
-- update_profile: trim-then-store + a length cap.
create or replace function public.update_profile(p_first_name text, p_last_name text)
  returns void
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  -- normalise once, up front — same pattern as create_booking
  v_first_name text := trim(p_first_name);
  v_last_name text := trim(p_last_name);
begin
  if coalesce(v_first_name, '') = '' or coalesce(v_last_name, '') = '' then
    raise exception 'first and last name cannot be blank';
  end if;
  if char_length(v_first_name) > 100 or char_length(v_last_name) > 100 then
    raise exception 'first and last name must each be at most 100 characters';
  end if;
  update
    public.profiles
  set
    first_name = v_first_name, -- store the TRIMMED value, not the raw input
    last_name = v_last_name
  where
    id = auth.uid();
end;
$$;

--------------------------------------------------------------------------------
-- create_booking: add length caps on the client-supplied names + reason. Every
-- other line is carried forward unchanged from 20260713170000 (create or replace
-- rewrites the whole body, so the full definition is restated here).
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
  -- lock on bookings at this time, so nobody else can book it in a race condition
  -- yes we are protected by the same-role unique indexes (see `traveller_in_timeslot`)
  -- but don't have schema-level protection of some user who is both a student and a traveller
  -- having a booking created at the same time slot in race condition where each side has the
  -- user in the other party/role. this lock guards against that (and something like it is required
  -- in every place this race condition is possible. chosen as alternative over more complicated solutions like
  -- another table that tracks person on both sides per slot)
  perform
    pg_advisory_xact_lock(hashtextextended(p_starts_at::text, 0));
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
    -- option: could do `GET STACKED DIAGNOSTICS` to see which unique constraint was violated but this will do for now
  end;
end;
$$;
