create function private.is_person_busy(p_time_traveller_id uuid, p_time_slot_begin timestamptz)
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
(bookings.time_traveller_id = p_time_traveller_id
          or bookings.student_id = p_time_traveller_id)
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
  set search_path = ''
  language plpgsql
  as $$
declare
  enrolled_university uuid;
  new_booking_id uuid;
begin
  select
    university_id
  into
    enrolled_university
  from
    public.student_enrolments
  where
    student_id = auth.uid();
  insert into public.bookings(reason, student_id, time_traveller_id, starts_at, university_id)
    values (p_reason, auth.uid(), private.find_assignable_traveller(p_starts_at), p_starts_at, enrolled_university)
  returning
    id
  into
    new_booking_id;
  return new_booking_id;
end;
$$;

