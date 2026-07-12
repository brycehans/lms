create function public.set_booking_completion(p_booking_id uuid, p_is_complete boolean)
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

revoke execute on function public.set_booking_completion(p_booking_id uuid, p_is_complete boolean) from public, anon;

grant execute on function public.set_booking_completion(p_booking_id uuid, p_is_complete boolean) to authenticated;

