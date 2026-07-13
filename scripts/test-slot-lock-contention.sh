#!/usr/bin/env bash
#
# Concurrency regression test for the per-slot advisory lock that stops one person
# being double-booked at a slot when they are the STUDENT on one booking and the
# assigned TRAVELLER on another (the per-role unique indexes each see only one
# column, so only the lock catches this).
#
# It exercises the exact pairing that regressed: create_booking (session A) vs
# reschedule_booking (session B), targeting the same destination slot S.
#
#   Bug shape: 20260713190300 restored the TimeZone-dependent text-hash lock key
#   in create_booking while reschedule_booking kept the epoch key, so the two
#   paths hashed the same instant to DIFFERENT bigint keys and never contended.
#   20260714090000 restored the epoch key in create_booking.
#
# The test asserts three things, all deterministic (no timing guesses — waits are
# server-side on pg_stat_activity/pg_locks):
#   1. CONTENTION: while A holds the lock inside an open transaction, B's
#      reschedule BLOCKS on the same advisory lock (pg_blocking_pids(B) contains
#      A). This is the regression: revert 20260714090000 and this assertion FAILS
#      because the two paths take different keys and B never blocks.
#   2. PREVENTION: once A commits, B unblocks, sees the person now busy, and
#      refuses with "already busy" instead of committing the double-book.
#   3. INVARIANT: no person appears twice (as student or traveller) at slot S
#      among active bookings.
#
# Requires: the local Supabase stack running (container supabase_db_lms). It
# creates its own isolated fixtures (unique f0000000-… UUIDs) and tears them down
# on exit, so it is repeatable and independent of seed state.

set -euo pipefail

CID="supabase_db_lms"

# --- identities (isolated from seed) ------------------------------------------
PA="f0000000-0000-0000-0000-0000000000aa"  # session A caller: student (+traveller), the collision person
PB="f0000000-0000-0000-0000-0000000000bb"  # session B caller: student who reschedules
TT="f0000000-0000-0000-0000-0000000000cc"  # a plain traveller so A's create always has someone to assign
TU="f0000000-0000-0000-0000-000000000001"  # test university

# --- slots: a weekday, 10:00 / 11:00 Australia/Melbourne, 42 days out ----------
# Built as Melbourne wall-clock then converted to an instant, so they satisfy the
# is_bookable_start_time domain (top-of-hour, 9–16 Melbourne, Mon–Fri) and are far
# enough out to be free for everyone.
DAY="((now() at time zone 'Australia/Melbourne')::date + 42 + case extract(isodow from ((now() at time zone 'Australia/Melbourne')::date + 42)) when 6 then 2 when 7 then 1 else 0 end)"
S_SQL="(($DAY::text || ' 10:00')::timestamp at time zone 'Australia/Melbourne')"        # destination slot (both A and B aim here)
SB_SQL="(($DAY::text || ' 11:00')::timestamp at time zone 'Australia/Melbourne')"       # B's existing booking's current slot

AOUT="$(mktemp)"; BOUT="$(mktemp)"

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
pass() { echo "${GREEN}PASS${RST}  $*"; }
fail() { echo "${RED}FAIL${RST}  $*"; exit 1; }
step() { echo "${DIM}··· $*${RST}"; }

# scalar query on a fresh connection (the observer)
q() { docker exec -i "$CID" psql -U postgres -d postgres -qtA -v ON_ERROR_STOP=1 -c "$1" | tr -d '[:space:]'; }

# block server-side until a boolean SQL condition holds (or time out)
wait_for() { # $1=boolean SQL expr  $2=label  $3=timeout secs
  local cond="$1" label="$2" t="${3:-15}"
  docker exec -i "$CID" psql -U postgres -d postgres -qtA -v ON_ERROR_STOP=1 >/dev/null <<SQL
do \$do\$
declare deadline timestamptz := clock_timestamp() + interval '$t seconds';
begin
  loop
    exit when ($cond);
    if clock_timestamp() > deadline then raise exception 'timeout waiting for: $label'; end if;
    perform pg_sleep(0.1);
  end loop;
end
\$do\$;
SQL
}

cleanup() {
  # close the two long-lived session FDs if still open
  exec 8>&- 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
  docker exec -i "$CID" psql -U postgres -d postgres -qtA >/dev/null 2>&1 <<SQL || true
select pg_terminate_backend(pid) from pg_stat_activity
  where application_name in ('locktest_A','locktest_B') and pid <> pg_backend_pid();
delete from public.bookings        where student_id in ('$PA','$PB','$TT') or time_traveller_id in ('$PA','$PB','$TT');
delete from public.student_enrolments where student_id in ('$PA','$PB','$TT');
delete from public.user_roles      where user_id in ('$PA','$PB','$TT');
delete from auth.users             where id in ('$PA','$PB','$TT');
delete from public.universities    where id = '$TU';
SQL
  rm -f "$AOUT" "$BOUT"
}
trap cleanup EXIT

echo "== booking slot-lock contention test =="

# --- fixtures -----------------------------------------------------------------
step "creating isolated fixtures"
docker exec -i "$CID" psql -U postgres -d postgres -qtA -v ON_ERROR_STOP=1 >/dev/null <<SQL
-- clean any residue from a previous aborted run
delete from public.bookings        where student_id in ('$PA','$PB','$TT') or time_traveller_id in ('$PA','$PB','$TT');
delete from public.student_enrolments where student_id in ('$PA','$PB','$TT');
delete from public.user_roles      where user_id in ('$PA','$PB','$TT');
delete from auth.users             where id in ('$PA','$PB','$TT');
delete from public.universities    where id = '$TU';

insert into public.universities (id, name) values ('$TU', 'Lock Test University');

