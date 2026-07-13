-- ============================================================================
-- SLOT DOMAIN TYPES — booking rules enforced at the TYPE level, not in app code.
--
-- A bookable start time is built as a chain of domains, each adding one check:
--   top_of_hour     — date_trunc('hour', v) = v          (no :30, no :45)
--   business_hours  — hour 9..16 (Australia/Melbourne)    (9am–4pm start)
--   is_bookable_start_time — isodow 1..5 (Mon–Fri)        (no weekends)
-- Because create_booking's parameter IS this domain, a bad time is rejected by
-- the type system before any function body runs. A failed domain check raises
-- sqlstate 23514 (check_violation).
--
-- Slots are built as Melbourne wall-clock then converted to an instant, anchored
-- to a fixed week (Mon 2026-07-13) so day-of-week / hour are deterministic and
-- independent of when the suite runs.
-- ============================================================================
begin;
select plan(9);

-- --- valid slots: accepted by the full chain --------------------------------
select lives_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '10 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  'Mon 10:00 Melbourne is a bookable start time');

select lives_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '9 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  'Mon 09:00 (first bookable hour) is accepted');

select lives_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '16 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  'Mon 16:00 (last bookable start) is accepted');

-- --- top_of_hour: reject anything not on the hour ---------------------------
select throws_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '10 hours 30 minutes')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  '23514', null, 'Mon 10:30 is rejected (not top of the hour)');

-- --- business_hours: reject before 9am / after 4pm start --------------------
select throws_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '8 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  '23514', null, 'Mon 08:00 is rejected (before business hours)');

select throws_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '17 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  '23514', null, 'Mon 17:00 is rejected (after the last bookable start)');

-- --- is_bookable_start_time: reject weekends --------------------------------
select throws_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '5 days 10 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  '23514', null, 'Sat 10:00 is rejected (weekend)');

select throws_ok(
  $$ select (((date_trunc('week', date '2026-07-15') + interval '6 days 10 hours')::timestamp)
             at time zone 'Australia/Melbourne')::is_bookable_start_time $$,
  '23514', null, 'Sun 10:00 is rejected (weekend)');

-- --- the private predicate agrees with the domain ---------------------------
-- create_booking / list_available_slots gate on private.is_bookable_slot; it must
-- accept exactly what the domain accepts (here: a good weekday slot).
select ok(
  private.is_bookable_slot(
    ((date_trunc('week', date '2026-07-15') + interval '10 hours')::timestamp)
      at time zone 'Australia/Melbourne'),
  'private.is_bookable_slot agrees the Mon 10:00 slot is bookable');

select * from finish();
rollback;
