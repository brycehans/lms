create function private.is_person_busy(p_user_id uuid, p_time_slot_begin timestamptz)
  returns boolean
  security definer
  set search_path = ''
  language sql
  as $$
  select
    exists(
      select
        1
      from
        public.bookings
      where
        -- time traveller might have a booking as a student at the time, or already booked for that time as the traveller
(bookings.time_traveller_id = p_user_id
          or bookings.student_id = p_user_id)
        and bookings.starts_at = p_time_slot_begin
        and bookings.cancelled_at is null
        and bookings.deleted_at is null);
$$;

-- find user whose role is time_traveller who has no existing (un-cancelled && undeleted) bookings
-- at the requested time. to avoid over-burdening one single traveller, randomly select from the
-- available travellers.
-- exclude self
create function private.find_assignable_traveller(p_booking_start_time timestamptz)
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

-- revoke the public grant so no other role can call them directly even though
-- `authenticated` holds usage on the `private` schema.
revoke execute on function private.is_person_busy(uuid, timestamptz) from public;

revoke execute on function private.find_assignable_traveller(timestamptz) from public;

create domain top_of_hour as timestamptz check (date_trunc('hour', value) = value);

-- WARNING! hardcoded timezone for demo, real system would read this in
-- bookings can be started from 9am to 4pm (last slot of the day so it finishes at 5pm EOD)
create domain business_hours as top_of_hour check (extract(HOUR from VALUE AT TIME ZONE 'Australia/Melbourne') between 9 and 16);

-- bookings can only be made for monday to friday business days
create domain is_bookable_start_time as business_hours check (extract(ISODOW from VALUE at time zone 'Australia/Melbourne') between 1 and 5);

create function public.create_booking(p_starts_at is_bookable_start_time, p_reason text)
  returns uuid -- the newly created booking's id
  security definer
  set timezone = 'Australia/Melbourne'
  set search_path = ''
  language plpgsql
  as $$
declare
  enrolled_university uuid;
  new_booking_id uuid;
  assigned_traveller uuid;
begin
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
    insert into public.bookings(reason, student_id, time_traveller_id, starts_at, university_id)
      values (p_reason, auth.uid(), assigned_traveller, p_starts_at, enrolled_university)
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

