-- ============================================================================
-- create_booking — the write RPC that turns a chosen slot into a booking.
--
-- It is the trust boundary: it re-validates inputs, takes the per-slot advisory
-- lock, refuses if the caller is already busy, resolves the caller's enrolment,
-- assigns a random free traveller, and FREEZES the passed names + enrolled
-- university onto the row. (The concurrency half of the lock is covered by
-- scripts/test-slot-lock-contention.sh; here we test the single-session logic.)
--
-- Isolated fixtures (f1…) built as the owner; the RPC is then called as the
-- authenticated student. Slots are far-future Melbourne weekday hours so the
-- caller and the seed travellers are all free. One transaction, rolled back.
-- ============================================================================
begin;
select plan(11);

-- Fixtures --------------------------------------------------------------------
insert into public.universities (id, name)
  values ('f1000000-0000-0000-0000-0000000000f1', 'RPC Test University');

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('f1000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rpc.sa@example.com','{"provider":"email"}','{"first_name":"Sam","last_name":"Enrolled"}', now(), now(), now()),
  ('f1000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rpc.sb@example.com','{"provider":"email"}','{"first_name":"Nyla","last_name":"Unenrolled"}', now(), now(), now()),
  ('f1000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rpc.tt@example.com','{"provider":"email"}','{"first_name":"Toni","last_name":"Traveller"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('f1000000-0000-0000-0000-0000000000a1','student'::public.user_role),
  ('f1000000-0000-0000-0000-0000000000b1','student'::public.user_role),  -- deliberately NOT enrolled
  ('f1000000-0000-0000-0000-0000000000c1','traveller'::public.user_role);

insert into public.student_enrolments (student_id, university_id) values
  ('f1000000-0000-0000-0000-0000000000a1','f1000000-0000-0000-0000-0000000000f1');

-- Deterministic slots stashed in GUCs so the dynamic-SQL assertions below can
-- reference them without string interpolation.
select set_config('test.future_slot',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne')
     + interval '8 weeks' + interval '10 hours')::timestamp
   at time zone 'Australia/Melbourne')::text, true);
select set_config('test.past_slot',
  ((date_trunc('week', now() at time zone 'Australia/Melbourne')
     - interval '2 weeks' + interval '10 hours')::timestamp
   at time zone 'Australia/Melbourne')::text, true);

-- Become the enrolled student ------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"f1000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- Happy path: returns an id, and the side effects are exactly right.
select isnt(
  public.create_booking(
    current_setting('test.future_slot')::timestamptz::public.is_bookable_start_time,
    'final exam', 'Frozen', 'Name'),
  null, 'create_booking returns a new booking id');

select is(
  (select university_id from public.bookings
     where student_id = 'f1000000-0000-0000-0000-0000000000a1'
       and starts_at = current_setting('test.future_slot')::timestamptz),
  'f1000000-0000-0000-0000-0000000000f1',
  'university_id is frozen from the caller''s enrolment');

select is(
  (select student_first_name || ' ' || student_last_name from public.bookings
     where student_id = 'f1000000-0000-0000-0000-0000000000a1'
       and starts_at = current_setting('test.future_slot')::timestamptz),
  'Frozen Name',
  'the passed names are frozen onto the booking (not the profile name)');

select isnt(
  (select time_traveller_id from public.bookings
     where student_id = 'f1000000-0000-0000-0000-0000000000a1'
       and starts_at = current_setting('test.future_slot')::timestamptz),
  'f1000000-0000-0000-0000-0000000000a1',
  'the assigned traveller is never the caller (no meeting yourself)');

select ok(
  (select time_traveller_id is not null from public.bookings
     where student_id = 'f1000000-0000-0000-0000-0000000000a1'
       and starts_at = current_setting('test.future_slot')::timestamptz),
  'a free traveller was assigned');

-- Busy check: caller already has the slot from the happy path.
select throws_like(
  $$ select public.create_booking(
       current_setting('test.future_slot')::timestamptz::public.is_bookable_start_time,
       'double book', 'Frozen', 'Name') $$,
  '%already busy%',
  'a second booking at the same slot is refused (caller already busy)');

-- Past slot: a valid weekday hour, but before now().
select throws_like(
  $$ select public.create_booking(
       current_setting('test.past_slot')::timestamptz::public.is_bookable_start_time,
       'time travel', 'Frozen', 'Name') $$,
  '%past%',
  'a booking in the past is refused');

-- Input re-validation at the trust boundary.
select throws_like(
  $$ select public.create_booking(
       (current_setting('test.future_slot')::timestamptz + interval '1 hour')::public.is_bookable_start_time,
       'blank name', '   ', 'Name') $$,
  '%name%required%',
  'a blank first name is refused');

select throws_like(
  $$ select public.create_booking(
       (current_setting('test.future_slot')::timestamptz + interval '1 hour')::public.is_bookable_start_time,
       'too long', repeat('x', 101), 'Name') $$,
  '%100 characters%',
  'a name longer than 100 characters is refused');

select throws_like(
  $$ select public.create_booking(
       (current_setting('test.future_slot')::timestamptz + interval '1 hour')::public.is_bookable_start_time,
       repeat('x', 2001), 'Frozen', 'Name') $$,
  '%2000 characters%',
  'a reason longer than 2000 characters is refused');

reset role;

-- Not enrolled: switch to the student with no enrolment row.
set local role authenticated;
set local request.jwt.claims to '{"sub":"f1000000-0000-0000-0000-0000000000b1","role":"authenticated"}';

select throws_like(
  $$ select public.create_booking(
       current_setting('test.future_slot')::timestamptz::public.is_bookable_start_time,
       'no uni', 'Nyla', 'Unenrolled') $$,
  '%not enrolled%',
  'a student with no enrolment cannot create a booking');

reset role;

select * from finish();
rollback;
