import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/utils";
import { type EmailOtpType } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { type NextRequest } from "next/server";

// Send OTP-confirmation errors to the same error page, with the message safely
// URL-encoded so it can't break out of the query string or inject markup.
function errorRedirect(message: string): never {
  redirect(`/auth/error?error=${encodeURIComponent(message)}`);
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const token_hash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  // Sanitize the caller-supplied redirect: safeNext only yields a same-origin,
  // path-absolute target (falling back to /me), closing the open redirect.
  const next = safeNext(searchParams.get("next"));

  if (token_hash && type) {
    const supabase = await createClient();

    const { error } = await supabase.auth.verifyOtp({
      type,
      token_hash,
    });
    if (!error) {
      // redirect user to the (sanitized) destination
      redirect(next);
    } else {
      // redirect the user to an error page with some instructions
      errorRedirect(error.message);
    }
  }

  // redirect the user to an error page with some instructions
  errorRedirect("No token hash or type");
}
