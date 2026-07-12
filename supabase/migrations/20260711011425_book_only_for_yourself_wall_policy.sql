create policy book_only_for_yourself_wall_policy on bookings
  for insert to authenticated
  with check (auth.uid () = student_id);

