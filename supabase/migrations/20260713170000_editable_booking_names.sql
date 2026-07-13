-- Make the student-name snapshot CLIENT-SETTABLE at booking time.
--
-- Originally (20260712052121) create_booking derived student_first_name /
-- student_last_name server-side from the caller's profile — a deliberate
-- "never trust a client-supplied value" stance. That rule is right for identity
-- and provenance (student_id is auth.uid(); the traveller is server-assigned so
-- a student can't hand-pick one), but the snapshot NAME is neither: it's
-- descriptive display data frozen onto the row. Letting a student set the name
-- printed on their OWN booking grants no privilege they lack — they can already
-- rename via update_profile — and per-booking naming is a real feature (book
-- under a preferred/different name without rewriting the profile). So the name
-- becomes two params; student_id and time_traveller_id stay server-derived.
--
-- Adding params is a NEW signature, so we drop the 2-arg function first (a
-- `create or replace` would leave both overloads and make the PostgREST call
-- ambiguous) and re-grant against the new one — grants are per-signature.
drop function public.create_booking(is_bookable_start_time, text);

create function public.create_booking(p_starts_at is_bookable_start_time, p_reason text, p_first_name text, p_last_name text)
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

-- re-seal the new overload: Supabase's ALTER DEFAULT PRIVILEGES auto-grants
-- EXECUTE to anon + authenticated + service_role on every new public function,
-- so revoke the NAMED anon grant (not just PUBLIC) and re-grant authenticated.
revoke execute on function public.create_booking(is_bookable_start_time, text, text, text) from public, anon;

grant execute on function public.create_booking(is_bookable_start_time, text, text, text) to authenticated;
