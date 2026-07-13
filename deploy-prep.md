# Deploy Prep — Vercel

The Next.js app deploys to Vercel with **no code changes**. The only real work
is giving it a publicly reachable Supabase, since local dev points at
`http://127.0.0.1:54321` (Docker on your machine), which Vercel's functions
cannot reach.

> **Live demo (current state).** This is already deployed:
> - App: **https://lms-zeta-lyart.vercel.app** (Vercel project
>   `brycehanscombs-projects/lms`, connected to `github.com/brycehans/lms` for
>   auto-deploy on push).
> - Supabase project ref `fegvvyztbsxcdemuzmiy`.
>
> The reproducible, non-secret hosted setup is captured in
> **`scripts/setup-hosted-supabase.sh`** (schema + seed + auth config). The
> secret bits (Vercel env vars) are documented below but deliberately not
> committed. Section numbers below map to a from-scratch redeploy.

## 1. Stand up a hosted Supabase

1. Create a hosted project at [supabase.com](https://supabase.com) (or
   self-host somewhere with a public URL) and link it:

   ```bash
   supabase link --project-ref <ref>
   supabase login   # stores the Management-API token used by the script below
   ```

2. Run the setup script from the repo root. It is idempotent — safe to re-run —
   and is the source of truth for everything hosted that would otherwise live
   only in the dashboard:

   ```bash
   bash scripts/setup-hosted-supabase.sh
   ```

   It does three things (edit the `PROJECT_REF` / `SITE_URL` at the top for a
   different project):

   - **Schema** — `supabase db push` applies every migration in
     `supabase/migrations/` (tables, RLS, RPCs).
   - **Seed** — runs `supabase/seed.sql` via `supabase db query` (**not**
     `db push --include-seed`). `--include-seed` tracks the seed by content
     hash and *silently skips execution* when the hash already matches, which
     leaves the demo accounts with no password and makes every login fail with
     `invalid_credentials`. `db query` always executes; `seed.sql` opens with
     `delete from auth.users`, so it is a clean deterministic reset.
   - **Auth config** — PATCHes the hosted auth settings via the Management API:
     sets `site_url` + the redirect allow-list to the deploy URL, and enables
     `mailer_autoconfirm` (email confirmation OFF). This mirrors `config.toml`'s
     `enable_confirmations = false`; the app assumes signup logs the user in
     immediately, so hosted must auto-confirm or signup stalls awaiting an
     email. These live in the script (not `config.toml`) because `config.toml`
     stays `localhost` for local dev — do **not** `supabase config push`, it
     would revert the hosted URLs.

   Skip the seed for a *real* production DB (it inserts throwaway demo data);
   it is intended only for the reviewer demo.

## 2. Set env vars in Vercel

These carry secrets, so they are set in Vercel only — not committed. With the
`vercel` CLI linked (`vercel link`), the exact commands are:

```bash
printf '%s' 'https://<ref>.supabase.co'        | vercel env add NEXT_PUBLIC_SUPABASE_URL production
printf '%s' '<publishable-or-anon-key>'        | vercel env add NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY production
printf '%s' 'true'                             | vercel env add NEXT_PUBLIC_DEMO_LOGINS production
printf '%s' '<demo-password>'                  | vercel env add NEXT_PUBLIC_DEMO_PASSWORD production
printf '%s' '<user>:<password>'                | vercel env add DEMO_BASIC_AUTH production
```

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | hosted project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | hosted project publishable / anon key (non-secret by design) |
| `NEXT_PUBLIC_DEMO_LOGINS` | `true` to show the one-click Quick-login panel (demo only) |
| `NEXT_PUBLIC_DEMO_PASSWORD` | shared demo password; must match the password you seed on the host (via the `app.demo_password` GUC). Pick a real value here — never the repo's local-dev default — and don't commit it. |
| `DEMO_BASIC_AUTH` | `user:password` — turns on the site-wide Basic Auth edge gate (see below). Server-only; **no** `NEXT_PUBLIC_` prefix. Keep the value out of the repo, or the gate is pointless. |

`NEXT_PUBLIC_*` values are inlined at **build time**, so set these before the
first production deploy (`vercel --prod`) — changing them later needs a rebuild.

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
- The password is the same for every seeded account and is **env-driven on both
  sides** — no default value is committed:
  - **DB**: `seed.sql` hashes `current_setting('app.demo_password', …)` into
    `auth.users.encrypted_password`, falling back to a throwaway *local-dev*
    value only for `db reset`. On a host, pass a real secret via the GUC.
  - **Client**: `QuickLogin` sends `NEXT_PUBLIC_DEMO_PASSWORD` (no fallback — the
    panel no-ops if it's unset).
  The DB value and `NEXT_PUBLIC_DEMO_PASSWORD` **must match**, or sign-in fails.

### Security posture

This feature deliberately publishes working credentials to anyone who can load
the login page, so it is **only safe behind edge gating**:

- **Never enable it on a public-facing production deploy.** `NEXT_PUBLIC_DEMO_LOGINS`
  must be unset/`false` there, so the panel and the client-side password never
  ship in the bundle.
- For the reviewer demo, we gate access at the edge with a **self-hosted HTTP
  Basic Auth gate** (`proxy.ts`), enabled by the `DEMO_BASIC_AUTH` env var. It
  runs in the middleware before any app code, so an un-authenticated visitor
  never reaches the login page or `/api/**` at all — it plays the same role as
  Vercel Access Protection but needs no paid plan. Set `DEMO_BASIC_AUTH` to a
  `user:password` string and share those with the reviewer.
- The accounts are **seed data only** (throwaway `@example.com` users, no real
  PII), and the password is a throwaway shared secret — treat both as public.
- Because it rides the standard auth flow, it grants **no more than a real login
  would**: RLS still scopes every read, and writes still go through the vetted
  RPCs. Quick-login changes *who can obtain a session*, not *what a session can do*.

### Enabling it on the hosted demo

1. Seed the demo accounts — handled by `scripts/setup-hosted-supabase.sh`
   (see section 1). To use a non-default password, run the seed with the GUC
   set: `PGOPTIONS="-c app.demo_password=yourpw" psql "$HOSTED_DB_URL" -f supabase/seed.sql`.
2. Set `NEXT_PUBLIC_DEMO_LOGINS=true` in Vercel (and `NEXT_PUBLIC_DEMO_PASSWORD`
   to the same password if you overrode the default).
3. Set `DEMO_BASIC_AUTH=user:password` in Vercel **before** enabling the flag, so
   the demo is never reachable un-gated. Verify by loading the deployment: the
   browser should prompt for Basic Auth credentials before any page renders.

## 3. Auth redirect URLs (handled by the setup script)

The signup route handler (`app/api/auth/signup/route.ts`) sets
`emailRedirectTo` from the request's `origin` header, and Supabase rejects
redirects that aren't allow-listed. `scripts/setup-hosted-supabase.sh` sets
`site_url` + the redirect allow-list to the deploy URL for you, so there's no
manual dashboard step. (To do it by hand instead: **Auth → URL Configuration →
Redirect URLs** in the dashboard.)

Because the script also enables `mailer_autoconfirm`, signup logs the user in
immediately and no confirmation email is sent. If you turn confirmations back
on, note that Supabase's built-in SMTP is heavily rate-limited — wire up real
SMTP for anything serious.

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
