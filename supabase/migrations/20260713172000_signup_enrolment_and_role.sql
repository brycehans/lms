-- Persist the student's university selection (and their student role) at signup.
--
-- handle_new_user (20260711015538) only ever wrote the profiles row, so a
-- fresh signup landed with NO student_enrolments row (create_booking then raises
-- "this student is not enrolled…") and NO user_roles row (empty /me). The signup
-- route already validates the chosen university and passes it into
-- raw_user_meta_data.university_id — the trigger just discarded it.
--
-- The trigger also fires on seed.sql's auth.users inserts, which include
-- travellers and admins. Those seed rows carry ONLY first_name/last_name in their
-- metadata — no university_id — whereas every real signup carries university_id.
-- So we gate the two new inserts on its presence: seed behaviour is unchanged
-- (its own explicit user_roles / student_enrolments inserts still own those rows),
-- and only genuine self-signups get a role + enrolment.
--
-- Security note: the role is HARDCODED to 'student' — the trigger never reads a
-- role out of client-supplied metadata, so signup cannot self-promote (upholds
-- the "roles live outside profiles precisely so nobody can self-elevate"
-- invariant). university_id is tenancy data, not a privilege, and was validated
-- by the signup route before it reached the metadata.
create or replace function private.handle_new_user ()
  returns trigger
  security definer
  set search_path = ''
  as $$
begin
  insert into public.profiles (id, first_name, last_name)
    values (new.id, new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'last_name');

  -- university_id present == a real student self-signup (seeded users omit it).
  if new.raw_user_meta_data ? 'university_id' then
    insert into public.user_roles (user_id, role)
      values (new.id, 'student')
    on conflict do nothing;

    insert into public.student_enrolments (student_id, university_id)
      values (new.id, (new.raw_user_meta_data ->> 'university_id')::uuid)
    on conflict do nothing;
  end if;

  return NEW;
end;
$$
language plpgsql;
