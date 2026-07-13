"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { cn, slugify } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import { Avatar } from "@/components/home/Avatar";

/**
 * One-click sign-in for reviewers. Renders ONLY when NEXT_PUBLIC_DEMO_LOGINS is
 * "true" (set it locally and on the hosted deploy you want it on). Every seeded
 * account shares the throwaway password minted in seed.sql, so this just drives
 * the normal signInWithPassword path — no impersonation / service-role backdoor.
 *
 * This is a deliberate demo affordance; keep the real gate at the edge (DB
 * firewalled to the Vercel deployment + Vercel access protection).
 */

// Must match the password seed.sql hashes into the accounts. Both default to
// "prophecy"; override both together (NEXT_PUBLIC_DEMO_PASSWORD + the seed's
// app.demo_password) if you want a different one.
const DEMO_PASSWORD = process.env.NEXT_PUBLIC_DEMO_PASSWORD ?? "prophecy";

// `portrait: true` only for the personas that are travellers (they have a
// /public/travellers/<slug>.webp). The rest fall back to initials — we don't
// pass a src for them, which also avoids a 404 that React's onError would miss
// during the SSR→hydration gap.
const ACCOUNTS = [
  {
    email: "tim.rollins@example.com",
    name: "Tim Rollins",
    role: "Student",
    blurb:
      "Students book consultations and can only see, cancel, or complete their own bookings.",
  },
  {
    email: "amara.okafor@example.com",
    name: "Amara Okafor",
    role: "Student + Traveller",
    portrait: true,
    blurb:
      "Holds both roles at once — books as a student and takes auto-assigned consultations as a traveller.",
  },
  {
    email: "mei.chen@example.com",
    name: "Mei Chen",
    role: "Traveller",
    portrait: true,
    blurb:
      "Travellers appear in the public roster and are auto-assigned to students' bookings; they see only their own sessions.",
  },
  {
    email: "kerry.davies@example.com",
    name: "Kerry Davies",
    role: "Admin · UTS",
    blurb:
      "Admins can see bookings scoped only to the university they administer (here, UTS).",
  },
  {
    email: "bryce.hanscomb@example.com",
    name: "Bryce Hanscomb",
    role: "Superadmin",
    blurb:
      "Superadmins are unscoped — they can see every booking across all universities.",
  },
];

export function QuickLogin({
  className,
  next = "/me",
}: {
  className?: string;
  // Post-login destination; pre-sanitized by the caller (login-form via safeNext).
  next?: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (process.env.NEXT_PUBLIC_DEMO_LOGINS !== "true") return null;

  const login = async (email: string) => {
    setBusy(email);
    setError(null);
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password: DEMO_PASSWORD,
      });
      if (error) {
        setError(error.message);
        return;
      }
      // Refresh so server components re-read the freshly-set auth cookie.
      router.push(next);
      router.refresh();
    } finally {
      // Always clear `busy` — including on the success path. We navigate to /me,
      // but Next's client router cache keeps this just-visited login segment's
      // React tree (state and all); logging out later restores it, so a `busy`
      // left set here would come back stuck on "Signing in…". Clearing in
      // `finally` guarantees the restored tree is idle.
      setBusy(null);
    }
  };

  return (
    <div className={cn("flex flex-col gap-3", className)}>
      <div className="space-y-2">
        <p className="text-sm font-medium">Jump straight in (demo)</p>
        <p className="text-xs text-muted-foreground">
          One-click sign in as a seeded account. This triggers a real
          Supabase-and-GoTrue authorization but obviously is not
          production-grade.
        </p>
      </div>
      <div className="flex flex-col gap-3">
        {ACCOUNTS.map((a) => (
          <div key={a.email} className="flex flex-col gap-1">
            <Button
              type="button"
              variant="outline"
              className="h-auto justify-between py-2"
              disabled={busy !== null}
              onClick={() => login(a.email)}
            >
              <span className="flex min-w-0 items-center gap-2">
                <Avatar
                  name={a.name}
                  src={
                    a.portrait
                      ? `/travellers/${slugify(a.name)}.webp`
                      : undefined
                  }
                  className="size-7 text-[10px]"
                />
                <span className="truncate font-medium">
                  {busy === a.email ? "Signing in…" : a.name}
                </span>
              </span>
              <span className="shrink-0 text-xs text-muted-foreground">
                {a.role}
              </span>
            </Button>
            <p className="px-1 text-xs leading-snug text-muted-foreground">
              {a.blurb}
            </p>
          </div>
        ))}
        <FormMessage>{error}</FormMessage>
      </div>

      {/* divider into the manual email/password form below */}
      <div className="relative py-1 mt-4">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-card px-2 text-muted-foreground">
            or sign in with email
          </span>
        </div>
      </div>
    </div>
  );
}
