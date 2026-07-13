import { createClient } from "@/lib/supabase/server";
import { Card, CardContent } from "@/components/ui/card";
import { CalendarCheck, CalendarClock } from "lucide-react";
import { SectionHeading } from "./SectionHeading";

const slotFmt = new Intl.DateTimeFormat("en-AU", {
  timeZone: "Australia/Melbourne",
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "numeric",
  minute: "2-digit",
});

/**
 * The signed-in user's upcoming (future, not-cancelled) bookings. The
 * `bookings` visibility wall (RLS) already scopes this to rows they're a party
 * to — as student OR traveller — so no app-layer authz here.
 *
 * We show the counterparty: if you're the student, that's the traveller (fetched
 * by id, visible via the `users_can_see_booking_counterparties` profiles
 * policy); if you're the traveller, it's the student, whose name is the frozen
 * snapshot already stored on the booking row.
 */
export async function UpcomingBookings({ userId }: { userId: string }) {
  const supabase = await createClient();

  const { data: bookings } = await supabase
    .from("bookings")
    .select(
      "id, starts_at, reason, student_id, time_traveller_id, student_first_name, student_last_name",
    )
    .gte("starts_at", new Date().toISOString())
    .is("cancelled_at", null)
    .order("starts_at", { ascending: true });

  if (!bookings || bookings.length === 0) {
    return (
      <section className="space-y-4">
        <SectionHeading icon={CalendarCheck} title="Your upcoming bookings" />
        <p className="text-sm text-muted-foreground">
          You have no upcoming consultations. Pick a slot below to book one.
        </p>
      </section>
    );
  }

  // For bookings where I'm the student, look up the assigned traveller's name.
  const travellerIds = [
    ...new Set(
      bookings
        .filter((b) => b.student_id === userId)
        .map((b) => b.time_traveller_id),
    ),
  ];

  const travellerNames = new Map<string, string>();
  if (travellerIds.length > 0) {
    const { data: travellers } = await supabase
      .from("profiles")
      .select("id, first_name, last_name")
      .in("id", travellerIds);
    for (const t of travellers ?? []) {
      travellerNames.set(t.id, `${t.first_name} ${t.last_name}`);
    }
  }

  return (
    <section className="space-y-4">
      <SectionHeading icon={CalendarCheck} title="Your upcoming bookings" />
      <ul className="grid gap-3 sm:grid-cols-2">
        {bookings.map((b) => {
          const iAmStudent = b.student_id === userId;
          const counterparty = iAmStudent
            ? (travellerNames.get(b.time_traveller_id) ?? "Your time traveller")
            : `${b.student_first_name} ${b.student_last_name}`;
          const role = iAmStudent ? "with time traveller" : "with student";

          return (
            <li key={b.id}>
              <Card>
                <CardContent className="flex items-start gap-3 p-4">
                  <span className="mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                    <CalendarClock size={18} />
                  </span>
                  <div className="min-w-0">
                    <p className="font-medium">
                      {slotFmt.format(new Date(b.starts_at))}
                    </p>
                    <p className="truncate text-sm text-muted-foreground">
                      {role} <span className="text-foreground">{counterparty}</span>
                    </p>
                    <p className="mt-1 truncate text-sm text-muted-foreground">
                      {b.reason}
                    </p>
                  </div>
                </CardContent>
              </Card>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
