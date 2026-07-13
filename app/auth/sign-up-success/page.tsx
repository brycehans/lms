import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { CheckCircle2 } from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { buttonVariants } from "@/components/ui/button";
import { BrandMark } from "@/components/BrandMark";
import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/utils";

export const metadata: Metadata = {
  title: "Account created",
};

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

// Presentational card. `continuing` = the visitor arrived from a booking
// deep-link (`?next=`), so the CTA carries them straight back to it.
function SuccessCard({
  continuing,
  dest,
}: {
  continuing: boolean;
  dest: string;
}) {
  return (
    <div className="flex w-full flex-col gap-6">
      <Card>
        <CardHeader>
          <span className="mb-1 inline-flex size-11 items-center justify-center rounded-full bg-primary/10 text-primary">
            <CheckCircle2 size={24} />
          </span>
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
            {continuing
              ? "You're all set — let's finish booking your consultation."
              : "You're ready to book a consultation with a time traveller."}
          </p>
          <Link href={continuing ? dest : "/"} className={buttonVariants()}>
            {continuing ? "Continue your booking" : "Get started"}
          </Link>
        </CardContent>
      </Card>
    </div>
  );
}

// Reading `next` is dynamic, so resolve it inside a Suspense child rather than in
// the page body (which would block the whole route under Cache Components).
async function ResolvedCard({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  // safeNext only yields "/me" for a missing/unsafe value, so anything else is a
  // real deep-link (the booking slot that sent them here) worth continuing to.
  const dest = safeNext(next);
  return <SuccessCard continuing={dest !== "/me"} dest={dest} />;
}

export default function Page({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  return (
    <div className="flex min-h-svh w-full items-center justify-center bg-gradient-to-b from-accent/50 to-background p-6 md:p-10">
      <div className="flex w-full max-w-sm flex-col items-center gap-6">
        <BrandMark />
        <Suspense fallback={<SuccessCard continuing={false} dest="/" />}>
          <ResolvedCard searchParams={searchParams} />
        </Suspense>
      </div>
    </div>
  );
}
