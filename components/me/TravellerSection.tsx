import { createClient } from "@/lib/supabase/server";
import { Telescope } from "lucide-react";
import { SectionHeading } from "@/components/home/SectionHeading";
import { BookingCard } from "./BookingCard";
import { BookingList } from "./BookingList";
import { bookingStatus } from "./booking-utils";
import { loaded, SectionError } from "./section-query";

/**
 * The sessions assigned to a traveller. Read-only: travellers don't schedule,
 * so there are no actions. The student's name is the frozen snapshot on the
 * booking row, so no profile lookup is needed.
 */
export async function TravellerSection({ userId }: { userId: string }) {
  const supabase = await createClient();
  const now = Date.now();

  const result = loaded(
    await supabase
      .from("bookings")
      .select(
        "id, starts_at, reason, student_first_name, student_last_name, university_id, cancelled_at, completed_at",
      )
      .eq("time_traveller_id", userId),
    "traveller sessions",
  );
  if (!result.ok) {
    return <SectionError icon={Telescope} title="Sessions assigned to you" />;
  }
  const rows = result.rows;

  // University snapshots (readable via public_read_universities). A traveller
  // serves students across universities, so their assigned sessions can span
  // several — which surfaces the university filter in the list below.
  const uniIds = [...new Set(rows.map((b) => b.university_id))];
  const uniNames = new Map<string, string>();
  if (uniIds.length > 0) {
    const { data: unis } = await supabase
      .from("universities")
      .select("id, name")
      .in("id", uniIds);
    for (const u of unis ?? []) uniNames.set(u.id, u.name);
  }

  const items = rows.map((b) => {
    const status = bookingStatus(b, now);
    const studentName = `${b.student_first_name} ${b.student_last_name}`;
    const universityName = uniNames.get(b.university_id);
    return {
      id: b.id,
      startsAt: b.starts_at,
      status,
      universityId: b.university_id,
      universityName,
      card: (
        <BookingCard
          startsAt={b.starts_at}
          status={status}
          details={
            <>
              with student{" "}
              <span className="text-foreground">{studentName}</span>
              {universityName ? ` · ${universityName}` : ""}
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
