-- Enforce the 100-character name cap at the real signup boundary (the trigger).
--
-- create_booking and update_profile both cap names at 100 chars, but those are
-- RPCs. The anon key is public, so supabase.auth.signUp can be called directly,
-- bypassing app/api/auth/signup/route.ts AND the RPCs entirely — the trigger,
-- not the route, is the true signup write boundary. It already rejects blank
-- names but did NOT bound their length, so a direct signup could persist an
-- oversized (e.g. 10 MB) name. Add the same 100-char cap here so the invariant
-- holds no matter which surface creates the user.
--
-- Full body restated (create or replace rewrites it); only the new length check
-- is added. The on_auth_user_created trigger keeps pointing at this function, so
-- no trigger re-creation is needed.
create or replace function private.handle_new_user ()
  returns trigger
  security definer
  set search_path = ''
  as $$
begin
  -- names are identity, not optional. Reject rather than store a blank.
  if coalesce(trim(new.raw_user_meta_data ->> 'first_name'), '') = ''
     or coalesce(trim(new.raw_user_meta_data ->> 'last_name'), '') = '' then
    raise exception 'signup requires a non-empty first_name and last_name in user metadata';
  end if;

  -- length cap, matching create_booking / update_profile. Checked on the trimmed
  -- value (the value we actually store), so trailing padding can't smuggle length.
  if char_length(trim(new.raw_user_meta_data ->> 'first_name')) > 100
     or char_length(trim(new.raw_user_meta_data ->> 'last_name')) > 100 then
    raise exception 'first and last name must each be at most 100 characters';
  end if;

  insert into public.profiles (id, first_name, last_name)
    values (new.id, trim(new.raw_user_meta_data ->> 'first_name'), trim(new.raw_user_meta_data ->> 'last_name'));

  -- university_id present == a real student self-signup (seeded users omit it).
  if new.raw_user_meta_data ? 'university_id' then
    -- re-validate against a LIVE university at the true boundary. A bad cast
    -- (non-uuid) raises invalid_text_representation and is rejected too.
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
