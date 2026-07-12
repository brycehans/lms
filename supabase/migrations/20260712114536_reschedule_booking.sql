-- a student may reschedule a booking. this function will change its start time
-- important to ensure security against changing the assigned time_traveller
-- eg "I want a different person I don't like who I got assigned"
-- and only have the start time change.
-- don't reschedule cancelled nor soft-deleted bookings
-- ensure the availability checks that passed on first booking still pass in the new slot
create function public.reschedule_booking(p_current_start timestamptz, p_new_start is_bookable_start_time)
  returns void
  -- use escalated sec priveliges because the constraint is that
  -- we don't want anyone to be able to change the columns of
  -- bookings (postgrest would expose them all to whomever was allowed in a policy)
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
    -- option: could do `GET STACKED DIAGNOSTICS` to see which unique constraint was violated but this will do for now
  end;
end;

$$;

revoke execute on function public.reschedule_booking(timestamptz, is_bookable_start_time) from public, anon;

grant execute on function public.reschedule_booking(timestamptz, is_bookable_start_time) to authenticated;

