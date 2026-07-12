import { EnvVarWarning } from "@/components/env-var-warning";
import { AuthButton } from "@/components/auth-button";
import { ConnectSupabaseSteps } from "@/components/tutorial/connect-supabase-steps";
import { SignUpUserSteps } from "@/components/tutorial/sign-up-user-steps";
import { hasEnvVars } from "@/lib/utils";
import { Suspense } from "react";
import { Footer } from "@/components/Footer";
import { Button, buttonVariants } from "@/components/ui/button";
import AvailableTimes from "@/components/AvailableTimes";

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center">
      <div className="flex-1 w-full flex flex-col gap-20 items-center">
        <nav className="w-full flex justify-center border-b border-b-foreground/10 h-16">
          <div className="w-full max-w-5xl flex justify-between items-center p-3 px-5 text-sm">
            <div className="flex gap-5 items-center font-semibold"></div>
            {!hasEnvVars ? (
              <EnvVarWarning />
            ) : (
              <Suspense>
                <AuthButton />
              </Suspense>
            )}
          </div>
        </nav>
        <div className="flex-1 flex flex-col gap-20 max-w-5xl p-5">
          <main className="flex-1 flex flex-col gap-6 px-4">
            <section className="text-center space-y-4">
              <h1 className="text-5xl">Course Prophecies</h1>
              <p>
                Discover what grade you got for Uni from a certified time
                traveller
              </p>
            </section>
            <AvailableTimes />
            <p>
              <a href="/book" className={buttonVariants()}>
                Book now
              </a>
            </p>
          </main>
        </div>

        <Footer />
      </div>
    </main>
  );
}
