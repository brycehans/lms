# Deploy Prep — Vercel

The Next.js app deploys to Vercel with **no code changes**. The only real work
is giving it a publicly reachable Supabase, since local dev points at
`http://127.0.0.1:54321` (Docker on your machine), which Vercel's functions
cannot reach.

## 1. Stand up a hosted Supabase

1. Create a hosted project at [supabase.com](https://supabase.com) (or
   self-host somewhere with a public URL).
2. Push the migrations — the full schema (tables, RLS, RPCs) lives in
   `supabase/migrations/`, so this reproduces it cleanly:

   ```bash
   supabase link --project-ref <ref>
   supabase db push
   ```

   Skip `supabase/seed.sql` for production unless you want the fake seed data.

## 2. Set env vars in Vercel

Project → Settings → Environment Variables:

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | hosted project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | hosted project publishable / anon key |
| `NEXT_PUBLIC_DEMO_LOGINS` | `true` to show the one-click Quick-login panel (demo only) |
| `NEXT_PUBLIC_DEMO_PASSWORD` | shared demo password; must match the seed (default `prophecy`) |

## Quick-login (demo reviewer access)

`/auth/login` shows a one-click "Jump straight in (demo)" block **above** the
email/password form — the preferred entry for a reviewer — with one button per
seeded persona (student, student+traveller, traveller, admin, superadmin). It
renders only when `NEXT_PUBLIC_DEMO_LOGINS=true`, and otherwise the login page is
just the ordinary form.

### How it works

- Each button calls the *normal* `supabase.auth.signInWithPassword` with the
  seeded account's email and the shared demo password. There is **no
  impersonation endpoint and no service-role code path** — it's the exact auth
  flow a real user takes, so sessions, cookies, and RLS all behave identically.
- The password is the same for every seeded account. It is env-driven on both
  sides and defaults to `prophecy`:
  - **DB**: `seed.sql` hashes `coalesce(current_setting('app.demo_password', true), 'prophecy')` into `auth.users.encrypted_password`.
  - **Client**: `QuickLogin` sends `NEXT_PUBLIC_DEMO_PASSWORD ?? 'prophecy'`.
  These two **must match**, or sign-in fails.

### Security posture

This feature deliberately publishes working credentials to anyone who can load
the login page, so it is **only safe behind edge gating**:

- **Never enable it on a public-facing production deploy.** `NEXT_PUBLIC_DEMO_LOGINS`
  must be unset/`false` there, so the panel and the client-side password never
  ship in the bundle.
- For the reviewer demo, gate access at the edge, not in the app:
  - **Vercel access protection** (password/SSO) in front of the whole deployment,
    so only the reviewer reaches the login page at all.
  - **DB network restriction** so the hosted Postgres only accepts connections
    from the Vercel deployment — a leaked anon key can't be used from elsewhere.
- The accounts are **seed data only** (throwaway `@example.com` users, no real
  PII), and the password is a throwaway shared secret — treat both as public.
- Because it rides the standard auth flow, it grants **no more than a real login
  would**: RLS still scopes every read, and writes still go through the vetted
  RPCs. Quick-login changes *who can obtain a session*, not *what a session can do*.

### Enabling it on the hosted demo

1. Run `supabase/seed.sql` against the hosted DB once (SQL editor, or
   `psql "$HOSTED_DB_URL" -f supabase/seed.sql`). `db push` does **not** run it.
   To use a non-default password, set the GUC when running:
   `PGOPTIONS="-c app.demo_password=yourpw" psql "$HOSTED_DB_URL" -f supabase/seed.sql`.
2. Set `NEXT_PUBLIC_DEMO_LOGINS=true` in Vercel (and `NEXT_PUBLIC_DEMO_PASSWORD`
   to the same password if you overrode the default).
3. Confirm the edge gating above is in place **before** enabling the flag.

## 3. Configure auth redirect URLs

The signup route handler (`app/api/auth/signup/route.ts`) sets
`emailRedirectTo` from the request's `origin` header — on Vercel that's your
`*.vercel.app` domain. Supabase rejects redirects that aren't allow-listed, so
add that domain under **Auth → URL Configuration → Redirect URLs** in the
hosted dashboard.

Confirmation emails use Supabase's built-in SMTP by default (heavily
rate-limited) — fine for a demo, but wire up real SMTP for anything serious.

## Non-issues

- `dev: "supabase start & next dev"` is dev-only. Vercel runs `build`
  (`next build`), which is clean.
- `proxy.ts` middleware deploys as an edge function normally.

## Caveat: Next.js canary features

`next.config.ts` sets `cacheComponents: true`, and the middleware uses the new
`proxy.ts` naming — both are **Next.js canary** features. The app is on
`next: latest` and Vercel builds from the lockfile, so the deployed version
matches local. Just expect a canary Next version in production; that's normal
given those two features.
