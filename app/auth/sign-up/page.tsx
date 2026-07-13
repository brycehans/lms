import type { Metadata } from "next";
import { SignUpForm } from "@/components/sign-up-form";
import { BrandMark } from "@/components/BrandMark";
import { createClient } from "@/lib/supabase/server";
import { Suspense } from "react";

export const metadata: Metadata = {
  title: "Create your account",
};

async function SignUp() {
  const supabase = await createClient();

  const { data: universities, error } = await supabase
    .from("universities")
    .select("id, name")
    .order("name");

  // Fail loudly rather than rendering an empty dropdown: without universities
  // the sign-up form can't be completed, so a read error is unrecoverable here.
  if (error) {
    throw new Error(`Failed to load universities: ${error.message}`);
  }

  return <SignUpForm universities={universities} className="w-full" />;
}

export default function Page() {
  return (
    <div className="flex min-h-svh w-full items-center justify-center bg-gradient-to-b from-accent/50 to-background p-6 md:p-10">
      <div className="flex w-full max-w-sm flex-col items-center gap-6">
        <BrandMark />
        <Suspense>
          <SignUp />
        </Suspense>
      </div>
    </div>
  );
}