-- inserting auth.users fires handle_new_user, which creates the profiles rows.
-- no university_id in metadata => trigger skips auto enrol/role; we set them below.
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
values
  ('$PA','00000000-0000-0000-0000-000000000000','authenticated','authenticated','locktest.pa@example.com','{"provider":"email","providers":["email"]}','{"first_name":"Casey","last_name":"Ayye"}', now(), now(), now()),
  ('$PB','00000000-0000-0000-0000-000000000000','authenticated','authenticated','locktest.pb@example.com','{"provider":"email","providers":["email"]}','{"first_name":"Bailey","last_name":"Bee"}', now(), now(), now()),
  ('$TT','00000000-0000-0000-0000-000000000000','authenticated','authenticated','locktest.tt@example.com','{"provider":"email","providers":["email"]}','{"first_name":"Toni","last_name":"Cee"}', now(), now(), now());

insert into public.user_roles (user_id, role) values
  ('$PA','student'::public.user_role), ('$PA','traveller'::public.user_role),
  ('$PB','student'::public.user_role),
  ('$TT','traveller'::public.user_role);

insert into public.student_enrolments (student_id, university_id) values
  ('$PA','$TU'), ('$PB','$TU');

-- B's existing booking: PB is the student, PA is the assigned traveller. When B
-- reschedules this into S, it must re-check that PA (the traveller) is free at S.
insert into public.bookings (student_id, time_traveller_id, reason, starts_at, university_id, student_first_name, student_last_name)
values ('$PB','$PA','lock-test existing booking', $SB_SQL, '$TU','Bailey','Bee');
SQL

# preflight: confirm auth.uid() is driven by the request.jwt.claims GUC as expected
UIDOK=$(q "set request.jwt.claims='{\"sub\":\"$PA\"}'; select case when auth.uid()='$PA' then 'ok' else 'no' end;")
[ "$UIDOK" = "ok" ] || fail "auth.uid() is not driven by request.jwt.claims — impersonation rig broken"
pass "fixtures created; auth.uid() impersonation confirmed"

# --- session A: BEGIN + create_booking(S); hold the transaction open ----------
step "session A: create_booking(S) inside an open transaction"
exec 8> >(docker exec -e PGAPPNAME=locktest_A -i "$CID" psql -U postgres -d postgres -q -v ON_ERROR_STOP=0 >"$AOUT" 2>&1)
cat >&8 <<SQL
set request.jwt.claims = '{"sub":"$PA","role":"authenticated"}';
begin;
select public.create_booking( ($S_SQL)::public.is_bookable_start_time, 'lock-test create', 'Casey', 'Ayye');
SQL

wait_for "(select count(*) from pg_locks l join pg_stat_activity s on s.pid=l.pid where s.application_name='locktest_A' and l.locktype='advisory' and l.granted) >= 1" "A to hold the slot lock"
APID=$(q "select pid from pg_stat_activity where application_name='locktest_A' order by backend_start desc limit 1;")
pass "session A holds the advisory lock on S (pid $APID, idle in transaction)"

# --- session B: BEGIN + reschedule(SB -> S); must block on A's lock -----------
step "session B: reschedule_booking(SB -> S) — expected to block"
exec 9> >(docker exec -e PGAPPNAME=locktest_B -i "$CID" psql -U postgres -d postgres -q -v ON_ERROR_STOP=0 >"$BOUT" 2>&1)
cat >&9 <<SQL
set request.jwt.claims = '{"sub":"$PB","role":"authenticated"}';
begin;
select public.reschedule_booking( ($SB_SQL)::timestamptz, ($S_SQL)::public.is_bookable_start_time );
SQL

wait_for "exists (select 1 from pg_stat_activity where application_name='locktest_B' and wait_event_type='Lock' and wait_event='advisory')" "B to block on the advisory lock"
BPID=$(q "select pid from pg_stat_activity where application_name='locktest_B' order by backend_start desc limit 1;")

# ASSERTION 1 — the regression: B is blocked specifically BY A, on the same lock.
BLOCKED_BY_A=$(q "select pg_blocking_pids($BPID) @> array[$APID]::int[];")
[ "$BLOCKED_BY_A" = "t" ] || fail "B is not blocked by A — create/reschedule are NOT contending on the same slot key (regression present)"
pass "CONTENTION: reschedule (B, pid $BPID) is blocked by create (A, pid $APID) on the same slot lock"

# --- release A; B proceeds and must refuse the double-book --------------------
step "committing session A; session B should now refuse"
echo "commit;" >&8
wait_for "not exists (select 1 from pg_stat_activity where application_name='locktest_B' and state='active')" "B to finish after A commits"

# ASSERTION 2 — prevention: B raised an "already busy" error rather than committing.
if grep -qi "already busy" "$BOUT"; then
  pass "PREVENTION: reschedule refused with $(grep -i 'already busy' "$BOUT" | head -1 | sed 's/^[A-Z ]*ERROR:  //')"
else
  echo "----- session B output -----"; cat "$BOUT"; echo "----------------------------"
  fail "B did not refuse with an 'already busy' error — a double-book may have committed"
fi
echo "rollback;" >&9

# ASSERTION 3 — invariant: nobody is double-occupying slot S in active bookings.
DUPS=$(q "select count(*) from (
  select person from (
    select student_id as person from public.bookings where starts_at = $S_SQL and cancelled_at is null and deleted_at is null
    union all
    select time_traveller_id from public.bookings where starts_at = $S_SQL and cancelled_at is null and deleted_at is null
  ) u group by person having count(*) > 1
) d;")
[ "$DUPS" = "0" ] || fail "INVARIANT violated: $DUPS person(s) appear twice at slot S"
pass "INVARIANT: no person double-booked at slot S"

echo "${GREEN}== all assertions passed ==${RST}"
