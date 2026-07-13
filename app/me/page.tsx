import type { Metadata } from "next";
import { Suspense } from "react";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { slugify } from "@/lib/utils";
import { UserPen } from "lucide-react";

import { BrandMark } from "@/components/BrandMark";
import { AuthButton } from "@/components/auth-button";
import { Footer } from "@/components/Footer";
import { Avatar } from "@/components/home/Avatar";
import { SectionHeading } from "@/components/home/SectionHeading";
import { RoleNote } from "@/components/me/RoleNote";
import { ProfileForm } from "@/components/me/ProfileForm";
import { StudentSection } from "@/components/me/StudentSection";
import { TravellerSection } from "@/components/me/TravellerSection";
import { OversightSection } from "@/components/me/OversightSection";
import { sortRoles, type AppRole } from "@/components/me/roles";
import { Badge } from "@/components/ui/badge";

export const metadata: Metadata = {
  title: "Your account",
};

/**
 * The signed-in user's home: identity, an explainer of what their role means,
 * and their bookings rendered per role. Auth-gated — anonymous visitors are
 * bounced to login. Everything below the gate is scoped by RLS, so the page
 * shows only what each persona is allowed to see.
 */
async function MeContent() {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;
  const userId = claims?.sub as string | undefined;
  const email = claims?.email as string | undefined;

  if (!userId) {
    redirect("/auth/login");
  }

  const [{ data: profile }, { data: roleRows }] = await Promise.all([
    supabase
      .from("profiles")
      .select("first_name, last_name")
      .eq("id", userId)
      .maybeSingle(),
    // Relies on the `read_own_roles` self-read policy on user_roles.
    supabase.from("user_roles").select("role").eq("user_id", userId),
  ]);

  const roles = sortRoles((roleRows ?? []).map((r) => r.role as AppRole));
  const firstName = profile?.first_name;
  const fullName = profile
    ? `${profile.first_name} ${profile.last_name}`
    : (email ?? "You");

  const isStudent = roles.includes("student");
  const isTraveller = roles.includes("traveller");
  const isStaff = roles.includes("admin") || roles.includes("superadmin");
  const isSuperadmin = roles.includes("superadmin");

  return (
    <div className="flex flex-col gap-10">
      {/* Identity */}
      <header className="flex items-center gap-4">
        <Avatar
          name={fullName}
          // Travellers reuse their public roster portrait
          // (/public/travellers/<slug>.webp); everyone else falls back to
          // initials. Avatar degrades to initials if the portrait is absent.
          src={isTraveller ? `/travellers/${slugify(fullName)}.webp` : undefined}
          className="size-16 text-lg"
        />
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold leading-tight">
            {firstName ? `Welcome back, ${firstName}` : "Welcome back"}
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">{fullName}</p>
          <span className="space-x-2">
            {isStudent && <Badge>Student</Badge>}
            {isTraveller && <Badge>Time Traveller</Badge>}
            {isStaff && <Badge>Administrator</Badge>}
            {isSuperadmin && <Badge>Super-Admin</Badge>}
          </span>
        </div>
      </header>

      <RoleNote roles={roles} />

      {/* Profile edit — kept above the bookings so it stays reachable without
          scrolling past a long list. Only shown once we have a profile row to
          prefill from. */}
      {profile && (
        <section className="space-y-4">
          <SectionHeading icon={UserPen} title="Your profile" />
          <p className="text-sm text-muted-foreground">
            Update the name on your account. This won&apos;t change the name on
            bookings you&apos;ve already made.
          </p>
          <ProfileForm
            defaultFirstName={profile.first_name}
            defaultLastName={profile.last_name}
          />
        </section>
      )}

      {isStudent && (
        <Suspense fallback={<SectionSkeleton />}>
          <StudentSection userId={userId} />
        </Suspense>
      )}

      {isTraveller && (
        <Suspense fallback={<SectionSkeleton />}>
          <TravellerSection userId={userId} />
        </Suspense>
      )}

      {isStaff && (
        <Suspense fallback={<SectionSkeleton />}>
          <OversightSection isSuperadmin={isSuperadmin} />
        </Suspense>
      )}
    </div>
  );
}

function SectionSkeleton() {
  return <div className="h-24 animate-pulse rounded-xl border bg-muted/30" />;
}

export default function MePage() {
  return (
    <main className="min-h-screen flex flex-col items-center">
      <div className="flex-1 w-full flex flex-col items-center">
        <nav className="w-full flex justify-center border-b border-b-foreground/10 h-16">
          <div className="w-full max-w-5xl flex justify-between items-center p-3 px-5 text-sm">
            <BrandMark />
            <Suspense>
              <AuthButton />
            </Suspense>
          </div>
        </nav>

        <div className="flex-1 w-full max-w-3xl p-5 py-12">
          <Suspense fallback={<div className="h-64" />}>
            <MeContent />
          </Suspense>
        </div>

        <Footer />
      </div>
    </main>
  );
}
