-- ============================================================================
-- set_booking_completion — a student marks one of their OWN, already-happened
-- bookings complete (or un-complete). Idempotent by design.
--
-- Guards: must be the caller's own booking; cannot touch a cancelled booking;
-- cannot mark an upcoming (future) booking. Bookings inserted directly with
-- fixed ids so we can pass them to the RPC.
-- ============================================================================
begin;
select plan(7);

-- Fixtures --------------------------------------------------------------------
insert into public.universities (id, name)
  values ('f4000000-0000-0000-0000-0000000000f4', 'Completion Test University');

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('f4000000-0000-0000-0000-0000000000a4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','done.sa@example.com','{"provider":"email"}','{"first_name":"Sam","last_name":"Owner"}', now(), now(), now()),
  ('f4000000-0000-0000-0000-0000000000b4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','done.sb@example.com','{"provider":"email"}','{"first_name":"Bo","last_name":"Other"}', now(), now(), now()),
  ('f4000000-0000-0000-0000-0000000000c4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','done.tt@example.com','{"provider":"email"}','{"first_name":"Ty","last_name":"Traveller"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('f4000000-0000-0000-0000-0000000000a4','student'::public.user_role),
  ('f4000000-0000-0000-0000-0000000000b4','student'::public.user_role),
  ('f4000000-0000-0000-0000-0000000000c4','traveller'::public.user_role);

select set_config('test.slot_past',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '2 weeks' + interval '10 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);
select set_config('test.slot_future',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '8 weeks' + interval '10 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);
select set_config('test.slot_past2',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '3 weeks' + interval '11 hours')::timestamp
     at time zone 'Australia/Melbourne')::text, true);

-- b001 past & open (completable); b002 future (not completable); b003 cancelled.
insert into public.bookings (id, student_id, time_traveller_id, reason, starts_at, cancelled_at, university_id, student_first_name, student_last_name)
values
  ('f4000000-0000-0000-0000-00000000b001','f4000000-0000-0000-0000-0000000000a4','f4000000-0000-0000-0000-0000000000c4','past open', current_setting('test.slot_past')::timestamptz,   null,        'f4000000-0000-0000-0000-0000000000f4','Sam','Owner'),
  ('f4000000-0000-0000-0000-00000000b002','f4000000-0000-0000-0000-0000000000a4','f4000000-0000-0000-0000-0000000000c4','upcoming',  current_setting('test.slot_future')::timestamptz, null,        'f4000000-0000-0000-0000-0000000000f4','Sam','Owner'),
  ('f4000000-0000-0000-0000-00000000b003','f4000000-0000-0000-0000-0000000000a4','f4000000-0000-0000-0000-0000000000c4','cancelled', current_setting('test.slot_past2')::timestamptz,  now(),       'f4000000-0000-0000-0000-0000000000f4','Sam','Owner');

-- Act as the owner ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"f4000000-0000-0000-0000-0000000000a4","role":"authenticated"}';

-- Mark complete.
select public.set_booking_completion('f4000000-0000-0000-0000-00000000b001', true);
select ok(
  (select completed_at is not null from public.bookings where id = 'f4000000-0000-0000-0000-00000000b001'),
  'set_booking_completion(true) stamps completed_at on a past booking');

-- Marking complete again is idempotent (no error).
select lives_ok(
  $$ select public.set_booking_completion('f4000000-0000-0000-0000-00000000b001', true) $$,
  'marking an already-complete booking complete again does not error');

-- Un-complete clears it.
select public.set_booking_completion('f4000000-0000-0000-0000-00000000b001', false);
select ok(
  (select completed_at is null from public.bookings where id = 'f4000000-0000-0000-0000-00000000b001'),
  'set_booking_completion(false) clears completed_at');

-- An upcoming booking cannot be completed.
select throws_like(
  $$ select public.set_booking_completion('f4000000-0000-0000-0000-00000000b002', true) $$,
  '%upcoming%',
  'an upcoming booking cannot be marked complete');

-- A cancelled booking cannot change completion state.
select throws_like(
  $$ select public.set_booking_completion('f4000000-0000-0000-0000-00000000b003', true) $$,
  '%cancelled%',
  'a cancelled booking''s completion cannot be changed');

-- A booking id that doesn't exist (for this caller) is refused.
select throws_like(
  $$ select public.set_booking_completion('f4000000-0000-0000-0000-0000000000de', true) $$,
  '%no booking found%',
  'a non-existent booking id is refused');

reset role;

-- A different student cannot complete someone else's booking (it resolves to none).
set local role authenticated;
set local request.jwt.claims to '{"sub":"f4000000-0000-0000-0000-0000000000b4","role":"authenticated"}';

select throws_like(
  $$ select public.set_booking_completion('f4000000-0000-0000-0000-00000000b001', true) $$,
  '%no booking found%',
  'a bystander cannot complete another student''s booking');

reset role;

select * from finish();
rollback;
