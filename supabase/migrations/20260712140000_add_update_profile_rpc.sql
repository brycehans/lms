create function public.update_profile(p_first_name text, p_last_name text)
  returns void
  security definer
  set search_path = ''
  language plpgsql
  as $$
begin
  -- reject blank names
  if trim(p_first_name) = '' or trim(p_last_name) = '' then
    raise exception 'first and last name cannot be blank';
  end if;
  update
    public.profiles
  set
    first_name = p_first_name,
    last_name = p_last_name
  where
    id = auth.uid();
end;
$$;

revoke execute on function public.update_profile(text, text) from public, anon;

grant execute on function public.update_profile(text, text) to authenticated;

