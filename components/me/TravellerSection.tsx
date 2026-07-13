import { createClient } from "@/lib/supabase/server";
import { Telescope } from "lucide-react";
import { SectionHeading } from "@/components/home/SectionHeading";
import { BookingCard } from "./BookingCard";
import { BookingList } from "./BookingList";
import { bookingStatus } from "./booking-utils";

/**
 * The sessions assigned to a traveller. Read-only: travellers don't schedule,
 * so there are no actions. The student's name is the frozen snapshot on the
 * booking row, so no profile lookup is needed.
 */
export async function TravellerSection({ userId }: { userId: string }) {
  const supabase = await createClient();
  const now = Date.now();

  const { data: bookings } = await supabase
    .from("bookings")
    .select(
      "id, starts_at, reason, student_first_name, student_last_name, cancelled_at, completed_at",
    )
    .eq("time_traveller_id", userId);

  const items = (bookings ?? []).map((b) => {
    const status = bookingStatus(b, now);
    const studentName = `${b.student_first_name} ${b.student_last_name}`;
    return {
      id: b.id,
      startsAt: b.starts_at,
      status,
      card: (
        <BookingCard
          startsAt={b.starts_at}
          status={status}
          details={
            <>
              with student{" "}
              <span className="text-foreground">{studentName}</span>
              <span className="mt-1 block truncate">{b.reason}</span>
            </>
          }
        />
      ),
    };
  });

  return (
    <section className="space-y-4">
      <SectionHeading icon={Telescope} title="Sessions assigned to you" />
      <BookingList
        items={items}
        emptyMessage="No students have been assigned to you yet."
      />
    </section>
  );
}
