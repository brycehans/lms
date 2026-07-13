export type BookingStatus = "upcoming" | "past" | "completed" | "cancelled";

/**
 * Derive a booking's lifecycle state from its timestamps. Order matters:
 * a cancelled booking is cancelled even if it was previously completed, and a
 * completed booking outranks the plain "past" bucket. Everything else is
 * "upcoming" (starts in the future) or "past" (started, not yet completed).
 *
 * `now` is injected so a server component can compute this once and hand the
 * result to a client child as a plain prop — avoiding a clock read during
 * hydration (which would risk an SSR/client mismatch).
 */
export function bookingStatus(
  b: { starts_at: string; cancelled_at: string | null; completed_at: string | null },
  now: number,
): BookingStatus {
  if (b.cancelled_at) return "cancelled";
  if (b.completed_at) return "completed";
  return new Date(b.starts_at).getTime() > now ? "upcoming" : "past";
}

const slotFmt = new Intl.DateTimeFormat("en-AU", {
  timeZone: "Australia/Melbourne",
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "numeric",
  minute: "2-digit",
});

/** Human slot label in Melbourne wall-clock, e.g. "Mon 14 Jul, 9:00 am". */
export function formatSlot(iso: string): string {
  return slotFmt.format(new Date(iso));
}

/**
 * List ordering shared by every section: upcoming bookings first (soonest at
 * the top), then everything settled (past/completed/cancelled) newest-first.
 */
export function sortByLifecycle<T extends { starts_at: string; status: BookingStatus }>(
  items: T[],
): T[] {
  return [...items].sort((a, b) => {
    const ga = a.status === "upcoming" ? 0 : 1;
    const gb = b.status === "upcoming" ? 0 : 1;
    if (ga !== gb) return ga - gb;
    const ta = new Date(a.starts_at).getTime();
    const tb = new Date(b.starts_at).getTime();
    return ga === 0 ? ta - tb : tb - ta;
  });
}
