-- Course Prophecies seed data.
-- Run by hand in the SQL editor (or via `supabase db query --linked --file`).
-- NOT a migration: `db push` never runs this.
--
-- Since Slice 4, profiles.id references auth.users(id), so we can no longer
-- mint profile ids with gen_random_uuid(). Instead we insert auth.users rows
-- with fixed UUIDs; the on_auth_user_created trigger (SECURITY DEFINER) reads
-- first_name/last_name out of raw_user_meta_data and creates the matching
-- profiles row automatically. Fixed UUIDs also kill the old "look users up by
-- first_name" fragility — we reference people by id everywhere below.
--------------------------------------------------------------------------------
-- Teardown so this file is re-runnable. Order matters: clear the tables that
-- reference profiles (ON DELETE NO ACTION would otherwise block us), then wipe
-- auth.users — the ON DELETE CASCADE on profiles.id takes the profiles rows with it.
delete from bookings;

delete from user_roles;

delete from university_administrations;

delete from student_enrolments;

delete from universities;

delete from auth.users;

--------------------------------------------------------------------------------
-- Users. Inserting into auth.users fires the trigger, which creates profiles.
-- (email/metadata only; no password — RLS is tested via the impersonation rig,
-- not real logins.)
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tim.rollins@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Tim","last_name":"Rollins"}', now(), now(), now()),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kerry.davies@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Kerry","last_name":"Davies"}', now(), now(), now()),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bryce.hanscomb@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Bryce","last_name":"Hanscomb"}', now(), now(), now()),
  -- Six sample time travellers for the "Meet our time travellers" roster. Their
  -- slugified names (first-last, lowercased) map to /public/travellers/<slug>.webp.
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'amara.okafor@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Amara","last_name":"Okafor"}', now(), now(), now()),
  ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mei.chen@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Mei","last_name":"Chen"}', now(), now(), now()),
  ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agnes.thornwood@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Agnes","last_name":"Thornwood"}', now(), now(), now()),
  ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rafael.duarte@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Rafael","last_name":"Duarte"}', now(), now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kenji.watanabe@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Kenji","last_name":"Watanabe"}', now(), now(), now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'marcus.bell@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Marcus","last_name":"Bell"}', now(), now(), now());

-- 20 "filler" students. Their only job is to be enough distinct bodies to fill
-- every traveller's calendar at a slot: closing one slot needs all 6 travellers
-- busy, i.e. 6 concurrent bookings with 6 distinct students, so a realistic
-- ~75%-available calendar needs a student pool comfortably larger than the
-- roster. Generated (id 20000000-…-0000000NN) rather than hand-listed; the
-- on_auth_user_created trigger turns each into a profile.
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
select
  ('20000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  lower((first_names)[g]) || '.' || lower((last_names)[g]) || '@example.com',
  '{"provider":"email","providers":["email"]}',
  jsonb_build_object('first_name', (first_names)[g], 'last_name', (last_names)[g]),
  now(), now(), now()
from
  (select
     array['Olivia','Liam','Noah','Emma','Ava','Ethan','Sophia','Mason','Isabella','Lucas','Mia','Jack','Charlotte','Henry','Amelia','Leo','Grace','Oliver','Zoe','Ruby'] as first_names,
     array['Nguyen','Smith','Patel','Kim','Brown','Lee','Wilson','Chen','Taylor','Singh','Walker','Ali','Martin','Wang','Clarke','Ahmed','Reed','Lopez','Novak','Ford'] as last_names) names,
  generate_series(1, 20) g;

-- DEMO LOGIN: give every seeded account the same throwaway password so a grader
-- can sign in (via the login form or the one-click QuickLogin panel). pgcrypto
-- lives in the `extensions` schema on Supabase, so we qualify the calls. Seeding
-- runs locally on `db reset` and is run deliberately against the hosted DB
-- (`db push` skips seed.sql) — real-world exposure is meant to be gated at the
-- edge (DB firewalled to Vercel + Vercel access protection), not here.
--
-- The password is env-driven: it reads the `app.demo_password` session setting,
-- falling back to 'prophecy'. Local `db reset` uses the default; to override on
-- hosted, run with the GUC set, e.g.
--   PGOPTIONS="-c app.demo_password=yourpw" psql "$DB_URL" -f supabase/seed.sql
-- Keep it in sync with the client's NEXT_PUBLIC_DEMO_PASSWORD.
--
-- Also blank the token columns: a direct insert leaves them NULL, but GoTrue
-- scans them as non-null strings when authenticating, so a real login otherwise
-- 500s with "Database error querying schema". (Never hit before because these
-- accounts had never actually logged in.)
update auth.users
  set encrypted_password = extensions.crypt(
      coalesce(current_setting('app.demo_password', true), 'prophecy'),
      extensions.gen_salt('bf')),
    confirmation_token = '',
    recovery_token = '',
    email_change = '',
    email_change_token_new = ''
where email like '%@example.com';

--------------------------------------------------------------------------------
-- Roles (junction table — a user can hold more than one; Amara and Marcus are both).
insert into user_roles (user_id, role)
values
  ('11111111-1111-1111-1111-111111111111', 'student'::user_role),
  -- Tim
  ('44444444-4444-4444-4444-444444444444', 'admin'::user_role),
  -- Kerry
  ('55555555-5555-5555-5555-555555555555', 'superadmin'::user_role),
  -- Bryce
  -- Sample travellers. Amara and Marcus (the two youngest-looking) double as
  -- students, so they hold both roles.
  ('66666666-6666-6666-6666-666666666666', 'traveller'::user_role),
  -- Amara (both)
  ('66666666-6666-6666-6666-666666666666', 'student'::user_role),
  ('77777777-7777-7777-7777-777777777777', 'traveller'::user_role),
  -- Mei
  ('88888888-8888-8888-8888-888888888888', 'traveller'::user_role),
  -- Agnes
  ('99999999-9999-9999-9999-999999999999', 'traveller'::user_role),
  -- Rafael
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'traveller'::user_role),
  -- Kenji
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'traveller'::user_role),
  -- Marcus (both)
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'student'::user_role);

