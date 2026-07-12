alter table universities enable row level security;

alter table university_administrations enable row level security;

alter table user_roles enable row level security;

-- First:
-- unis should be public for the anon brochureware index pages
-- no mechanism for uni CRUD after initial seed, so no policies required for maintaining unis
-- (we can build them if/when uni CRUD management is built out)
create policy public_read_universities on universities
  for select to public
  using (deleted_at is null);

--
-- Second:
-- university_administrations stays deny-all because the only
-- readers of that table are in security definer bypass context
-- where rls is not in effect;
--
-- Third:
-- policy authenticated_users_browse_travellers needs to allow the RLS checker to access
-- rows where the user is a traveller so it can do its job
create policy allow_authenticated_to_see_travellers on user_roles
  for select to authenticated
  using (user_roles.role = 'traveller'::user_role)
