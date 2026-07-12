-- students may only be enrolled in one uni at a time.
-- they are allowed to change unis and keep their old bookings
-- (bookings are scoped to a uni)
create table student_enrolments(
  student_id uuid primary key references profiles(id) on delete cascade,
  university_id uuid references universities(id) on delete cascade not null,
  created_at timestamptz default now() not null
);

alter table student_enrolments enable row level security;

