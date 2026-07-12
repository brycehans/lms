create type user_role as ENUM (
  -- customers/bookers (travellers could be students at the/any uni)
  'student',
  'traveller',
  -- staff (can't book, can't be students, can't be travellers)
  'admin',
  'superadmin'
);

create table profiles (
  id uuid primary key default gen_random_uuid (),
  first_name text not null,
  last_name text not null,
  created_at timestamptz not null default now(),
  -- soft deletes, no GDPR support, etc
  deleted_at timestamptz
);

create table user_roles (
  user_id uuid references profiles (id) on delete no ACTION not null,
  role user_role not null,
  primary key (user_id, role)
);

create table bookings (
  id uuid primary key default gen_random_uuid (),
  reason text not null,
  student_id uuid references profiles (id) on delete no ACTION not null,
  time_traveller_id uuid references profiles (id) on delete no ACTION not null,
  -- we could make "starts_at" nullable but most bookings will be not-cancelled so
  -- we can make the extra check work be done on cancelled lookups rather than
  -- where-not-null done in the common path
  starts_at timestamptz not null,
  -- point-in-time snapshot of the student's name AT BOOKING TIME (frozen, like
  -- university_id): the profile name can change later via the profile edit form,
  -- but a booking records who it was made under when it was made.
  student_first_name text not null,
  student_last_name text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  cancelled_at timestamptz,
  -- null = not yet marked complete; a timestamp = when the student marked it done.
  -- minted server-side by the completion RPC (like cancelled_at), toggled back to
  -- null to un-complete. only completable once the session is in the past.
  completed_at timestamptz
);

