-- ============================================================================
-- RLS READ POLICIES — tenant isolation and per-role read visibility.
--
-- Reads are the ONLY thing RLS guards in this app (writes go through RPCs; see
-- 02_write_surface_locked_test.sql). So these tests ARE the read-authz suite.
--
-- The impersonation rig (same one scripts/test-slot-lock-contention.sh uses):
--   set local role authenticated;                       -- stop being the postgres
--                                                        -- superuser, who BYPASSES RLS
--   set local request.jwt.claims to '{"sub":"<uid>"}';  -- what auth.uid() reads
-- We `reset role` back to postgres between blocks to build fixtures as the
-- (RLS-exempt) owner. Everything runs in one transaction and rolls back, so the
-- suite leans on seed identities without mutating them.
--
-- Seed cast (see supabase/seed.sql):
--   Tim   11111111… student  @ UTS
--   Nadia 22222222… admin    @ University of Melbourne
--   Kerry 44444444… admin    @ UTS
--   Bryce 55555555… superadmin (unscoped)
--   Mei   77777777… traveller
--   UTS   aaaaaaaa…   USyd bbbbbbbb…   Melbourne 10000000-…-0001
-- ============================================================================
begin;
select plan(20);

-- A soft-deleted UTS booking: admins must NOT see it, superadmin must. Inserted
-- as the owner (postgres), bypassing RLS. deleted_at set => excluded from the
-- partial unique indexes, so it can't collide with seed rows.
insert into public.bookings
  (id, student_id, time_traveller_id, reason, starts_at, university_id,
   student_first_name, student_last_name, deleted_at)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   '11111111-1111-1111-1111-111111111111',
   '77777777-7777-7777-7777-777777777777',
   'soft-deleted fixture',
   now() + interval '90 days',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'Tim', 'Rollins', now());

-- ---------------------------------------------------------------------------
-- ANON (logged-out visitor): only the public traveller roster + universities.
-- Two layers stack here: column-scoped GRANTs cap WHICH columns anon may touch,
-- and RLS policies cap WHICH rows. We test both.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

-- RLS row filter: the roster policy shows travellers, hides everyone else.
select is(
  (select count(*)::int from public.profiles where id = '77777777-7777-7777-7777-777777777777'),
  1, 'anon CAN see a traveller profile (public roster)');

select is(
  (select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  0, 'anon CANNOT see a student-only profile');

select ok(
  (select count(*) from public.universities) > 0,
  'anon CAN read the university directory');

select is(
  (select count(*)::int from public.user_roles where role <> 'traveller'),
  0, 'anon sees ONLY traveller rows in user_roles');

reset role;

-- GRANT layer: anon's read surface is column-scoped, and bookings is off-limits
-- entirely. Asserted from the catalog (as owner) so a missing GRANT is a hard
-- permission error at query time, independent of any RLS row filter.
select ok(
  not has_table_privilege('anon', 'public.bookings', 'SELECT'),
  'anon has NO table SELECT on bookings (not even filtered — denied outright)');

select ok(
  has_column_privilege('anon', 'public.profiles', 'first_name', 'SELECT'),
  'anon MAY read the granted roster column profiles.first_name');

select ok(
  not has_column_privilege('anon', 'public.profiles', 'deleted_at', 'SELECT'),
  'anon may NOT read an ungranted column (profiles.deleted_at) — column-scoped');

-- ---------------------------------------------------------------------------
-- TIM (student): own bookings only; own enrolment; own non-traveller roles.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  1, 'Tim sees his own profile');

select is(
  (select count(*)::int from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  0, 'Tim CANNOT see Nadia (an admin who is not his booking counterparty)');

select is(
  (select count(*)::int from public.bookings
     where student_id <> '11111111-1111-1111-1111-111111111111'
       and time_traveller_id <> '11111111-1111-1111-1111-111111111111'),
  0, 'every booking Tim can see is one he is a party to');

select ok(
  (select count(*) from public.bookings) > 0,
  'Tim does see his own bookings (sanity: the wall is not just hiding everything)');

select is(
  (select count(*)::int from public.student_enrolments
     where student_id <> '11111111-1111-1111-1111-111111111111'),
  0, 'Tim sees only his own enrolment');

select is(
  (select count(*)::int from public.user_roles
     where user_id = '44444444-4444-4444-4444-444444444444'),
  0, 'Tim CANNOT see another user''s admin role row');

reset role;

-- ---------------------------------------------------------------------------
-- KERRY (UTS admin): scoped to UTS; blind to USyd; blind to soft-deleted.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

select ok(
  (select count(*) from public.bookings
     where university_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') > 0,
  'Kerry (UTS admin) sees UTS bookings');

select is(
  (select count(*)::int from public.bookings
     where university_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0, 'Kerry is blind to USyd bookings (tenant isolation)');

select is(
  (select count(*)::int from public.bookings
     where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  0, 'Kerry (non-superadmin) cannot see a soft-deleted UTS booking');

reset role;

-- ---------------------------------------------------------------------------
-- NADIA (Melbourne admin): the mirror image — sees Melbourne, blind to UTS.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select ok(
  (select count(*) from public.bookings
     where university_id = '10000000-0000-0000-0000-000000000001') > 0,
  'Nadia (Melbourne admin) sees Melbourne bookings');

select is(
  (select count(*)::int from public.bookings
     where university_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0, 'Nadia is blind to UTS bookings');

reset role;

-- ---------------------------------------------------------------------------
-- BRYCE (superadmin): unscoped — every uni, including soft-deleted rows.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

select is(
  (select count(distinct university_id)::int from public.bookings
     where university_id in ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                             'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')),
  2, 'Bryce (superadmin) sees across universities (UTS and USyd)');

select is(
  (select count(*)::int from public.bookings
     where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  1, 'Bryce (superadmin) CAN see the soft-deleted booking');

reset role;

select * from finish();
rollback;
