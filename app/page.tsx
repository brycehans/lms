import { Suspense } from "react";
import { AuthButton } from "@/components/auth-button";
import { createClient } from "@/lib/supabase/server";
import { Footer } from "@/components/Footer";
import { buttonVariants } from "@/components/ui/button";
import { ProfileSummary } from "@/components/home/ProfileSummary";
import { UpcomingBookings } from "@/components/home/UpcomingBookings";
import { AvailabilityCalendar } from "@/components/home/AvailabilityCalendar";
import { UniversitiesList } from "@/components/home/UniversitiesList";
import { TravellerIndex } from "@/components/home/TravellerIndex";
import { BrandMark } from "@/components/BrandMark";
import { Starfield } from "@/components/home/Starfield";
import { HowItWorks } from "@/components/HowItWorks";
import { MoonStar, Sparkles, ArrowBigDown } from "lucide-react";

/**
 * The identity + upcoming-bookings sections read auth cookies (uncached), so
 * they live behind their own Suspense boundary — with Cache Components on, a
 * top-level `await getClaims()` in the page would block the whole route.
 * Renders nothing for anonymous visitors.
 */
async function AccountSections() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  const userId = claims?.sub as string | undefined;
  const email = claims?.email as string | undefined;

  if (!userId) return null;

  return (
    <>
      <ProfileSummary userId={userId} email={email} />
      <UpcomingBookings userId={userId} />
    </>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center overflow-x-clip">
      <div className="flex-1 w-full flex flex-col items-center">
        <nav className="sticky top-0 z-50 w-full flex justify-center border-b border-b-foreground/10 h-16 bg-background/80 backdrop-blur-sm">
          <div className="w-full max-w-5xl flex justify-between items-center p-3 px-5 text-sm">
            <BrandMark />
            <Suspense>
              <AuthButton />
            </Suspense>
          </div>
        </nav>

        {/* Hero — soft green night sky with a scattered starfield */}
        <section className="relative w-full flex justify-center overflow-hidden bg-gradient-to-b from-accent/70 via-background to-background border-b border-b-foreground/5">
          <Starfield />
          <div className="relative w-full max-w-5xl px-5 py-24">
            <div className="flex flex-col items-center gap-6 text-center">
              <h1 className="text-5xl md:text-6xl font-bold tracking-tight text-foreground">
                Course Prophecies
              </h1>
              <p className="max-w-2xl text-lg text-muted-foreground">
                Stop guessing your final grade. Book a one-hour consultation
                with a certified time traveller who&apos;ll gaze into your exam
                results and tell you exactly what you scored.
              </p>
              <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
                <a
                  href="#availability-calendar"
                  className={buttonVariants({ size: "lg" })}
                >
                  <ArrowBigDown size={18} />
                  Book a consultation
                </a>
              </div>
            </div>
          </div>
        </section>

        <div className="flex flex-col gap-16 w-full max-w-5xl p-5 py-12">
          <HowItWorks />

          <Suspense>
            <AccountSections />
          </Suspense>

          <Suspense>
            <AvailabilityCalendar />
          </Suspense>

          <Suspense>
            <div id="universities" className="hash-target">
              <UniversitiesList />
            </div>
          </Suspense>

          <Suspense>
            <TravellerIndex />
          </Suspense>
        </div>

        <Footer />
      </div>
    </main>
  );
}
