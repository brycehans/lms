export type BookingStatus = "upcoming" | "past" | "completed" | "cancelled";

/**
 * Human labels for each lifecycle state, shared by the card badge and the
 * status filter so the two never drift apart.
 */
export const STATUS_LABEL: Record<BookingStatus, string> = {
  upcoming: "Upcoming",
  past: "Awaiting completion",
  completed: "Completed",
  cancelled: "Cancelled",
};

// The order statuses are offered in the filter (and grouped by lifecycle sort).
export const STATUS_ORDER: BookingStatus[] = [
  "upcoming",
  "past",
  "completed",
  "cancelled",
];

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
  b: {
    starts_at: string;
    cancelled_at: string | null;
    completed_at: string | null;
  },
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

/** The ways the interactive booking list can be ordered. */
export type SortMode = "lifecycle" | "soonest" | "latest";

export const SORT_LABEL: Record<SortMode, string> = {
  lifecycle: "Upcoming first",
  soonest: "Date (soonest)",
  latest: "Date (latest)",
};

/**
 * Client-side ordering for the interactive list, keyed off the same fields the
 * list carries. "lifecycle" is the default: upcoming bookings first (soonest at
 * the top), then everything settled (past/completed/cancelled) newest-first.
 * The others are a plain chronological sort in either direction.
 */
export function sortBookings<
  T extends { startsAt: string; status: BookingStatus },
>(items: T[], mode: SortMode): T[] {
  const time = (iso: string) => new Date(iso).getTime();
  return [...items].sort((a, b) => {
    if (mode === "soonest") return time(a.startsAt) - time(b.startsAt);
    if (mode === "latest") return time(b.startsAt) - time(a.startsAt);
    // lifecycle
    const ga = a.status === "upcoming" ? 0 : 1;
    const gb = b.status === "upcoming" ? 0 : 1;
    if (ga !== gb) return ga - gb;
    return ga === 0
      ? time(a.startsAt) - time(b.startsAt)
      : time(b.startsAt) - time(a.startsAt);
  });
}
