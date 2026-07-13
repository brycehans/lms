import { createClient } from "@/lib/supabase/server";
import { ShieldCheck } from "lucide-react";
import { SectionHeading } from "@/components/home/SectionHeading";
import { BookingCard } from "./BookingCard";
import { BookingList } from "./BookingList";
import { bookingStatus } from "./booking-utils";

/**
 * The oversight list for staff. We deliberately do NOT filter by university
 * here — the `admins_read_scoped_bookings` policy does the scoping: an admin
 * sees only their universities' bookings, a superadmin sees all. So this same
 * unfiltered query yields the correct set for either role, and the DB stays the
 * single source of truth for who-sees-what. Read-only (staff can't book).
 */
export async function OversightSection({
  isSuperadmin,
}: {
  isSuperadmin: boolean;
}) {
  const supabase = await createClient();
  const now = Date.now();

  const { data: bookings } = await supabase
    .from("bookings")
    .select(
      "id, starts_at, reason, time_traveller_id, student_first_name, student_last_name, university_id, cancelled_at, completed_at, deleted_at",
    );

  const rows = bookings ?? [];

  // Traveller names (traveller profiles are publicly readable) + university names.
  const travellerIds = [...new Set(rows.map((b) => b.time_traveller_id))];
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

  const travellerNames = new Map<string, string>();
  for (const t of travellers ?? []) {
    travellerNames.set(t.id, `${t.first_name} ${t.last_name}`);
  }
  const uniNames = new Map<string, string>();
  for (const u of unis ?? []) uniNames.set(u.id, u.name);

  const items = rows.map((b) => {
    const status = bookingStatus(b, now);
    const studentName = `${b.student_first_name} ${b.student_last_name}`;
    const travellerName =
      travellerNames.get(b.time_traveller_id) ?? "a time traveller";
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
          deleted={!!b.deleted_at}
          details={
            <>
              <span className="text-foreground">{studentName}</span> with{" "}
              <span className="text-foreground">{travellerName}</span>
              {universityName ? ` · ${universityName}` : ""}
              <span className="mt-1 block truncate">{b.reason}</span>
            </>
          }
        />
      ),
    };
  });

  const title = isSuperadmin ? "All bookings" : "Bookings at your universities";

  return (
    <section className="space-y-4">
      <SectionHeading icon={ShieldCheck} title={title} />
      <BookingList
        items={items}
        emptyMessage="There are no bookings in your scope yet."
      />
    </section>
  );
}
