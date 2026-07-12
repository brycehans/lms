-- ensure we avoid toctou issues by competing bookings by having the first
-- committed one own that slot even if atomicity can't catch it
--
create unique index student_in_timeslot on bookings(student_id, starts_at)
where
  deleted_at is null and cancelled_at is null;

create unique index traveller_in_timeslot on bookings(time_traveller_id, starts_at)
where
  deleted_at is null and cancelled_at is null;

