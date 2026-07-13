-- ============================================================================
-- NO CLIENT-WRITABLE SURFACE — the central architectural invariant.
--
-- The tables have NO INSERT/UPDATE/DELETE RLS policies and the client roles get
-- no write GRANTs; all mutation is funnelled through SECURITY DEFINER RPCs. So a
-- client role holding a valid session must be unable to write to ANY table
-- directly. Every failure below is sqlstate 42501 (insufficient_privilege) —
-- whether from the missing GRANT or an RLS row check, both are the wall doing
-- its job.
--
-- This also pins the fix from migration 20260714093000: TRUNCATE (which bypasses
-- RLS) is revoked, so it can't be used to empty a table out from under the model.
-- ============================================================================
begin;
select plan(13);

-- Act as a fully authenticated student (Tim). The identity is irrelevant to the
-- outcome — no client role can write regardless of who they are.
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- Sanity / positive control: reads DO work, so the failures below are the write
-- path being blocked, not a broken connection.
select lives_ok(
  $$ select 1 from public.bookings limit 1 $$,
  'authenticated CAN read bookings (positive control)');

-- bookings — no direct writes of any kind.
select throws_ok(
  $$ insert into public.bookings (id) values (gen_random_uuid()) $$,
  '42501', null, 'authenticated cannot INSERT a booking directly');

select throws_ok(
  $$ update public.bookings set reason = 'hacked' $$,
  '42501', null, 'authenticated cannot UPDATE bookings directly');

select throws_ok(
  $$ delete from public.bookings $$,
  '42501', null, 'authenticated cannot DELETE bookings directly');

select throws_ok(
  $$ truncate public.bookings $$,
  '42501', null, 'authenticated cannot TRUNCATE bookings (revoked in 20260714093000)');

-- user_roles — the self-promotion attack. This is why roles live in their own
-- table and not on profiles: even a direct insert of a superadmin row is denied.
select throws_ok(
  $$ insert into public.user_roles (user_id, role)
       values ('11111111-1111-1111-1111-111111111111', 'superadmin') $$,
  '42501', null, 'authenticated cannot grant itself a role (no self-promotion)');

select throws_ok(
  $$ update public.user_roles set role = 'superadmin' $$,
  '42501', null, 'authenticated cannot UPDATE user_roles');

-- profiles — even your OWN row is only writable via update_profile, not directly.
select throws_ok(
  $$ insert into public.profiles (id, first_name, last_name)
       values (gen_random_uuid(), 'Mallory', 'Malicious') $$,
  '42501', null, 'authenticated cannot INSERT a profile directly');

select throws_ok(
  $$ update public.profiles set first_name = 'Renamed' $$,
  '42501', null, 'authenticated cannot UPDATE profiles directly (only via RPC)');

-- tenancy tables — enrolments, universities, administrations are all read-only
-- to clients.
select throws_ok(
  $$ insert into public.student_enrolments (student_id, university_id)
       values ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') $$,
  '42501', null, 'authenticated cannot self-enrol into a university');

select throws_ok(
  $$ insert into public.universities (name) values ('Fake U') $$,
  '42501', null, 'authenticated cannot create a university');

select throws_ok(
  $$ insert into public.university_administrations (user_id, university_id)
       values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  '42501', null, 'authenticated cannot make itself a university admin');

reset role;

-- Catalog-level backstop: assert TRUNCATE is granted to NEITHER client role on ANY
-- public table, so a table added later can't quietly reintroduce the hole.
select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public'
      and privilege_type = 'TRUNCATE'
      and grantee in ('anon', 'authenticated')),
  0, 'no TRUNCATE granted to anon/authenticated on any public table');

select * from finish();
rollback;
