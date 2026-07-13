#!/usr/bin/env bash
#
# Reproducible, idempotent setup of the HOSTED Supabase project for the demo.
#
# This is the source of truth for the parts of the hosted setup that otherwise
# live only as ephemeral dashboard / Management-API state. Re-running it brings a
# hosted project back to the known demo state. It touches ONLY non-secret config
# (schema, seed, and public auth URLs), so it is safe to commit and to run again.
#
# Prerequisites:
#   - `supabase` CLI linked to the project (`supabase link --project-ref <ref>`)
#     and logged in. The Management-API token is read from SUPABASE_ACCESS_TOKEN
#     if set, otherwise from the macOS keychain (where `supabase login` stores it).
#   - Run from the repo root: `bash scripts/setup-hosted-supabase.sh`
#
# What it does NOT do (deliberately):
#   - Set Vercel env vars — those include secrets (the Basic Auth gate
#     credential, the demo password) and must not live in a public repo. See
#     deploy-prep.md for the exact `vercel env add` commands.
#   - Enable the quick-login panel — that is the NEXT_PUBLIC_DEMO_LOGINS Vercel
#     flag, also in deploy-prep.md.

set -euo pipefail

# --- Config (edit these for a different project / deployment) ------------------
PROJECT_REF="fegvvyztbsxcdemuzmiy"
# The hosted app's canonical URL. Used as Supabase's auth redirect base.
SITE_URL="https://lms-zeta-lyart.vercel.app"
# Preview/deployment URLs also allowed to complete auth redirects (password
# reset, OAuth). The wildcard covers Vercel's per-deployment hostnames.
REDIRECT_ALLOW_LIST="${SITE_URL}/**,https://*-brycehanscombs-projects.vercel.app/**"

cd "$(dirname "$0")/.."

# --- 1. Schema -----------------------------------------------------------------
# Applies every migration not yet on the remote history table.
echo "==> Pushing migrations"
pnpm exec supabase db push --linked --yes

# --- 2. Seed -------------------------------------------------------------------
# IMPORTANT: use `db query`, not `db push --include-seed`. The latter tracks the
# seed by content-hash and SKIPS execution when the hash already matches — which
# silently leaves the demo accounts without the crypt('prophecy', ...) password
# and makes every login fail with `invalid_credentials`. `db query` always runs
# the file, and seed.sql opens with `delete from auth.users` so it is a clean,
# deterministic reset every time.
echo "==> Seeding (forced execution)"
pnpm exec supabase db query --linked -f supabase/seed.sql >/dev/null
echo "    seeded"

# --- 3. Auth config ------------------------------------------------------------
# site_url / redirect list are environment-specific, so they live here rather
# than in config.toml (which stays localhost for local dev). mailer_autoconfirm
# mirrors config.toml's `enable_confirmations = false`: the app assumes signup
# leaves the user logged in immediately (no confirmation email), so hosted must
# auto-confirm too — otherwise signup silently stalls awaiting an email.
echo "==> Configuring hosted auth (site_url, redirect allow-list, auto-confirm)"
TOKEN="${SUPABASE_ACCESS_TOKEN:-$(security find-generic-password -s 'Supabase CLI' -w 2>/dev/null || true)}"
if [ -z "${TOKEN:-}" ]; then
  echo "    ERROR: no Supabase access token. Set SUPABASE_ACCESS_TOKEN or run 'supabase login'." >&2
  exit 1
fi
curl -fsS -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -d "{\"site_url\":\"${SITE_URL}\",\"mailer_autoconfirm\":true,\"uri_allow_list\":\"${REDIRECT_ALLOW_LIST}\"}" \
  >/dev/null
echo "    auth configured"

echo "==> Hosted Supabase setup complete."
