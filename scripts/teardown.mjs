// Teardown — return the working tree to fresh-clone state.
//
// Removes everything a clone does NOT ship but that running the app creates:
//   - the local Supabase Docker stack AND its Postgres volumes (seeded db data),
//   - installed dependencies + Next build output,
//   - local env files (a clone has only the tracked .env.example),
//   - Supabase's local caches under supabase/.
//
// It intentionally LEAVES tracked files, plus .claude/ (your local editor/agent
// config) and .vercel/ (deploy link) — those aren't runnable state. Delete them
// by hand if you want a byte-for-byte clean tree.
//
// Usage:
//   pnpm teardown            # confirm, then tear down
//   pnpm teardown --dry-run  # show what would be removed, change nothing
//   pnpm teardown --yes      # skip the confirmation prompt
//   pnpm teardown --keep-env # keep .env / .env.local

import { spawnSync } from "node:child_process";
import { existsSync, rmSync, statSync } from "node:fs";
import { createInterface } from "node:readline/promises";

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run") || args.has("-n");
const assumeYes = args.has("--yes") || args.has("-y");
const keepEnv = args.has("--keep-env");

// Paths to remove, relative to repo root. Ordering doesn't matter here; the
// Supabase stack is stopped separately (and first) because its CLI lives in
// node_modules.
const PATHS = [
  "node_modules",
  ".next",
  "out",
  "build",
  "coverage",
  "next-env.d.ts",
  "tsconfig.tsbuildinfo",
  "supabase/.branches",
  "supabase/.temp",
  "supabase/snippets",
  ...(keepEnv ? [] : [".env", ".env.local"]),
];

const present = PATHS.filter((p) => existsSync(p));

function describe(p) {
  try {
    return statSync(p).isDirectory() ? `${p}/` : p;
  } catch {
    return p;
  }
}

console.log("[teardown] this will restore the tree to fresh-clone state:");
console.log("  • stop the local Supabase stack and DISCARD its db volumes");
if (present.length) {
  console.log("  • delete:");
  for (const p of present) console.log(`      ${describe(p)}`);
} else {
  console.log("  • (no derived files present to delete)");
}
if (keepEnv) console.log("  • keeping .env / .env.local (--keep-env)");
console.log("  • keeping .claude/ and .vercel/ (delete by hand if you want them gone)");

if (dryRun) {
  console.log("\n[teardown] --dry-run: nothing was changed.");
  process.exit(0);
}

if (!assumeYes) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const answer = (await rl.question("\nProceed? [y/N] ")).trim().toLowerCase();
  rl.close();
  if (answer !== "y" && answer !== "yes") {
    console.log("[teardown] aborted.");
    process.exit(0);
  }
}

// 1. Stop the stack + drop volumes. Must run BEFORE node_modules is removed
//    (the supabase CLI lives there). --no-backup discards the db data, which is
//    the point — a fresh clone has no volumes. Failure (e.g. Docker not running,
//    stack already down) is non-fatal; we still clean the filesystem.
console.log("\n[teardown] stopping local Supabase (discarding volumes)…");
if (existsSync("node_modules")) {
  const stop = spawnSync("pnpm", ["exec", "supabase", "stop", "--no-backup"], {
    stdio: "inherit",
  });
  if (stop.status !== 0) {
    console.warn(
      "[teardown] `supabase stop` didn't exit cleanly (Docker down or already stopped?) — continuing.",
    );
  }
} else {
  console.warn(
    "[teardown] node_modules already gone — skipping `supabase stop`.\n" +
      "           If the Docker stack is still up, run `supabase stop --no-backup`\n" +
      "           after `pnpm install`, or stop the containers manually.",
  );
}

// 2. Remove derived files/dirs.
for (const p of present) {
  rmSync(p, { recursive: true, force: true });
  console.log(`[teardown] removed ${describe(p)}`);
}

console.log(
  "\n[teardown] done — tree is at fresh-clone state.\n" +
    "Rehydrate with: pnpm install && pnpm dev",
);
