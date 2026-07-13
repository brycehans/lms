# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Course Prophecies" — a mini-LMS built on the Next.js + Supabase starter kit. Students book 1-hour consultations with "time travellers" who prophesy their grades. Built on Next.js (App Router, canary features) + local Supabase (Postgres 17) in Docker.

## Commands

```bash
pnpm dev         # starts local Supabase (docker) AND next dev together (app on :1955)
pnpm teardown    # stops Supabase + wipes db volumes + removes derived files (node_modules, .next, local env) → fresh-clone state. Flags: --dry-run, --yes, --keep-env
pnpm build       # next build
pnpm typecheck   # tsc --noEmit — the reliable pre-commit check
pnpm lint        # eslint . — currently BROKEN (eslint-config-next 15.3.1 vs ESLint 9 flat-config); use typecheck instead
```

Supabase (CLI pinned in devDependencies — invoke via `pnpm supabase …` or `npx supabase …`):

```bash
supabase start                 # boots the local stack (Studio on :54323, API on :54321, db on :54322)
supabase db reset              # drops, re-runs ALL migrations, then runs seed.sql — the local rebuild
supabase migration new <name>  # scaffold a new timestamped migration
supabase db push               # apply migrations to the LINKED (hosted) project — does NOT run seed.sql
```

There is no test suite. Backend correctness is verified by hand against the local db (Studio / SQL editor).

## Architecture — the security model is the whole point

This is a server-mediated Supabase app, which is deliberately *not* the default Supabase pattern. The one rule everything follows:

- **Reads**: Server Components call the Supabase SDK directly. **RLS policies** scope what each role sees — there is no hand-written authz in the app layer for reads.
- **Writes**: go through **Next.js API Route Handlers** (`app/api/**/route.ts`) that call `SECURITY DEFINER` **RPCs**. This is the *only* client-writable surface. There are deliberately **no INSERT/UPDATE/DELETE RLS policies** on the tables — mutation is impossible except through a vetted RPC.

Consequences to keep in mind:
- Never add table-level write policies to "make a mutation work." Add or extend an RPC instead.
- RLS only matters for reads. RPCs bypass RLS (they run as definer), so each RPC must enforce its own invariants internally (`auth.uid()` checks, busy-checks, business-hours domains, etc.).
- Route handlers use the cookie-aware server client (`lib/supabase/server.ts`), which writes refreshed auth cookies onto the response. Do not call Supabase auth from a bare client on the server.

### Three Postgres schemas

- `public` — tables + the RPC functions (exposed via PostgREST). RPCs are `revoke execute … from public, anon` then `grant execute … to authenticated`.
- `private` — helper functions used inside RLS policies and RPCs (e.g. `is_person_busy`, `find_assignable_traveller`, `admin_university_ids`). `authenticated` has USAGE on the schema so policies resolve, but EXECUTE is revoked from `public` and the schema is not in PostgREST's exposed list, so nothing here gets a REST endpoint.
- `auth` — Supabase's. `profiles.id` FKs to `auth.users(id) ON DELETE CASCADE`. On signup, a `SECURITY DEFINER` trigger (`handle_new_user`) reads `raw_user_meta_data` and inserts the `profiles` row — so the app never inserts profiles directly.

### Domain model

- `profiles` — the app's user table (named "profiles" to avoid confusion with `auth.users`). Soft-deletable (`deleted_at`); no hard delete / GDPR support.
- `user_roles` — junction table (`user_id, role`) where `role` is the persona enum (`student`/`traveller`/`admin`/`superadmin`). The persona is stored, not derived — kept separate from bindings (enrolments, university administrations). Note: keeping roles out of `profiles` is a security decision — the profile self-update policy would otherwise let users promote themselves.
- `bookings` — student ↔ traveller at a `starts_at` slot. `university_id`, `student_first_name`, `student_last_name` are **frozen snapshots at creation time** (a later profile rename or uni transfer must not rewrite history). `cancelled_at` / `completed_at` are minted server-side by RPCs.
- `student_enrolments`, `universities`, `university_administrations` — tenancy. A student is enrolled in one uni (PK forbids multiple); admins are scoped to the unis they administer.

### Booking rules encoded in the DB (not the app)

Custom domain types enforce slots at the type level: `top_of_hour` → `business_hours` (9am–4pm start, Australia/Melbourne, hardcoded) → `is_bookable_start_time` (Mon–Fri). `create_booking` also assigns a random available traveller, takes a `pg_advisory_xact_lock` on the slot to close a both-roles race, and enforces "can't be in two places at once" via `is_person_busy`.

## Migrations

`supabase/migrations/` is the source of truth and is **append-only** — never edit an already-applied migration; add a new one. `supabase/seed.sql` is NOT a migration (`db push` skips it); it inserts `auth.users` rows with fixed UUIDs and lets the trigger create profiles. It runs on local `supabase db reset`.

## Deploy

Local Supabase (`127.0.0.1:54321`) is unreachable from a hosted deploy. See `deploy-prep.md` for the Vercel path (hosted Supabase + `db push` + env vars + auth redirect URLs).

## Known issues

- **Firefox reload loop in `next dev` (upstream Next 16.2.10 bug).** In Firefox,
  pages with dynamic (uncached) content — most visibly `/me` when signed in —
  can enter a hard reload loop (~3×/sec). It's **dev-only** (never happens in a
  production build) and **Firefox-only** (Chrome is unaffected). Cause: Next's
  React debug channel (`experimental.reactDebugChannel`, on by default) calls
  `location.reload()` when the browser serves the dev HTML from cache
  (`PerformanceNavigationTiming.transferSize === 0`) and can't restore the
  channel from `sessionStorage`. We are **leaving the feature on** (it powers dev
  tooling / the `/_next/mcp` browser introspection); **use Chrome for local dev**
  to avoid it, or set `experimental.reactDebugChannel: false` in `next.config.ts`
  if you must use Firefox. **Known upstream** — vercel/next.js#94634, fixed by
  vercel/next.js#94128 (in `16.3.0-canary.30`); stable `latest` is still 16.2.10,
  so the mitigation stays until 16.3 ships stable. Investigation record in
  `docs/bug-reports/nextjs-firefox-debug-channel-reload-loop.md` (marked do-not-file).
