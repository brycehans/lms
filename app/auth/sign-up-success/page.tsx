import Link from "next/link";
import { Suspense } from "react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { buttonVariants } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/server";

// Reads dynamic (cookie-backed) auth data, so it lives behind a <Suspense>
// boundary — otherwise awaiting it here blocks the whole route from streaming.
async function GreetingName() {
  const supabase = await createClient();

  // TRADEOFF OPPORTUNITY!
  // With email confirmations off, signup leaves the user logged in. The name
  // they entered rides in the JWT's user_metadata, so we can greet them without a DB round-trip.
  // downside is the kinda yucky lookup on FE instead of using useUser() or whatever
  const { data } = await supabase.auth.getClaims();
  const firstName = data?.claims?.user_metadata?.first_name as
    string | undefined;

  return firstName ? `, ${firstName}` : null;
}

export default function Page() {
  return (
    <div className="flex min-h-svh w-full items-center justify-center p-6 md:p-10">
      <div className="w-full max-w-sm">
        <div className="flex flex-col gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-2xl">
                Thanks
                <Suspense fallback={null}>
                  <GreetingName />
                </Suspense>
                !
              </CardTitle>
              <CardDescription>Your account is ready</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <p className="text-sm text-muted-foreground">
                You&apos;re ready to book a consultation with a time traveller.
              </p>
              <Link href="/book" className={buttonVariants()}>
                Get started
              </Link>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
