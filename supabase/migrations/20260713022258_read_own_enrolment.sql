-- TRADEOFF OPPORTUNITY! Why a read policy and not an RPC:
-- rpcs with security definer tiers are immune to rls policies, and we use
-- them often when a user needs to know something about rows they aren't
-- party to, but asking for your own enrolment row is fine to allow
grant select on public.student_enrolments to authenticated;

-- student may read only their own enrolment row.
create policy read_own_enrolment on public.student_enrolments
  for select to authenticated
  using (auth.uid() = student_id);

