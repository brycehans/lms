-- Let a user read their OWN role rows.
--
-- Until now the only SELECT policy on user_roles was
-- `allow_anyone_to_see_travellers` (role = 'traveller'), which lets the roster
-- resolve traveller ids but leaves a student/admin/superadmin unable to read
-- even their own persona. The /me page needs it to decide which sections to
-- render, so add a self-read.
--
-- Why a plain policy and not a SECURITY DEFINER RPC (same reasoning as
-- read_own_enrolment): definer RPCs are for reading rows you AREN'T party to;
-- asking for your own row is fine to allow directly. RLS is row-level, and this
-- table only has (user_id, role) — there's nothing sensitive to hide per-column,
-- so exposing your own rows leaks nothing. The column grant
-- (grant select on public.user_roles to authenticated) already exists.
--
-- Note this is additive to allow_anyone_to_see_travellers: RLS policies are
-- OR'd, so a traveller still resolves via either policy.
create policy read_own_roles on public.user_roles
  for select to authenticated
  using (user_id = auth.uid());
