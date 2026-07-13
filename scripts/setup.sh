#!/usr/bin/env bash
#
# One-command spinup for a fresh clone: prerequisites -> deps -> a fully seeded
# local Supabase stack -> the dev server.
#
# Run it WITHOUT pnpm — that's the point: it verifies pnpm (and Docker/node) are
# present and reports a clear install pointer if not, so it can't be `pnpm <x>`.
#
#   ./scripts/setup.sh          # or: bash scripts/setup.sh
#
# Idempotent and safe to re-run: `supabase db reset` brings the local db to the
# known demo state every time (drops, re-applies every migration, re-runs
# seed.sql).
#
# This script is LOCAL-only. For a hosted deploy see deploy-prep.md and
# scripts/setup-hosted-supabase.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

# --- 1. Prerequisites ----------------------------------------------------------
# Fail fast with a human message: a missing/stopped Docker or absent pnpm is the
# common fresh-clone snag, and the raw errors the tools throw are cryptic.
echo "==> Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "    ERROR: Docker is required — install Docker Desktop and retry." >&2; exit 1; }
docker info       >/dev/null 2>&1 || { echo "    ERROR: Docker isn't running — start Docker Desktop and retry." >&2; exit 1; }
command -v node   >/dev/null 2>&1 || { echo "    ERROR: Node.js is required (see .nvmrc — 24)." >&2; exit 1; }
command -v pnpm   >/dev/null 2>&1 || { echo "    ERROR: pnpm is required — https://pnpm.io/installation (e.g. 'npm i -g pnpm')." >&2; exit 1; }

# --- 2. Dependencies -----------------------------------------------------------
echo "==> Installing dependencies"
pnpm install --frozen-lockfile

# No .env.local step: local dev needs no Supabase config. `pnpm dev` (dev.mjs)
# derives the URL + publishable key live from the running stack and defaults the
# demo flags. Copy .env.example to .env.local by hand only to override a default
# (e.g. point at a hosted Supabase) — see that file's comments.

# --- 3. Local Supabase: boot + deterministic seed ------------------------------
# `start` boots the stack (first run pulls Docker images — can take a few
# minutes). `db reset` then guarantees migrations + seed regardless of whether a
# stale volume already exists — a plain `start` only seeds a brand-new volume,
# which is the classic "why is the roster empty?" trap on a re-clone.
echo "==> Starting local Supabase (first run pulls images — be patient)"
pnpm exec supabase start
echo "==> Applying migrations + seed (deterministic demo data)"
pnpm exec supabase db reset

# --- 4. Run --------------------------------------------------------------------
# Hand off to the dev launcher (scripts/dev.mjs): it re-checks Supabase (a fast
# no-op now), wires the app to the stack's reported URL/key, and starts Next.
# exec so Ctrl-C stops Next cleanly; Supabase keeps running in the background.
echo "==> Launching the app — http://localhost:3000"
exec pnpm dev
