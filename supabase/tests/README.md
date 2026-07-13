# Database tests (pgTAP)

These are the primary correctness gate for the backend. Because the security
model is _server-mediated_ — RLS scopes all reads, and every write goes through a
`SECURITY DEFINER` RPC — the invariants worth testing live in the database, not
the app layer. So the suite runs **against the database**, in Postgres, using
[pgTAP](https://pgtap.org/).

## Running

```bash
pnpm test:db                       # whole suite (needs the local stack up)
pnpm supabase test db --local supabase/tests/04_create_booking_test.sql   # one file
```

`supabase test db --local` runs each `*.sql` file through `pg_prove` against the
running local database. pgTAP itself is provided by the test runner image — no
migration installs it, so it never reaches production. Each file wraps itself in
`begin … rollback`, so tests mutate freely and leave no trace; they can lean on
seed identities without disturbing them.

## The impersonation rig

Reads are gated by RLS, which only engages for non-superuser roles — but
`pg_prove` connects as the `postgres` superuser, who **bypasses RLS**. So to test
a policy we must stop being the superuser and present a JWT the way the app does:

```sql
set local role authenticated;                                    -- or `anon`
set local request.jwt.claims to '{"sub":"<user-uuid>","role":"authenticated"}';
-- ... assertions run as that user; auth.uid() returns <user-uuid> ...
reset role;                                                      -- back to postgres to build more fixtures
```

`auth.uid()` reads `sub` out of `request.jwt.claims`, so setting that GUC _is_
"logging in" for the purposes of RLS and the RPCs. This is the same rig
`scripts/test-slot-lock-contention.sh` uses.

Two things follow from it:

- **Fixtures are built as `postgres`** (RLS-exempt), then we drop to a client role
  to make assertions. Toggle back with `reset role`.
- **Grants are tested too.** Client roles only hold `SELECT` (column-scoped, for
  `anon`); calling an RPC as `authenticated` also exercises its `grant execute`.

## Files

| File                                | Covers                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| `01_rls_reads_test.sql`             | Tenant isolation & read visibility: anon roster, student/admin/superadmin scoping, column-scoped grants |
| `02_write_surface_locked_test.sql`  | No client-writable surface: direct INSERT/UPDATE/DELETE/TRUNCATE all denied     |
| `03_domain_types_test.sql`          | `is_bookable_start_time` domain chain (top-of-hour, 9–4, Mon–Fri)               |
| `04_create_booking_test.sql`        | `create_booking`: assignment, frozen snapshots, busy/past/validation/enrolment  |
| `05_cancel_booking_test.sql`        | `cancel_booking`: ownership, live-only, future-only                             |
| `06_reschedule_booking_test.sql`    | `reschedule_booking`: same-time, past, ownership, student- & traveller-busy     |
| `07_set_booking_completion_test.sql`| `set_booking_completion`: past-only, not-cancelled, ownership, idempotent        |
| `08_profile_and_signup_test.sql`    | `update_profile` (trim/blank/cap, no role escalation), frozen-name snapshot, `handle_new_user` signup trigger |

**Not covered here:** the _concurrency_ half of the per-slot advisory lock — a
single pgTAP transaction can't model two racing sessions. That lives in
`scripts/test-slot-lock-contention.sh` (`pnpm test:contention`), which drives two
real connections and asserts one blocks on the other's lock.
