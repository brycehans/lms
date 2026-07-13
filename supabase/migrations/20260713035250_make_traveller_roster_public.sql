-- Make the "Meet our time travellers" roster public (visible to anonymous
-- visitors), not auth-gated. Two axes have to open together, per table:
--
--   1. A column-scoped GRANT — which COLUMNS anon may read. We deliberately grant
--      only the columns the roster needs, not the whole row. This fails closed:
--      a future column added to profiles/user_roles is NOT exposed to anon until
--      someone deliberately grants it, and a stray `select *` from anon errors
--      instead of over-sharing.
--   2. A SELECT policy that includes `anon` — which ROWS anon may read. RLS is
--      enabled on both tables, so a grant alone yields zero rows; the row filter
--      still lives in the policy. The filters are UNCHANGED — we only widen the
--      audience from `authenticated` to `anon, authenticated`.
--
-- Net anon exposure: traveller ids + names only. Non-traveller personas
-- (students/admins/superadmins) stay invisible because the row filters below
-- never match them.

--------------------------------------------------------------------------------
-- user_roles: anon may read only the traveller rows, only the two columns the
-- roster query reads (user_id to join, role to filter).
grant select (user_id, role) on user_roles to anon;

drop policy allow_authenticated_to_see_travellers on user_roles;

create policy allow_anyone_to_see_travellers on user_roles
  for select to anon, authenticated
  using (user_roles.role = 'traveller'::user_role);

--------------------------------------------------------------------------------
-- profiles: anon may read only non-deleted traveller profiles, only the three
-- columns the roster renders. (The policy's exists(...) subquery reads user_roles
-- under anon's RLS too — the traveller grant above is what lets it resolve.)
grant select (id, first_name, last_name) on profiles to anon;

drop policy authenticated_users_browse_travellers on profiles;

create policy anyone_browses_travellers on profiles
  for select to anon, authenticated
  using (profiles.deleted_at is null
    and exists (
      select
        1
      from
        user_roles ur
      where
        ur.user_id = profiles.id
        and ur.role = 'traveller'::user_role));
