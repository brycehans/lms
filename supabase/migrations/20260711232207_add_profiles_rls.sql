alter table profiles enable row level security;

-- allow travellers to be seen by any auth user on the Browse Travellers page
create policy authenticated_users_browse_travellers on profiles
  for select to authenticated
  using (profiles.deleted_at is null
    and exists (
      select
        1
      from
        user_roles ur
      where
        ur.user_id = profiles.id
        and ur.role = 'traveller'::user_role));

-- allow students to be seen only when the student is you...
create policy users_can_see_their_own_profiles on profiles
  for select to authenticated
  using (auth.uid() = profiles.id
    and profiles.deleted_at is null);

-- ...or they're on a booking you're party to
create policy users_can_see_booking_counterparties on profiles
  for select to authenticated
  using (profiles.deleted_at is null
    and exists (
      select
        1
      from
        bookings bk
      where
        auth.uid() in (bk.student_id, bk.time_traveller_id)
        and profiles.id in (bk.student_id, bk.time_traveller_id)
        and bk.deleted_at is null));

create policy self_update_profile on profiles
  for update to authenticated
  using (profiles.id = auth.uid())
  with check (profiles.id = auth.uid());

