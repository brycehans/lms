import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

/**
 * Update the caller's own profile name. The only client-writable surface is the
 * RPC — `update_profile` targets `auth.uid()` and rejects blank names, so
 * nothing here needs its own authz beyond shape validation.
 *
 * Note this changes only the profile row; bookings freeze their own name
 * snapshot at creation, so a rename here never rewrites booking history.
 */
export async function POST(request: Request) {
  let body: { firstName?: unknown; lastName?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { firstName, lastName } = body;
  if (typeof firstName !== "string" || typeof lastName !== "string") {
    return NextResponse.json({ error: "Missing name" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_profile", {
    p_first_name: firstName,
    p_last_name: lastName,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
