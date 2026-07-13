-- ============================================================================
-- reschedule_booking — move one of the caller's own upcoming bookings to a new
-- slot, keeping the same assigned traveller.
--
-- Guards (in order): reject a no-op same-time move, reject the past, take the
-- per-slot lock on the DESTINATION, resolve the caller's live target booking,
-- then refuse if EITHER party (the student OR the frozen traveller) is already
-- busy at the destination. Bookings inserted directly so the assigned traveller
-- is known. (The lock's concurrency behaviour is in the contention shell test.)
-- ============================================================================
begin;
select plan(7);

-- Fixtures --------------------------------------------------------------------
insert into public.universities (id, name)
  values ('f3000000-0000-0000-0000-0000000000f3', 'Reschedule Test University');

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('f3000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','res.sa@example.com','{"provider":"email"}','{"first_name":"Sam","last_name":"Owner"}', now(), now(), now()),
  ('f3000000-0000-0000-0000-0000000000b3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','res.sb@example.com','{"provider":"email"}','{"first_name":"Bea","last_name":"Other"}', now(), now(), now()),
  ('f3000000-0000-0000-0000-0000000000c3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','res.tt@example.com','{"provider":"email"}','{"first_name":"Tam","last_name":"Traveller"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('f3000000-0000-0000-0000-0000000000a3','student'::public.user_role),
  ('f3000000-0000-0000-0000-0000000000b3','student'::public.user_role),
  ('f3000000-0000-0000-0000-0000000000c3','traveller'::public.user_role);

-- Base = Monday 00:00 Melbourne, 8 weeks out (local wall clock, no tz yet).
select set_config('test.base',
  (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '8 weeks')::text, true);
-- Each slot = base + offset, converted from Melbourne wall-clock to an instant.
select set_config('test.cur_happy',     ((current_setting('test.base')::timestamp + interval '9 hours')          at time zone 'Australia/Melbourne')::text, true);
select set_config('test.new_happy',     ((current_setting('test.base')::timestamp + interval '10 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.cur_same',      ((current_setting('test.base')::timestamp + interval '11 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.cur_past_src',  ((current_setting('test.base')::timestamp + interval '12 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.cur_notowner',  ((current_setting('test.base')::timestamp + interval '13 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.cur_studbusy',  ((current_setting('test.base')::timestamp + interval '14 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.block_student', ((current_setting('test.base')::timestamp + interval '15 hours')         at time zone 'Australia/Melbourne')::text, true);
select set_config('test.cur_travbusy',  ((current_setting('test.base')::timestamp + interval '1 day 9 hours')    at time zone 'Australia/Melbourne')::text, true);
select set_config('test.block_trav',    ((current_setting('test.base')::timestamp + interval '1 day 10 hours')   at time zone 'Australia/Melbourne')::text, true);
select set_config('test.past_dest',     ((current_setting('test.base')::timestamp - interval '10 weeks' + interval '10 hours') at time zone 'Australia/Melbourne')::text, true);

-- SA's bookings (all SA + TT). Each scenario gets its own current slot so the
-- tests don't interfere. Plus two "blocker" bookings that occupy a destination.
insert into public.bookings (student_id, time_traveller_id, reason, starts_at, university_id, student_first_name, student_last_name)
values
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','happy',    current_setting('test.cur_happy')::timestamptz,    'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','same',     current_setting('test.cur_same')::timestamptz,     'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','pastsrc',  current_setting('test.cur_past_src')::timestamptz, 'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','notowner', current_setting('test.cur_notowner')::timestamptz, 'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','studbusy', current_setting('test.cur_studbusy')::timestamptz, 'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','travbusy', current_setting('test.cur_travbusy')::timestamptz, 'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  -- blocker: SA is ALSO busy at block_student (as a student), so a move there is refused.
  ('f3000000-0000-0000-0000-0000000000a3','f3000000-0000-0000-0000-0000000000c3','blkstud',  current_setting('test.block_student')::timestamptz,'f3000000-0000-0000-0000-0000000000f3','Sam','Owner'),
  -- blocker: the traveller TT is busy at block_trav (with a DIFFERENT student), so a move there is refused.
  ('f3000000-0000-0000-0000-0000000000b3','f3000000-0000-0000-0000-0000000000c3','blktrav',  current_setting('test.block_trav')::timestamptz,   'f3000000-0000-0000-0000-0000000000f3','Bea','Other');

-- Act as the owner ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-0000000000a3","role":"authenticated"}';

-- Happy path (setup call, then assert the move).
select public.reschedule_booking(
  current_setting('test.cur_happy')::timestamptz,
  current_setting('test.new_happy')::timestamptz::public.is_bookable_start_time);

select is(
  (select count(*)::int from public.bookings
     where student_id = 'f3000000-0000-0000-0000-0000000000a3'
       and starts_at = current_setting('test.new_happy')::timestamptz and cancelled_at is null),
  1, 'reschedule moves the booking to the new slot');

select is(
  (select count(*)::int from public.bookings
     where student_id = 'f3000000-0000-0000-0000-0000000000a3'
       and starts_at = current_setting('test.cur_happy')::timestamptz and cancelled_at is null),
  0, 'the original slot is vacated by the move');

-- Same-time move is a no-op and rejected.
select throws_like(
  $$ select public.reschedule_booking(
       current_setting('test.cur_same')::timestamptz,
       current_setting('test.cur_same')::timestamptz::public.is_bookable_start_time) $$,
  '%already at the time%',
  'rescheduling a booking onto its own slot is rejected');

-- Into the past is rejected.
select throws_like(
  $$ select public.reschedule_booking(
       current_setting('test.cur_past_src')::timestamptz,
       current_setting('test.past_dest')::timestamptz::public.is_bookable_start_time) $$,
  '%into the past%',
  'rescheduling into the past is rejected');

-- Destination where the STUDENT is already busy.
select throws_like(
  $$ select public.reschedule_booking(
       current_setting('test.cur_studbusy')::timestamptz,
       current_setting('test.block_student')::timestamptz::public.is_bookable_start_time) $$,
  '%you are already busy%',
  'cannot move to a slot where the student is already busy');

-- Destination where the assigned TRAVELLER is already busy.
select throws_like(
  $$ select public.reschedule_booking(
       current_setting('test.cur_travbusy')::timestamptz,
       current_setting('test.block_trav')::timestamptz::public.is_bookable_start_time) $$,
  '%time traveller is already busy%',
  'cannot move to a slot where the assigned traveller is already busy');

reset role;

-- A different student cannot reschedule someone else's booking.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f3000000-0000-0000-0000-0000000000b3","role":"authenticated"}';

select throws_like(
  $$ select public.reschedule_booking(
       current_setting('test.cur_notowner')::timestamptz,
       current_setting('test.new_happy')::timestamptz::public.is_bookable_start_time) $$,
  '%no booking for this student%',
  'a bystander cannot reschedule another student''s booking');

reset role;

select * from finish();
rollback;
