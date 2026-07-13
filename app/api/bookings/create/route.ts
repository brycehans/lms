import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

/**
 * Create a booking for the caller (a student) at a chosen slot. The RPC is the
 * only client-writable surface: it assigns a random free traveller, takes the
 * per-slot advisory lock, re-checks availability/business-hours, and snapshots
 * the passed names + enrolled university onto the row. `p_starts_at` is typed to
 * the `is_bookable_start_time` domain in the DB, so a non-bookable time is
 * rejected by the type system, not app code.
 *
 * Names come from the form (prefilled from the profile but editable), so we pass
 * them through rather than letting the RPC re-read the profile — this is what
 * lets a student correct the name that gets frozen onto this one booking.
 */
export async function POST(request: Request) {
  let body: {
    startsAt?: unknown;
    firstName?: unknown;
    lastName?: unknown;
    reason?: unknown;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { startsAt, firstName, lastName, reason } = body;
  if (typeof startsAt !== "string" || !startsAt) {
    return NextResponse.json({ error: "Missing startsAt" }, { status: 400 });
  }
  if (typeof firstName !== "string" || !firstName.trim()) {
    return NextResponse.json({ error: "Missing first name" }, { status: 400 });
  }
  if (typeof lastName !== "string" || !lastName.trim()) {
    return NextResponse.json({ error: "Missing last name" }, { status: 400 });
  }
  if (typeof reason !== "string" || !reason.trim()) {
    return NextResponse.json({ error: "Missing reason" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_booking", {
    p_starts_at: startsAt,
    p_reason: reason.trim(),
    p_first_name: firstName.trim(),
    p_last_name: lastName.trim(),
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
