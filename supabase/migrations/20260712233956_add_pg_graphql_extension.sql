-- hosted supabase has graphql setup by default but local
-- requires enabling it to get access. we enable it for
-- the demo to enhance code explanation and walkthrus.
create extension if not exists pg_graphql;

