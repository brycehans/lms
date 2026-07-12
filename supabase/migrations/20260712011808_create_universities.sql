create table universities (
  id uuid primary key default gen_random_uuid (),
  name text not null,
  created_at timestamptz default now() not null,
  deleted_at timestamptz
);

create table university_administrations (
  user_id uuid references profiles (id) on delete cascade,
  university_id uuid references universities (id) on delete cascade,
  primary key (user_id, university_id)
);

alter table bookings
  add column university_id uuid references universities (id) on delete no action not null;

