create function public.is_current_user_superadmin ()
  returns boolean
  security definer stable
  set search_path = ''
  as $$
  select
    exists (
      select
        1
      from
        public.user_roles
      where
        role = 'superadmin'
        and user_id = auth.uid ());
$$
language sql;

-- which universities does the current user have admin reach over?
create function public.admin_university_ids ()
  returns setof uuid
  security definer stable
  set search_path = ''
  as $$
  select
    university_id
  from
    public.university_administrations
  where
    user_id = auth.uid ()
  union
  select
    id
  from
    public.universities
  where
    public.is_current_user_superadmin ()
    and public.universities.deleted_at is null;
$$
language sql;

