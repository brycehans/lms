alter table bookings enable row level security;

create policy user_booking_ownership_visibility_wall on bookings
  for select to authenticated
  using ((student_id = auth.uid ()
    or time_traveller_id = auth.uid ())
    and deleted_at is null);

