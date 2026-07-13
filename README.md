# Course Prophecies

A mini-LMS where students book 1-hour consultations with "time travellers" who
prophesy their grades. Built on Next.js (App Router) + Supabase (Postgres 17),
running locally in Docker.

The interesting part is the **security model**, not the fortune-telling: this is
a deliberately server-mediated Supabase app (not the default client-writes
pattern), and the whole design turns on one rule — see [Architecture](#architecture).

## Quick start

```bash
pnpm install
cp .env.example .env.local   # local Supabase defaults — works as-is
pnpm dev                     # boots local Supabase (docker) AND next dev together
```

Requires Docker running (for the local Supabase stack). The values in
`.env.example` are the local stack's fixed dev defaults, so the copy above is all
the config a clone needs.

- App: [localhost:3000](http://localhost:3000)
- Supabase Studio: [localhost:54323](http://localhost:54323) · API on `:54321` · db on `:54322`

The landing page has one-click demo logins for each persona (student, traveller,
admin, superadmin), seeded deterministically by `supabase/seed.sql`.

> **Local dev:** use Chrome. Firefox hits an upstream Next 16.2.10 dev-only reload
> loop on pages with dynamic content (e.g. `/me`); see the note in `CLAUDE.md`.

### Useful commands

```bash
pnpm typecheck                 # tsc --noEmit — the reliable pre-commit gate
pnpm build                     # next build
pnpm supabase db reset         # drop, re-run ALL migrations, then seed.sql (local rebuild)
pnpm supabase migration new X  # scaffold a timestamped migration
```

There is no automated test suite; backend correctness is verified by hand against
the local db (Studio / SQL editor).

## Architecture

One rule everything follows:

- **Reads**: Server Components call the Supabase SDK directly. **RLS policies**
  scope what each role sees — there is no hand-written read authz in the app layer.
- **Writes**: go through **Next.js API Route Handlers** that call `SECURITY
  DEFINER` **RPCs**. This is the *only* client-writable surface. There are
  deliberately **no INSERT/UPDATE/DELETE RLS policies** on the tables — mutation
  is impossible except through a vetted RPC.

Because RPCs run as definer (bypassing RLS), each one enforces its own invariants
internally: `auth.uid()` checks, busy-checks, business-hours domain types, a
per-slot advisory lock, and re-validation of anything a client could forge. RLS
only governs reads.

### Three Postgres schemas

- `public` — tables + the RPCs (exposed via PostgREST). RPCs are
  `revoke execute … from public, anon` then `grant execute … to authenticated`.
- `private` — helpers used inside RLS policies and RPCs (`is_person_busy`,
  `find_assignable_traveller`, `admin_university_ids`, `business_tz`, …). Not in
  PostgREST's exposed schema list, so nothing here gets a REST endpoint.
- `auth` — Supabase's. On signup a `SECURITY DEFINER` trigger (`handle_new_user`)
  reads `raw_user_meta_data` and creates the `profiles` row, student role, and
  enrolment — so the app never inserts profiles directly, and role is hardcoded
  server-side so signup can't self-promote.

### Domain model

- `profiles` — the app's user table (soft-deletable via `deleted_at`).
- `user_roles` — `(user_id, role)` junction. Roles live **outside** `profiles`
  precisely so the profile self-update policy can't be used to self-elevate.
- `bookings` — student ↔ traveller at a `starts_at` slot. `university_id` and the
  student name are **frozen snapshots at creation** (a later rename/transfer must
  not rewrite history). `cancelled_at` / `completed_at` are minted server-side.
- `student_enrolments`, `universities`, `university_administrations` — tenancy.

Booking slots are enforced at the **type level** by custom domains:
`top_of_hour` → `business_hours` (9am–4pm, Australia/Melbourne) →
`is_bookable_start_time` (Mon–Fri). `create_booking` also assigns a random free
traveller, takes a `pg_advisory_xact_lock` on the slot to close a both-roles
double-booking race, and enforces "can't be in two places at once".

## Sitemap

Legend: ✅ built

### Pages

```
/                       ✅ public landing (availability calendar, traveller roster, universities)
/book                   ✅ booking form — session dropdown (deep-linked via ?start_at=),
                             editable first/last name (prefilled from profile), reason
/me                     ✅ account page — identity + per-role bookings:
  ├─ student            ✅   own consultations (reason/datetime/traveller/state),
  │                            mark complete/incomplete, cancel, reschedule
  ├─ traveller          ✅   own assigned sessions (read-only)
  └─ admin/superadmin   ✅   oversight — consultations scoped by RLS
                             (admin: their universities · superadmin: all), read-only
  └─ profile edit       ✅   first/last name form (POSTs to /api/profile → update_profile RPC)
/auth/login             ✅ email + password sign-in (+ one-click demo logins)
/auth/sign-up           ✅ sign-up — captures first/last name + university, which the
                             handle_new_user trigger turns into a profile + student role
                             + enrolment
/auth/sign-up-success   ✅ account-ready notice; email confirmation is OFF, so signup
                             leaves the user logged in and the CTA continues any pending
                             booking
/auth/forgot-password   ✅ request a reset link
/auth/update-password   ✅ set a new password
/auth/confirm           ✅ email-confirmation / OTP callback (route handler)
/auth/error             ✅ auth error page
```

### API Route Handlers (mutations → RPC)

Every write goes through a handler that calls one `SECURITY DEFINER` RPC — there
is no direct table DML from the client.

```
POST   /api/auth/signup           ✅ -> auth.signUp (metadata drives the profile trigger)
POST   /api/bookings/create       ✅ -> create_booking(starts_at, reason, first_name, last_name)
POST   /api/bookings/cancel       ✅ -> cancel_booking(starts_at)
POST   /api/bookings/reschedule   ✅ -> reschedule_booking(current_start, new_start)
POST   /api/bookings/complete     ✅ -> set_booking_completion(booking_id, is_complete)
POST   /api/profile               ✅ -> update_profile(first_name, last_name)
```

> Booking cancel/reschedule key off `starts_at` (the RPCs identify a booking by
> student + slot), while completion keys off `booking_id`.

## Migrations

`supabase/migrations/` is the source of truth and is **append-only** — never edit
an applied migration; add a new one. `supabase/seed.sql` is **not** a migration
(`db push` skips it); it seeds `auth.users` with fixed UUIDs and lets the trigger
create profiles. It runs on local `supabase db reset`.

## Known limitations (by design, for this take-home)

- **Hardcoded business timezone.** `Australia/Melbourne` is baked into the
  `business_hours` domain. Runtime slot logic is timezone-safe (routed through
  `private.business_tz()`), but the domain type still assumes a whole-hour UTC
  offset — the one documented spot that would need a migration to move to a
  fractional-hour zone.
- **Soft delete only.** `deleted_at`; no hard delete / GDPR erasure path.
- **No automated tests.** Backend correctness is checked by hand against local db.

## Deploy

Local Supabase (`127.0.0.1:54321`) is unreachable from a hosted deploy. See
`deploy-prep.md` for the Vercel path (hosted Supabase + `db push` + env vars +
auth redirect URLs). The public demo enables the one-click logins behind a
site-wide HTTP Basic Auth gate (`DEMO_BASIC_AUTH`, enforced in `proxy.ts`) so the
published demo credentials only reach reviewers who clear the gate.