-- Marcus
-- The 20 filler students get the student role.
insert into user_roles (user_id, role)
select
  ('20000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  'student'::user_role
from generate_series(1, 20) g;
--------------------------------------------------------------------------------
-- Universities. Fixed UUIDs so bookings + admin rows can reference them
-- deterministically (the explicit id overrides the table's gen_random_uuid()).
insert into universities (id, name)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'University of Technology Sydney'),
  -- UTS
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'University of Sydney'),
  -- USyd
  -- Two more universities to round out the directory. No bookings/admins
  -- reference these, so their ids only need to be distinct + stable across reseeds.
  ('10000000-0000-0000-0000-000000000001', 'University of Melbourne'),
  ('10000000-0000-0000-0000-000000000002', 'Monash University');
--------------------------------------------------------------------------------
-- University administrations (junction). Kerry administers UTS only.
-- Bryce (superadmin) deliberately gets NO row: superadmin is unscoped by
-- definition, so the RBAC policy grants it every uni regardless of this table.
insert into university_administrations (user_id, university_id)
  values ('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Kerry -> UTS
--------------------------------------------------------------------------------
-- Student enrolments (one uni per student). These MUST match the frozen
-- university_id on each student's bookings below, so RPC-created bookings land
-- in the same uni as the seeded history: Tim = UTS, Amara = UTS, Marcus = USyd.
-- (Kerry/Bryce are not students, so no enrolment rows.)
insert into student_enrolments (student_id, university_id)
  values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  -- Tim -> UTS
  ('66666666-6666-6666-6666-666666666666', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  -- Amara -> UTS
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

-- Marcus -> USyd
-- Enrol the 20 filler students, round-robin across all four universities, so
-- their bookings' frozen university_id spreads across tenants (Kerry, the UTS
-- admin, will see only the UTS slice).
insert into student_enrolments (student_id, university_id)
select
  ('20000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  (array[
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', -- UTS
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', -- USyd
    '10000000-0000-0000-0000-000000000001', -- Melbourne
    '10000000-0000-0000-0000-000000000002'  -- Monash
  ])[(g % 4) + 1]::uuid
