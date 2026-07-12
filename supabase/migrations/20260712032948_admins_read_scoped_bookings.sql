-- superadmins can read all bookings,
-- admins that administrate a university can see all bookings for that university
create policy admins_read_scoped_bookings on bookings
  for select to authenticated
  using (university_id in (
    select
      public.admin_university_ids ())
      and (bookings.deleted_at is null
      or public.is_current_user_superadmin ()))
