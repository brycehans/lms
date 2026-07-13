-- Close a gap in the "no client-writable surface" model.
--
-- Supabase bootstraps every project with `grant all on all tables in schema
-- public to anon, authenticated`. This project deliberately never grants
-- INSERT/UPDATE/DELETE to those roles — all mutation goes through SECURITY
-- DEFINER RPCs, and RLS has no write policies — but `grant all` also handed out
-- TRUNCATE, which survived. TRUNCATE is special: it is NOT subject to row-level
-- security, so unlike a blocked DELETE it would let a client role empty a table
-- wholesale, sidestepping the invariant the rest of the schema enforces.
--
-- It is not reachable through the app's exposed surface today (PostgREST has no
-- TRUNCATE verb, and there is no other raw-SQL path for these roles), so this is
-- defense-in-depth rather than a live hole — but the privilege layer should match
-- the stated guarantee, so we revoke it.
--
-- INSERT/UPDATE/DELETE are intentionally left as-is: they were never granted, and
-- they respect RLS regardless. REFERENCES/TRIGGER remain (they are inert without
-- CREATE on the schema, which these roles also lack) and are not data mutations.
revoke truncate on all tables in schema public from anon, authenticated;

-- And for any table added later: stop the same bootstrap default from re-granting
-- TRUNCATE. All public tables are owned by postgres, so postgres's default
-- privileges are the ones that apply to future CREATE TABLEs here.
alter default privileges for role postgres in schema public revoke truncate on tables from anon, authenticated;