from generate_series(1, 20) g;
--------------------------------------------------------------------------------
-- Bookings, covering every permutation of state (upcoming / cancelled /
-- completed) across both universities and both single- and dual-role people.
-- university_id is FROZEN from the student's nominal enrollment at creation
-- (denormalized, not joined-through): Tim = UTS, Amara = UTS, Marcus = USyd.
-- The UTS/USyd split means Kerry (UTS admin) sees the UTS rows and is blind to
-- the USyd ones. Amara and Marcus each appear as BOTH a booking's student and
-- (elsewhere) its time traveller, exercising the dual-role case.
--
-- starts_at must be a REAL slot (top-of-hour, 9am-4pm, Mon-Fri) so it matches
-- the create_booking domain rules. We build each slot in Melbourne WALL-CLOCK
-- and convert back to an instant:
--   date_trunc('week', now() at time zone 'Australia/Melbourne')  -> Monday 00:00 local
--   + interval offsets                                            -> the local slot
--   at time zone 'Australia/Melbourne'                            -> back to timestamptz
-- Week-anchored (not fixed dates) so upcoming/past states stay correct over time.
-- Slots are chosen so no ACTIVE (non-cancelled) party is double-booked at a slot.
-- student_first_name/last_name are FROZEN snapshots of each student's profile
-- name at booking time; here they match the profiles so "frozen == current"
-- until a profile is edited (Tim Rollins, Amara Okafor, Marcus Bell).
insert into bookings (student_id, time_traveller_id, reason, starts_at, cancelled_at, completed_at, university_id, student_first_name, student_last_name)
  values -- Tim (UTS) + Mei, upcoming: next Mon 9am
  ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777', 'final exam for HLTN1001', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 9 hours') at time zone 'Australia/Melbourne', null, null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Tim', 'Rollins'),
  -- Amara (UTS) + Rafael, upcoming: next Tue 10am
  ('66666666-6666-6666-6666-666666666666', '99999999-9999-9999-9999-999999999999', 'organic chemistry midterm', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 1 day 10 hours') at time zone 'Australia/Melbourne', null, null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Amara', 'Okafor'),
  -- Marcus (USyd) + Kenji, upcoming: next Wed 11am
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'thesis defence for PHIL402', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 2 days 11 hours') at time zone 'Australia/Melbourne', null, null, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Marcus', 'Bell'),
  -- Tim (UTS) + Marcus (traveller — dual role), upcoming: next Thu 1pm
  ('11111111-1111-1111-1111-111111111111', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Summative exam for CS2003', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 3 days 13 hours') at time zone 'Australia/Melbourne', null, null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Tim', 'Rollins'),
  -- Tim (UTS) + Agnes, cancelled: was next Mon 2pm, cancelled yesterday
  ('11111111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', 'retake for STAT1010', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 14 hours') at time zone 'Australia/Melbourne', now() - interval '1 day', null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Tim', 'Rollins'),
  -- Marcus (USyd) + Rafael, cancelled: was next Fri 3pm, cancelled a couple hours ago
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '99999999-9999-9999-9999-999999999999', 'logic final for PHIL210', (date_trunc('week', now() at time zone 'Australia/Melbourne') + interval '1 week 4 days 15 hours') at time zone 'Australia/Melbourne', now() - interval '2 hours', null, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Marcus', 'Bell'),
  -- Amara (UTS) + Kenji, completed: last Wed 10am, marked done an hour after it started
  ('66666666-6666-6666-6666-666666666666', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'prac for BIO150', (date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '1 week' + interval '2 days 10 hours') at time zone 'Australia/Melbourne', null, (date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '1 week' + interval '2 days 11 hours') at time zone 'Australia/Melbourne', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Amara', 'Okafor'),
  -- Marcus (USyd, student) + Amara (traveller — dual role), completed: last Tue 11am, done an hour later
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '66666666-6666-6666-6666-666666666666', 'prac for Jazz 201', (date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '1 week' + interval '1 day 11 hours') at time zone 'Australia/Melbourne', null, (date_trunc('week', now() at time zone 'Australia/Melbourne') - interval '1 week' + interval '1 day 12 hours') at time zone 'Australia/Melbourne', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Marcus', 'Bell');

--------------------------------------------------------------------------------
-- Generative fill so the calendar isn't wall-to-wall "Open". A slot only reads
-- as unavailable when ALL travellers are busy (list_available_slots keeps a slot
-- while >= 1 traveller is free), so we deterministically pick ~25% of upcoming
-- weekday slots to saturate fully (all 6 travellers booked) and partially fill
-- the rest — landing the calendar around ~75% availability.
--
-- Deterministic, not random(), so reseeds are reproducible: a slot's occupancy
-- is a hash of its position in the ordered slot list. Every booking here is
-- ACTIVE and future (no cancelled/completed — those live in the explicit rows
-- above). The NOT EXISTS guard keeps any person (as student OR traveller) from
-- being double-booked at a slot, which also keeps this from colliding with the
-- explicit bookings above.
with slots as (
  select
    gs as starts_at,
    row_number() over (order by gs) as slot_ix
  from generate_series(
    date_trunc('hour', now()) + interval '1 hour', -- next top-of-hour
    now() + interval '21 days',
    interval '1 hour') as gs
  where gs > now()
    and extract(isodow from gs at time zone 'Australia/Melbourne') between 1 and 5 -- Mon–Fri
    and extract(hour from gs at time zone 'Australia/Melbourne') between 9 and 16   -- 9am–4pm
),
-- occupancy per slot: hash to 0–99; < 25 → saturate all 6 travellers (slot goes
-- "Full"); otherwise book 0–5 of them (slot stays "Open").
slot_occ as (
  select
    starts_at,
    slot_ix,
    case
      when (((slot_ix * 1103515245 + 12345) % 100) + 100) % 100 < 25 then 6
      else (((slot_ix * 1103515245 + 12345) % 100) + 100) % 100 % 6
    end as k
  from slots
),
travellers as (
  select user_id, row_number() over (order by user_id) as t_ix
  from user_roles
  where role = 'traveller'::user_role
),
-- student pool = enrolled students who are NOT also travellers (keeps the
-- dual-role people out of the fill so they're never their own counterparty).
students as (
  select se.student_id, se.university_id, p.first_name, p.last_name,
    row_number() over (order by se.student_id) as s_ix
  from student_enrolments se
  join profiles p on p.id = se.student_id
  where se.student_id not in (select user_id from user_roles where role = 'traveller'::user_role)
),
student_count as (select count(*)::int as n from students)
insert into bookings (student_id, time_traveller_id, reason, starts_at, university_id, student_first_name, student_last_name)
select
  st.student_id,
  tr.user_id,
  'grade divination consult',
  so.starts_at,
  st.university_id,
  st.first_name,
  st.last_name
from slot_occ so
join travellers tr on tr.t_ix <= so.k
cross join student_count sc
-- spread which students take which slot/traveller so the fill looks organic
join students st on st.s_ix = ((so.slot_ix * 6 + tr.t_ix) % sc.n) + 1
where not exists (
  select 1 from bookings b
  where b.starts_at = so.starts_at
    and b.cancelled_at is null
    and b.deleted_at is null
    and (tr.user_id in (b.time_traveller_id, b.student_id)
      or st.student_id in (b.time_traveller_id, b.student_id)));

--------------------------------------------------------------------------------
-- Past sessions so EVERY student has completable history. A student can only
-- toggle completion on a booking whose session is in the past and not cancelled,
-- so each student gets 3 past bookings: one already completed (to test
-- UN-completing) and two past-but-open (to test completing). These are all in
-- the past, so they don't touch future calendar availability.
--
-- Each (student, j) lands on its OWN past slot (idx is unique across the set),
-- so no two of these bookings ever share a slot — that alone makes them
-- collision-free; the traveller <> student guard and the NOT EXISTS keep them
-- consistent with the dual-role people and the explicit rows above.
with past_slots as (
  select gs as starts_at, row_number() over (order by gs desc) as rn
  from generate_series(
    date_trunc('hour', now()) - interval '28 days',
    now() - interval '1 hour',
    interval '1 hour') as gs
  where gs < now() - interval '1 hour'
    and extract(isodow from gs at time zone 'Australia/Melbourne') between 1 and 5
    and extract(hour from gs at time zone 'Australia/Melbourne') between 9 and 16
),
students as (
  select se.student_id, se.university_id, p.first_name, p.last_name,
    row_number() over (order by se.student_id) as s_ix
  from student_enrolments se
  join profiles p on p.id = se.student_id
),
travellers as (
  select user_id, row_number() over (order by user_id) as t_ix
  from user_roles
  where role = 'traveller'::user_role
),
tcount as (select count(*)::int as n from travellers),
plan as (
  select
    st.student_id, st.university_id, st.first_name, st.last_name, j,
    ((st.s_ix - 1) * 3 + (j - 1)) as idx -- unique per (student, j) → unique slot
  from students st
  cross join generate_series(1, 3) as j
)
insert into bookings (student_id, time_traveller_id, reason, starts_at, completed_at, university_id, student_first_name, student_last_name)
select
  pl.student_id,
  tr.user_id,
  'past divination session',
  ps.starts_at,
  case when pl.j = 1 then ps.starts_at + interval '1 hour' end, -- j=1 already completed; j=2,3 left open
  pl.university_id,
  pl.first_name,
  pl.last_name
from plan pl
join past_slots ps on ps.rn = pl.idx + 1
cross join tcount tc
join travellers tr on tr.t_ix = (pl.idx % tc.n) + 1
where tr.user_id <> pl.student_id
  and not exists (
    select 1 from bookings b
    where b.starts_at = ps.starts_at
      and b.cancelled_at is null
      and b.deleted_at is null
      and (tr.user_id in (b.time_traveller_id, b.student_id)
        or pl.student_id in (b.time_traveller_id, b.student_id)));

