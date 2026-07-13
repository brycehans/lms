import type { Metadata } from "next";
import { Suspense } from "react";
import { LoginForm } from "@/components/login-form";
import { BrandMark } from "@/components/BrandMark";

export const metadata: Metadata = {
  title: "Sign in",
};

// Reading `next` from searchParams is dynamic, so it lives in its own Suspense
// child — awaiting it in the page body blocks the whole route under Cache
// Components. The fallback is the same form without a `next`, so there's no
// layout shift while it resolves.
async function LoginCard({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  return <LoginForm className="w-full" next={next} />;
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
        <Suspense fallback={<LoginForm className="w-full" />}>
          <LoginCard searchParams={searchParams} />
        </Suspense>
      </div>
    </div>
  );
}
