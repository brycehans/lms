-- ============================================================================
-- cancel_booking — a student cancels one of their OWN, still-upcoming bookings.
--
-- It re-derives the target from auth.uid() + slot, and only ever touches a row
-- that is the caller's, live (not already cancelled/deleted), and in the future.
-- Bookings are inserted directly (as owner) so we control their exact state.
-- ============================================================================
begin;
select plan(6);

-- Fixtures --------------------------------------------------------------------
insert into public.universities (id, name)
  values ('f2000000-0000-0000-0000-0000000000f2', 'Cancel Test University');

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('f2000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cancel.sa@example.com','{"provider":"email"}','{"first_name":"Sam","last_name":"Owner"}', now(), now(), now()),
  ('f2000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cancel.sb@example.com','{"provider":"email"}','{"first_name":"Bob","last_name":"Bystander"}', now(), now(), now()),
  ('f2000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cancel.tt@example.com','{"provider":"email"}','{"first_name":"Tia","last_name":"Traveller"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('f2000000-0000-0000-0000-0000000000a2','student'::public.user_role),
  ('f2000000-0000-0000-0000-0000000000b2','student'::public.user_role),
  ('f2000000-0000-0000-0000-0000000000c2','traveller'::public.user_role);

select set_config('test.slot_a',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '8 weeks' + interval '10 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);
select set_config('test.slot_b',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '8 weeks' + interval '1 day 11 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);
select set_config('test.slot_past',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '2 weeks' + interval '10 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);

-- slot_a: SA's live future booking (will be cancelled)
-- slot_b: SA's live future booking (a bystander will fail to cancel it)
-- slot_past: SA's past booking (cannot be cancelled — already happened)
insert into public.bookings (student_id, time_traveller_id, reason, starts_at, university_id, student_first_name, student_last_name)
values
  ('f2000000-0000-0000-0000-0000000000a2','f2000000-0000-0000-0000-0000000000c2','a', current_setting('test.slot_a')::timestamptz,    'f2000000-0000-0000-0000-0000000000f2','Sam','Owner'),
  ('f2000000-0000-0000-0000-0000000000a2','f2000000-0000-0000-0000-0000000000c2','b', current_setting('test.slot_b')::timestamptz,    'f2000000-0000-0000-0000-0000000000f2','Sam','Owner'),
  ('f2000000-0000-0000-0000-0000000000a2','f2000000-0000-0000-0000-0000000000c2','p', current_setting('test.slot_past')::timestamptz, 'f2000000-0000-0000-0000-0000000000f2','Sam','Owner');

-- Act as the owner ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"f2000000-0000-0000-0000-0000000000a2","role":"authenticated"}';

-- Happy path (executed as setup; effect asserted next).
select public.cancel_booking(current_setting('test.slot_a')::timestamptz);

select ok(
  (select cancelled_at is not null from public.bookings
     where student_id = 'f2000000-0000-0000-0000-0000000000a2'
       and starts_at = current_setting('test.slot_a')::timestamptz),
  'cancel_booking stamps cancelled_at on the caller''s live booking');

-- Cancelling the same slot again finds no live row.
select throws_like(
  $$ select public.cancel_booking(current_setting('test.slot_a')::timestamptz) $$,
  '%no live booking%',
  'an already-cancelled booking cannot be cancelled again');

-- A past booking is not cancellable (only future slots).
select throws_like(
  $$ select public.cancel_booking(current_setting('test.slot_past')::timestamptz) $$,
  '%no live booking%',
  'a booking in the past cannot be cancelled');

reset role;

-- A different student cannot cancel someone else's booking.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f2000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select throws_like(
  $$ select public.cancel_booking(current_setting('test.slot_b')::timestamptz) $$,
  '%no live booking%',
  'a bystander cannot cancel another student''s booking');

reset role;

-- ...and that bystander attempt left slot_b untouched.
select ok(
  (select cancelled_at is null from public.bookings
     where student_id = 'f2000000-0000-0000-0000-0000000000a2'
       and starts_at = current_setting('test.slot_b')::timestamptz),
  'the failed cross-student cancel did not affect the real booking');

-- Cancelling frees the person: is_person_busy is false at the cancelled slot.
select ok(
  not private.is_person_busy('f2000000-0000-0000-0000-0000000000a2', current_setting('test.slot_a')::timestamptz),
  'a cancelled slot no longer counts the person as busy');

select * from finish();
rollback;
