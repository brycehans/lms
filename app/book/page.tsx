import type { Metadata } from "next";
import { Suspense } from "react";
import { redirect } from "next/navigation";
import Link from "next/link";

import { createClient } from "@/lib/supabase/server";
import { BrandMark } from "@/components/BrandMark";
import { AuthButton } from "@/components/auth-button";
import { Footer } from "@/components/Footer";
import { buttonVariants } from "@/components/ui/button";
import { BookingForm } from "@/components/book/BookingForm";

export const metadata: Metadata = {
  title: "Book a consultation",
};

/**
 * Auth-gated booking page. We read the caller's profile name here (server side,
 * scoped by RLS) purely to PREFILL the form — the names the student actually
 * confirms are posted back and snapshotted by `create_booking`, so a rename here
 * changes only this booking, never the profile.
 */
async function BookContent({
  searchParams,
}: {
  searchParams: Promise<{ start_at?: string }>;
}) {
  // Awaiting searchParams (and the auth cookie) happens INSIDE this Suspense
  // boundary — doing it at the page top would block the whole route from
  // streaming under Cache Components.
  const { start_at: initialStart } = await searchParams;

  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub as string | undefined;

  if (!userId) {
    // Bounce anonymous visitors, but remember the slot they were trying to book:
    // `next` round-trips through login (see safeNext + login-form) so they land
    // back on this exact deep-link once signed in.
    const here = initialStart
      ? `/book?start_at=${encodeURIComponent(initialStart)}`
      : "/book";
    redirect(`/auth/login?next=${encodeURIComponent(here)}`);
  }

  const [{ data: profile }, { data: roleRows }] = await Promise.all([
    supabase
      .from("profiles")
      .select("first_name, last_name")
      .eq("id", userId)
      .maybeSingle(),
    // Relies on the `read_own_roles` self-read policy on user_roles.
    supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", userId)
      .eq("role", "student"),
  ]);

  // Only students can book. `create_booking` enforces this server-side (no
  // enrolment → rejected); this is the friendly front door so a traveller/admin
  // who follows a deep-link isn't handed a form that can only fail.
  const isStudent = (roleRows ?? []).length > 0;
  if (!isStudent) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-2xl font-semibold leading-tight">
          Booking is for students
        </h1>
        <p className="text-sm text-muted-foreground">
          Consultations can only be booked from a student account. Your account
          doesn&apos;t hold a student role, so there&apos;s nothing to book here.
        </p>
        <Link href="/me" className={buttonVariants({ className: "w-fit" })}>
          Back to my account
        </Link>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <header>
        <h1 className="text-2xl font-semibold leading-tight">
          Book a consultation
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Pick a time and a certified time traveller will be assigned to gaze
          into your results.
        </p>
      </header>

      <BookingForm
        initialStart={initialStart}
        defaultFirstName={profile?.first_name ?? ""}
        defaultLastName={profile?.last_name ?? ""}
      />
    </div>
  );
}

export default function BookPage({
  searchParams,
}: {
  searchParams: Promise<{ start_at?: string }>;
}) {
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

        <div className="flex-1 w-full max-w-2xl p-5 py-12">
          <Suspense fallback={<div className="h-64" />}>
            <BookContent searchParams={searchParams} />
          </Suspense>
        </div>

        <Footer />
      </div>
    </main>
  );
}
