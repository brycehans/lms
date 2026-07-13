-- Close the two residual gaps at the signup trust boundary.
--
-- The anon key is public, so supabase.auth.signUp can be called directly,
-- bypassing app/api/auth/signup/route.ts entirely. The trigger — not the route —
-- is therefore the real boundary, and it was trusting two things the route
-- happened to check but a direct signup does not:
--
-- (1) University must be alive. The route's alive-check reads `universities`
--     under RLS (which hides deleted_at rows); a direct signup only gets FK
--     validation, and the student_enrolments FK can't see deleted_at. Result: a
--     student enrolled at a soft-deleted university, which create_booking then
--     freezes onto every booking. Re-check `deleted_at is null` here.
--
-- (2) Names must be present. Missing first_name/last_name previously hit the
--     profiles NOT NULL and surfaced as GoTrue's opaque "Database error saving
--     new user". Make it a DELIBERATE raise with a clear message rather than an
--     incidental constraint trip — we refuse to fabricate a blank identity.
--
-- Role stays HARDCODED to 'student' (unchanged): the trigger never reads a role
-- from client metadata, so signup still can't self-promote.
create or replace function private.handle_new_user ()
  returns trigger
  security definer
  set search_path = ''
  as $$
begin
  -- (2) names are identity, not optional. Reject rather than store a blank.
  if coalesce(trim(new.raw_user_meta_data ->> 'first_name'), '') = ''
     or coalesce(trim(new.raw_user_meta_data ->> 'last_name'), '') = '' then
    raise exception 'signup requires a non-empty first_name and last_name in user metadata';
  end if;

  insert into public.profiles (id, first_name, last_name)
    values (new.id, trim(new.raw_user_meta_data ->> 'first_name'), trim(new.raw_user_meta_data ->> 'last_name'));

  -- university_id present == a real student self-signup (seeded users omit it).
  if new.raw_user_meta_data ? 'university_id' then
    -- (1) re-validate against a LIVE university here at the true boundary. A bad
    -- cast (non-uuid) raises invalid_text_representation and is rejected too.
    if not exists (
      select 1
      from public.universities
      where id = (new.raw_user_meta_data ->> 'university_id')::uuid
        and deleted_at is null) then
      raise exception 'signup references an unknown or deleted university';
    end if;

    insert into public.user_roles (user_id, role)
      values (new.id, 'student')
    on conflict do nothing;

    insert into public.student_enrolments (student_id, university_id)
      values (new.id, (new.raw_user_meta_data ->> 'university_id')::uuid)
    on conflict do nothing;
  end if;

  return NEW;
end;
$$
language plpgsql;
