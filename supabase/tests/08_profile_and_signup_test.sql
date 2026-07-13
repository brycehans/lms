-- ============================================================================
-- update_profile RPC, the handle_new_user signup trigger, and the frozen-name
-- invariant that ties them together.
--
--  * update_profile: trims, rejects blank/over-long names, and CANNOT change
--    anything but the caller's own name (roles live in another table by design).
--  * frozen snapshot: renaming a profile must NOT rewrite the name already
--    frozen onto an existing booking (history is immutable).
--  * handle_new_user: inserting an auth.users row creates the profile, and —
--    when signup metadata carries a valid university_id — the student role and
--    enrolment too; it rejects blank/over-long names and unknown universities.
-- ============================================================================
begin;
select plan(14);

-- Fixtures: SA already exists with a booking whose name snapshot is "Old Name".
insert into public.universities (id, name)
  values ('f5000000-0000-0000-0000-0000000000f5', 'Profile Test University');

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('f5000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','prof.sa@example.com','{"provider":"email"}','{"first_name":"Old","last_name":"Name"}', now(), now(), now()),
  ('f5000000-0000-0000-0000-0000000000c5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','prof.tt@example.com','{"provider":"email"}','{"first_name":"Ty","last_name":"Traveller"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('f5000000-0000-0000-0000-0000000000a5','student'::public.user_role),
  ('f5000000-0000-0000-0000-0000000000c5','traveller'::public.user_role);

insert into public.bookings (student_id, time_traveller_id, reason, starts_at, university_id, student_first_name, student_last_name)
values ('f5000000-0000-0000-0000-0000000000a5','f5000000-0000-0000-0000-0000000000c5','snapshot test',
        (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '8 weeks' + interval '10 hours')::timestamp at time zone 'Australia/Melbourne',
        'f5000000-0000-0000-0000-0000000000f5','Old','Name');

-- === update_profile (as the caller) =========================================
set local role authenticated;
set local request.jwt.claims to '{"sub":"f5000000-0000-0000-0000-0000000000a5","role":"authenticated"}';

-- Rename, with padding that must be trimmed off before storing.
select public.update_profile('  Renamed  ', '  Person  ');

select is(
  (select first_name from public.profiles where id = 'f5000000-0000-0000-0000-0000000000a5'),
  'Renamed', 'update_profile stores the trimmed first name');

select is(
  (select last_name from public.profiles where id = 'f5000000-0000-0000-0000-0000000000a5'),
  'Person', 'update_profile stores the trimmed last name');

-- FROZEN SNAPSHOT: the rename must not touch the booking's captured name.
select is(
  (select student_first_name || ' ' || student_last_name from public.bookings
     where student_id = 'f5000000-0000-0000-0000-0000000000a5'),
  'Old Name', 'renaming the profile leaves the booking''s frozen name snapshot intact');

-- Blank / over-long names are refused.
select throws_like(
  $$ select public.update_profile('   ', 'Person') $$,
  '%cannot be blank%', 'update_profile rejects a blank first name');

select throws_like(
  $$ select public.update_profile(repeat('x', 101), 'Person') $$,
  '%100 characters%', 'update_profile rejects a name over 100 characters');

-- update_profile has no authority over roles: the caller still holds exactly the
-- one role they started with (the guarantee that keeps profile edits from being a
-- privilege-escalation path).
select is(
  (select count(*)::int from public.user_roles where user_id = 'f5000000-0000-0000-0000-0000000000a5'),
  1, 'a profile rename does not add or change the caller''s roles');

reset role;

-- === handle_new_user signup trigger (as the owner, i.e. GoTrue) =============
-- Full self-signup: names + a valid university_id in metadata.
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values ('f5000000-0000-0000-0000-00000000e001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','signup.full@example.com','{"provider":"email"}',
        jsonb_build_object('first_name','Fresh','last_name','Signup','university_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
        now(), now(), now());

select is(
  (select first_name from public.profiles where id = 'f5000000-0000-0000-0000-00000000e001'),
  'Fresh', 'signup creates the profile row from metadata');

select is(
  (select count(*)::int from public.user_roles
     where user_id = 'f5000000-0000-0000-0000-00000000e001' and role = 'student'),
  1, 'signup with a university grants the student role');

select is(
  (select university_id from public.student_enrolments where student_id = 'f5000000-0000-0000-0000-00000000e001'),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'signup with a university creates the enrolment');

-- Seeded-style signup: no university_id => profile only, no role/enrolment.
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values ('f5000000-0000-0000-0000-00000000e002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','signup.nouni@example.com','{"provider":"email"}',
        '{"first_name":"Staff","last_name":"Member"}', now(), now(), now());

select is(
  (select count(*)::int from public.profiles where id = 'f5000000-0000-0000-0000-00000000e002'),
  1, 'signup with no university still creates the profile');

select is(
  (select count(*)::int from public.user_roles where user_id = 'f5000000-0000-0000-0000-00000000e002')
  + (select count(*)::int from public.student_enrolments where student_id = 'f5000000-0000-0000-0000-00000000e002'),
  0, 'signup with no university grants no role and no enrolment');

-- Rejections: blank name, over-long name, unknown university.
select throws_like(
  $$ insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
     values ('f5000000-0000-0000-0000-00000000e003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','signup.blank@example.com',
             '{"first_name":"","last_name":"Nameless"}', now(), now()) $$,
  '%non-empty%', 'signup with a blank name is rejected by the trigger');

select throws_like(
  $$ insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
     values ('f5000000-0000-0000-0000-00000000e004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','signup.long@example.com',
             jsonb_build_object('first_name', repeat('x',101), 'last_name','Toolong'), now(), now()) $$,
  '%100 characters%', 'signup with an over-long name is rejected by the trigger');

select throws_like(
  $$ insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
     values ('f5000000-0000-0000-0000-00000000e005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','signup.baduni@example.com',
             jsonb_build_object('first_name','Ghost','last_name','Uni','university_id','00000000-0000-0000-0000-0000000000ff'), now(), now()) $$,
  '%unknown or deleted university%', 'signup referencing an unknown university is rejected');

select * from finish();
rollback;
