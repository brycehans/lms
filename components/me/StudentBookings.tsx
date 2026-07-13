"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { CalendarSync, Check, Undo2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/ui/form-message";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { BookingCard } from "./BookingCard";
import { BookingList } from "./BookingList";
import { formatSlot, type BookingStatus } from "./booking-utils";

export type StudentBooking = {
  id: string;
  starts_at: string;
  reason: string;
  travellerName: string;
  universityId?: string;
  universityName?: string;
  status: BookingStatus;
};

const DAY_MS = 86_400_000;
// How far ahead we offer reschedule slots.
const RESCHEDULE_WINDOW_DAYS = 21;

/**
 * A student's own bookings, with the three mutations they're allowed:
 * cancel + reschedule (upcoming only) and toggle-completion (past only). Each
 * button hits an API route that calls the matching SECURITY DEFINER RPC — the
 * only client-writable surface — then we `router.refresh()` so the server
 * components re-read the new state.
 */
export function StudentBookings({ items }: { items: StudentBooking[] }) {
  const router = useRouter();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // A transient success confirmation (e.g. after a reschedule). The card itself
  // moves to its new sorted position on refresh, so this line names what changed
  // and then clears itself.
  const [success, setSuccess] = useState<string | null>(null);
  useEffect(() => {
    if (!success) return;
    const t = setTimeout(() => setSuccess(null), 4000);
    return () => clearTimeout(t);
  }, [success]);

  // Reschedule panel state (only one open at a time).
  const [openId, setOpenId] = useState<string | null>(null);
  const [slots, setSlots] = useState<{ iso: string; label: string }[]>([]);
  const [slotsStatus, setSlotsStatus] = useState<"idle" | "loading" | "error">(
    "idle",
  );
  const [chosen, setChosen] = useState<string>("");

  async function mutate(
    url: string,
    body: unknown,
    id: string,
    successMsg: string,
  ) {
    setBusyId(id);
    setError(null);
    setSuccess(null);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(json.error ?? "Something went wrong. Please try again.");
        return false;
      }
      router.refresh();
      setSuccess(successMsg);
      return true;
    } catch {
      setError("Network error. Please try again.");
      return false;
    } finally {
      setBusyId(null);
    }
  }

  async function openReschedule(startsAt: string) {
    setOpenId(startsAt);
    setChosen("");
    setError(null);
    setSuccess(null);
    setSlotsStatus("loading");
    const now = Date.now();
    const from = new Date(now).toISOString();
    const to = new Date(now + RESCHEDULE_WINDOW_DAYS * DAY_MS).toISOString();
    // Reschedule-specific RPC: it only returns slots where THIS booking's
    // assigned traveller and the student are both free, so every option offered
    // will pass reschedule_booking's checks. (list_available_slots is the
    // any-traveller new-booking query and would surface slots that then fail.)
    const { data, error } = await createClient().rpc("list_reschedule_slots", {
      p_current_start: startsAt,
      p_from: from,
      p_to: to,
    });
    if (error || !data) {
      setSlotsStatus("error");
      setSlots([]);
      return;
    }
    // setof timestamptz → bare ISO strings. The RPC already excludes the
    // current slot.
    setSlots(
      (data as string[]).map((iso) => ({ iso, label: formatSlot(iso) })),
    );
    setSlotsStatus("idle");
  }

  const listItems = items.map((b) => {
    const busy = busyId === b.id;
    const isOpen = openId === b.starts_at;

    return {
      id: b.id,
      startsAt: b.starts_at,
      status: b.status,
      universityId: b.universityId,
      universityName: b.universityName,
      card: (
        <BookingCard
          startsAt={b.starts_at}
          status={b.status}
          details={
            <>
              with time traveller{" "}
              <span className="text-foreground">{b.travellerName}</span>
              {b.universityName ? ` · ${b.universityName}` : ""}
              <span className="mt-1 block truncate">{b.reason}</span>
            </>
          }
          actions={
            <div className="flex flex-col gap-2 border-t pt-3">
              <div className="flex flex-wrap gap-2">
                {b.status === "upcoming" && (
                  <>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={busy}
                      onClick={() =>
                        isOpen ? setOpenId(null) : openReschedule(b.starts_at)
                      }
                    >
                      <CalendarSync size={15} />
                      Reschedule
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={busy}
                      onClick={() =>
                        mutate(
                          "/api/bookings/cancel",
                          { startsAt: b.starts_at },
                          b.id,
                          "Consultation cancelled.",
                        )
                      }
                    >
                      <X size={15} />
                      Cancel
                    </Button>
                  </>
                )}
                {b.status === "past" && (
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={busy}
                    onClick={() =>
                      mutate(
                        "/api/bookings/complete",
                        { bookingId: b.id, isComplete: true },
                        b.id,
                        "Marked as complete.",
                      )
                    }
                  >
                    <Check size={15} />
                    Mark complete
                  </Button>
                )}
                {b.status === "completed" && (
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={busy}
                    onClick={() =>
                      mutate(
                        "/api/bookings/complete",
                        { bookingId: b.id, isComplete: false },
                        b.id,
                        "Marked as not complete.",
                      )
                    }
                  >
                    <Undo2 size={15} />
                    Mark not complete
                  </Button>
                )}
              </div>

              {isOpen && (
                <div className="flex flex-wrap items-center gap-2">
                  {slotsStatus === "loading" && (
                    <span className="text-sm text-muted-foreground">
                      Loading available slots…
                    </span>
                  )}
                  {slotsStatus === "error" && (
                    <span className="text-sm text-muted-foreground">
                      Couldn&apos;t load availability. Please try again.
                    </span>
                  )}
                  {slotsStatus === "idle" && slots.length === 0 && (
                    <span className="text-sm text-muted-foreground">
                      No other slots are free in the next{" "}
                      {RESCHEDULE_WINDOW_DAYS} days.
                    </span>
                  )}
                  {slotsStatus === "idle" && slots.length > 0 && (
                    <>
                      <Select value={chosen} onValueChange={setChosen}>
                        <SelectTrigger size="sm" className="min-w-[16rem]">
                          <SelectValue placeholder="Pick a new time…" />
                        </SelectTrigger>
                        <SelectContent>
                          {slots.map((s) => (
                            <SelectItem key={s.iso} value={s.iso}>
                              {s.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Button
                        size="sm"
                        disabled={busy || !chosen}
                        onClick={async () => {
                          const label = slots.find(
                            (s) => s.iso === chosen,
                          )?.label;
                          const ok = await mutate(
                            "/api/bookings/reschedule",
                            { currentStart: b.starts_at, newStart: chosen },
                            b.id,
                            label
                              ? `Consultation moved to ${label}.`
                              : "Consultation rescheduled.",
                          );
                          if (ok) setOpenId(null);
                        }}
                      >
                        Confirm move
                      </Button>
                    </>
                  )}
                  {/* Reschedule failure shows here, next to the picker, so the
                        student can immediately pick another slot. Other actions'
                        errors surface at the bottom of the list. */}
                  <FormMessage className="w-full">{error}</FormMessage>
                </div>
              )}
            </div>
          }
        />
      ),
    };
  });

  return (
    <div className="space-y-3">
      <BookingList
        items={listItems}
        emptyMessage="You haven't booked any consultations yet. Pick a slot on the home page to book one."
      />
      {/* When a reschedule panel is open its own error renders inline (above);
          this covers the instant cancel/complete actions instead. */}
      {!openId && <FormMessage>{error}</FormMessage>}
      <FormMessage variant="success">{success}</FormMessage>
    </div>
  );
}
