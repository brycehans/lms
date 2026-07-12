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

delete from universities;

delete from auth.users;

--------------------------------------------------------------------------------
-- Users. Inserting into auth.users fires the trigger, which creates profiles.
-- (email/metadata only; no password — RLS is tested via the impersonation rig,
-- not real logins.)
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tim.rollins@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Tim","last_name":"Rollins"}', now(), now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'alice.kindleton@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Alice","last_name":"Kindleton"}', now(), now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'evan.towers@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Evan","last_name":"Towers"}', now(), now(), now()),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kerry.davies@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Kerry","last_name":"Davies"}', now(), now(), now()),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bryce.hanscomb@example.com', '{"provider":"email","providers":["email"]}', '{"first_name":"Bryce","last_name":"Hanscomb"}', now(), now(), now());

--------------------------------------------------------------------------------
-- Roles (junction table — a user can hold more than one; Evan is both).
insert into user_roles (user_id, role)
values
  ('11111111-1111-1111-1111-111111111111', 'student'::user_role),
  -- Tim
  ('22222222-2222-2222-2222-222222222222', 'traveller'::user_role),
  -- Alice
  ('33333333-3333-3333-3333-333333333333', 'student'::user_role),
  -- Evan (both)
  ('33333333-3333-3333-3333-333333333333', 'traveller'::user_role),
  ('44444444-4444-4444-4444-444444444444', 'admin'::user_role),
  -- Kerry
  ('55555555-5555-5555-5555-555555555555', 'superadmin'::user_role);

-- Bryce
--------------------------------------------------------------------------------
-- Universities. Fixed UUIDs so bookings + admin rows can reference them
-- deterministically (the explicit id overrides the table's gen_random_uuid()).
insert into universities (id, name)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'University of Technology Sydney'),
  -- UTS
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'University of Sydney');

-- USyd
--------------------------------------------------------------------------------
-- University administrations (junction). Kerry administers UTS only.
-- Bryce (superadmin) deliberately gets NO row: superadmin is unscoped by
-- definition, so the RBAC policy grants it every uni regardless of this table.
insert into university_administrations (user_id, university_id)
  values ('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Kerry -> UTS
--------------------------------------------------------------------------------
-- Bookings, covering upcoming / completed / cancelled states.
-- university_id is FROZEN from the student's nominal enrollment at creation
-- (denormalized, not joined-through): Tim = UTS, Evan-as-student = USyd.
-- Split is 3 UTS / 1 USyd so Kerry (UTS admin) must see 3 and be blind to 1.
insert into bookings (student_id, time_traveller_id, reason, starts_at, cancelled_at, university_id)
  values -- Tim (UTS) + Alice, upcoming
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'final exam for HLTN1001', now() + interval '1 day', null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  -- Tim (UTS) + Alice, cancelled (was scheduled for today)
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'final exam for HLTN1001', date_trunc('day', now()), now() - interval '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  -- Evan (USyd, student) + Alice, completed in the past
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'prac for Jazz 201', now() - interval '3 days', null, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  -- Tim (UTS, student) + Evan (traveller), upcoming
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'Summative exam for CS2003', now() + interval '4 days', null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

