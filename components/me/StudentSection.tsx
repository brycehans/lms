import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CalendarCheck, CalendarPlus, Sparkles } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { SectionHeading } from "@/components/home/SectionHeading";
import { StudentBookings, type StudentBooking } from "./StudentBookings";
import { bookingStatus } from "./booking-utils";
import { loaded, SectionError } from "./section-query";

/**
 * The student's own bookings. The bookings visibility wall (RLS) already scopes
 * this to rows where they're the student, so `.eq("student_id", …)` is a
 * belt-and-braces filter rather than the security boundary. Actions live in the
 * client child; this component just reads + shapes the data.
 */
export async function StudentSection({ userId }: { userId: string }) {
  const supabase = await createClient();
  const now = Date.now();

  const result = loaded(
    await supabase
      .from("bookings")
      .select(
        "id, starts_at, reason, time_traveller_id, university_id, cancelled_at, completed_at",
      )
      .eq("student_id", userId),
    "student bookings",
  );
  if (!result.ok) {
    return <SectionError icon={CalendarCheck} title="Your bookings" />;
  }
  const rows = result.rows;

  // The assigned traveller's name is visible via the counterparty profiles policy.
  const travellerIds = [...new Set(rows.map((b) => b.time_traveller_id))];
  // University snapshots (readable via public_read_universities). A student is
  // enrolled in one uni, but bookings freeze the uni at creation — so a
  // transferred student can hold bookings across more than one, which is what
  // powers the university filter in the list below.
  const uniIds = [...new Set(rows.map((b) => b.university_id))];

  const [{ data: travellers }, { data: unis }] = await Promise.all([
    travellerIds.length
      ? supabase
          .from("profiles")
          .select("id, first_name, last_name")
          .in("id", travellerIds)
      : Promise.resolve({
          data: [] as { id: string; first_name: string; last_name: string }[],
        }),
    uniIds.length
      ? supabase.from("universities").select("id, name").in("id", uniIds)
      : Promise.resolve({ data: [] as { id: string; name: string }[] }),
  ]);

  const names = new Map<string, string>();
  for (const t of travellers ?? []) {
    names.set(t.id, `${t.first_name} ${t.last_name}`);
  }
  const uniNames = new Map<string, string>();
  for (const u of unis ?? []) uniNames.set(u.id, u.name);

  // Ordering + filtering happen client-side in BookingList; pass rows as-is.
  const items: StudentBooking[] = rows.map((b) => ({
    id: b.id,
    starts_at: b.starts_at,
    reason: b.reason,
    travellerName: names.get(b.time_traveller_id) ?? "your time traveller",
    universityId: b.university_id,
    universityName: uniNames.get(b.university_id),
    status: bookingStatus(b, now),
  }));

  return (
    <section className="space-y-4">
      {/* Book-a-new-session CTA — the primary action a student comes here for. */}
      <div className="flex flex-col items-start gap-3 rounded-xl border bg-accent/60 p-4 sm:flex-row sm:items-center sm:justify-between">
        <p className="flex items-center gap-2 text-sm text-foreground">
          <Sparkles
            size={18}
            strokeWidth={2}
            className="shrink-0 text-primary"
          />
          Ready to find out how you did? Book a consultation with a time
          traveller.
        </p>
        <Link
          href="/book"
          className={buttonVariants({ className: "shrink-0" })}
        >
          <CalendarPlus size={16} />
          Book a session
        </Link>
      </div>

      <SectionHeading icon={CalendarCheck} title="Your bookings" />
      <StudentBookings items={items} />
    </section>
  );
}
