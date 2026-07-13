import { SignUpForm } from "@/components/sign-up-form";
import { createClient } from "@/lib/supabase/server";
import { Suspense } from "react";

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

  return <SignUpForm universities={universities} />;
}

export default function Page() {
  return (
    <div className="flex min-h-svh w-full items-center justify-center p-6 md:p-10">
      <div className="w-full max-w-sm">
        <Suspense>
          <SignUp />
        </Suspense>
      </div>
    </div>
  );
}
