import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

type SignUpRequestBody = {
  email?: unknown;
  password?: unknown;
  firstName?: unknown;
  lastName?: unknown;
  universityId?: unknown;
};

export async function POST(request: Request) {
  let body: SignUpRequestBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { email, password, firstName, lastName, universityId } = body;

  // Re-validate on the server — the client's react-hook-form rules are for UX
  // only and cannot be trusted.
  if (
    typeof email !== "string" ||
    typeof password !== "string" ||
    typeof firstName !== "string" ||
    typeof lastName !== "string" ||
    typeof universityId !== "string" ||
    !email ||
    !password ||
    !firstName ||
    !lastName ||
    !universityId
  ) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  // The browser sends its origin on the fetch; fall back to the configured site
  // URL so the confirmation email links somewhere valid.
  const origin =
    request.headers.get("origin") ?? process.env.NEXT_PUBLIC_SITE_URL;

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: origin ? `${origin}/protected` : undefined,
      // Keys must be snake_case: the handle_new_user trigger reads
      // raw_user_meta_data ->> 'first_name' / 'last_name' to seed the profile.
      // NOTE: university_id is carried here too, but nothing consumes it yet —
      // enrolment (student_enrolments row + student role) still needs a backend
      // path. See the handoff note.
      data: {
        first_name: firstName,
        last_name: lastName,
        university_id: universityId,
      },
    },
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ ok: true });
}
