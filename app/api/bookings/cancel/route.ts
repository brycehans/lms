import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

/**
 * Cancel one of the caller's own upcoming bookings. The only client-writable
 * surface is the RPC — it re-derives the target from `auth.uid()` + slot and
 * enforces "student-only, still in the future", so nothing here needs its own
 * authz beyond shape validation.
 */
export async function POST(request: Request) {
  let body: { startsAt?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { startsAt } = body;
  if (typeof startsAt !== "string" || !startsAt) {
    return NextResponse.json({ error: "Missing startsAt" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking", {
    p_starts_at: startsAt,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
