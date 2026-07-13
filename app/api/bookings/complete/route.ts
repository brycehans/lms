import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

/**
 * Toggle the completion flag on one of the caller's own bookings. The RPC
 * enforces student-ownership, rejects cancelled bookings, and only allows
 * completing a session whose start time is in the past.
 */
export async function POST(request: Request) {
  let body: { bookingId?: unknown; isComplete?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { bookingId, isComplete } = body;
  if (typeof bookingId !== "string" || !bookingId) {
    return NextResponse.json({ error: "Missing bookingId" }, { status: 400 });
  }
  if (typeof isComplete !== "boolean") {
    return NextResponse.json({ error: "Missing isComplete" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_booking_completion", {
    p_booking_id: bookingId,
    p_is_complete: isComplete,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
