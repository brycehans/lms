-- idempotently cancel a booking. fine to do it again and again, only the
-- `cancelled_at` timestamp will change
-- TRADEOFF OPPORTUNITY: what if it's important to know when the first time the cancellation happened?
create function public.cancel_booking(p_starts_at timestamptz)
  returns void
  -- use escalated sec priveliges because the constraint is that
  -- we don't want anyone to be able to change the columns of
  -- bookings (postgrest would expose them all to whomever was allowed in a policy)
  -- but cancelled_at is the only column that may be changed for cancelling
  -- (there's also rescheduling that only changes starts_at and keep all other columns
  -- like the participants frozen to their initial values)
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  target_booking uuid;
begin
  select
    id
  into
    target_booking
  from
    public.bookings
  where
    public.bookings.starts_at = p_starts_at
    and public.bookings.student_id = auth.uid()
    and public.bookings.deleted_at is null
    and public.bookings.starts_at > now();
  if target_booking is null then
    raise exception 'no booking for this student is known for this time slot (or it has already passed). cancelling nothing!';
  end if;
  update
    public.bookings
  set
    cancelled_at = now()
  where
    public.bookings.id = target_booking;
end;
$$;

revoke execute on function public.cancel_booking(timestamptz) from public;

grant execute on function public.cancel_booking(timestamptz) to authenticated;

