import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

/**
 * Move one of the caller's own upcoming bookings to a new slot. The RPC keeps
 * the assigned traveller and every other column frozen — only `starts_at`
 * changes — and re-runs the availability/busy checks against the new slot. The
 * `p_new_start` argument is typed to the `is_bookable_start_time` domain in the
 * DB, so a non-bookable time is rejected by the type system, not app code.
 */
export async function POST(request: Request) {
  let body: { currentStart?: unknown; newStart?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { currentStart, newStart } = body;
  if (typeof currentStart !== "string" || !currentStart) {
    return NextResponse.json({ error: "Missing currentStart" }, { status: 400 });
  }
  if (typeof newStart !== "string" || !newStart) {
    return NextResponse.json({ error: "Missing newStart" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("reschedule_booking", {
    p_current_start: currentStart,
    p_new_start: newStart,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
