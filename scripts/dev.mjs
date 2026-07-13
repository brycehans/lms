// Local dev launcher — makes `pnpm dev` adaptive to whatever ports the local
// Supabase stack actually binds, so a clone "just works" without hand-editing
// env files, and a port change only needs to happen in supabase/config.toml.
//
// It:
//   1. boots the local Supabase stack (idempotent — fast if already running),
//   2. reads the URL + publishable key the running stack reports,
//   3. starts `next dev` wired to those values.
//
// Precedence: anything you set explicitly in the shell or .env.local wins — the
// derived local values only fill the gaps. So to point the local app at a
// hosted Supabase, just set NEXT_PUBLIC_SUPABASE_URL in .env.local.
//
// This runs only for `pnpm dev`. Production (Vercel) uses `next build` + the
// dashboard env vars, and never touches this file.

import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

/** Minimal KEY=VALUE parser for .env files (quotes stripped, # comments ignored). */
function parseEnvFile(path) {
  if (!existsSync(path)) return {};
  const out = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!m || line.trim().startsWith("#")) continue;
    let v = m[2].trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    out[m[1]] = v;
  }
  return out;
}

const supabase = ["exec", "supabase"];

// 1. Boot the stack.
console.log("[dev] starting local Supabase…");
const started = spawnSync("pnpm", [...supabase, "start"], { stdio: "inherit" });
if (started.status !== 0) {
  console.error(
    "\n[dev] `supabase start` failed.\n" +
      "If this is a port conflict, change the clashing port in supabase/config.toml\n" +
      "(defaults: API 54321, db 54322, studio 54323, plus 54320/54324/54329). You\n" +
      "only need to edit it there — the app follows whatever the stack reports.\n",
  );
  process.exit(started.status ?? 1);
}

// 2. Read what the running stack is actually using.
const status = spawnSync("pnpm", [...supabase, "status", "-o", "env"], {
  encoding: "utf8",
});
if (status.status !== 0) {
  console.error(status.stderr || "[dev] `supabase status` failed.");
  process.exit(status.status ?? 1);
}
const reported = Object.fromEntries(
  status.stdout
    .split("\n")
    .map((l) => l.match(/^([A-Z0-9_]+)="?(.*?)"?$/))
    .filter(Boolean)
    .map((m) => [m[1], m[2]]),
);

// 3. Resolve config. Explicit (shell > .env.local > .env) wins; derived fills gaps.
const explicit = {
  ...parseEnvFile(".env"),
  ...parseEnvFile(".env.local"),
  ...process.env,
};
const derived = {
  NEXT_PUBLIC_SUPABASE_URL: reported.API_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: reported.PUBLISHABLE_KEY,
  // Local-dev demo defaults (reviewer quick-login). Override in .env.local.
  // The password must match seed.sql's local-only fallback so seeded accounts
  // are loggable; it is a throwaway LOCAL value, not any hosted secret.
  NEXT_PUBLIC_DEMO_LOGINS: "true",
  NEXT_PUBLIC_DEMO_PASSWORD: "localdev",
};
for (const [k, v] of Object.entries(derived)) {
  if (v && !explicit[k]) process.env[k] = v;
}

console.log(`[dev] app → Supabase at ${explicit.NEXT_PUBLIC_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL}`);

// 4. Hand off to next dev on a FIXED, uncommon port (1955). We deliberately
// forgo Next's default port fallback: the app's URL is baked into the auth
// redirect allow-list in supabase/config.toml (site_url / additional_redirect_urls),
// so a moved port would silently desync those. A fixed uncommon port is unlikely
// to clash on a fresh machine; if it does, override with `pnpm dev -p <port>` or
// PORT=<port> (and update config.toml to match if you rely on auth redirects).
const APP_PORT = "1955";
const passthrough = process.argv.slice(2);
const hasPortFlag = passthrough.some(
  (a) => a === "-p" || a === "--port" || a.startsWith("--port="),
);
const portArgs = hasPortFlag || process.env.PORT ? [] : ["-p", APP_PORT];

const next = spawn("pnpm", ["exec", "next", "dev", ...portArgs, ...passthrough], {
  stdio: "inherit",
  env: process.env,
});
next.on("exit", (code) => process.exit(code ?? 0));
