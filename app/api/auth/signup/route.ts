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
    return NextResponse.json(
      { error: "Invalid request body" },
      { status: 400 },
    );
  }

  const { email, password, firstName, lastName, universityId } = body;

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
    return NextResponse.json(
      { error: "Missing required fields" },
      { status: 400 },
    );
  }

  const supabase = await createClient();

  // universityId is only checked for shape above — confirm it names a real,
  // non-deleted university before trusting it. The public_read_universities
  // RLS policy hides soft-deleted rows, and anon can read the granted id
  // column. A malformed (non-uuid) value surfaces as a query error and is
  // treated as invalid too. Guards against a forged/stale id, since nothing
  // downstream enforces it yet.
  const { data: university, error: universityError } = await supabase
    .from("universities")
    .select("id")
    .eq("id", universityId)
    .maybeSingle();

  if (universityError || !university) {
    return NextResponse.json(
      { error: "Invalid university selection" },
      { status: 400 },
    );
  }

  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
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
