"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { SectionHeading } from "./SectionHeading";
import { cn } from "@/lib/utils";

/**
 * Rolling weekly availability grid: today is the left-most column, seven days
 * across, the eight bookable hours (9am–4pm, Australia/Melbourne) down. Arrows
 * page ±7 days.
 *
 * CONTRACT — reads a SECURITY DEFINER RPC:
 *
 *   public.list_available_slots(p_from timestamptz, p_to timestamptz)
 *     returns setof timestamptz
 *
 *   Each returned value is a bookable slot start in [p_from, p_to) that has at
 *   least one traveller free. Because it returns a SCALAR set, PostgREST hands
 *   supabase-js a bare array of ISO strings (not `{ starts_at }` objects), so we
 *   consume `string[]`. It MUST be SECURITY DEFINER: under the bookings RLS wall
 *   the caller can't see other travellers' bookings, so availability can't be
 *   computed from a plain select.
 *
 * If the fetch errors the grid degrades to a gentle "couldn't load availability"
 * state rather than showing everything as full.
 */

const MELB = "Australia/Melbourne";
const HOURS = [9, 10, 11, 12, 13, 14, 15, 16];
const DAY_MS = 86_400_000;

// yyyy-mm-dd of an instant, in Melbourne wall-clock.
const melbDate = new Intl.DateTimeFormat("en-CA", {
  timeZone: MELB,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
// hour (00–23) of an instant, in Melbourne wall-clock.
const melbHour = new Intl.DateTimeFormat("en-GB", {
  timeZone: MELB,
  hour: "2-digit",
  hour12: false,
});
// Column header label. Columns are UTC-midnight anchors of a Melbourne calendar
// date, so we format them in UTC to read back that same date.
const colLabel = new Intl.DateTimeFormat("en-AU", {
  timeZone: "UTC",
  weekday: "short",
  day: "numeric",
});

const pad = (n: number) => String(n).padStart(2, "0");
// Slot identity = Melbourne calendar date + hour, e.g. "2026-07-13-9".
const slotKey = (ymd: string, hour: number) => `${ymd}-${hour}`;
const keyForInstant = (iso: string) =>
  slotKey(
    melbDate.format(new Date(iso)),
    Number(melbHour.format(new Date(iso))),
  );

type Status = "loading" | "ok" | "error";

export function AvailabilityCalendar() {
  const [weekOffset, setWeekOffset] = useState(0);
  const [status, setStatus] = useState<Status>("loading");
  // slot-key → the exact ISO instant the RPC returned for that slot.
  const [avail, setAvail] = useState<Map<string, string>>(new Map());

  // Melbourne "today" as a UTC-midnight anchor, so day arithmetic is DST-free.
  const [ty, tm, td] = melbDate.format(new Date()).split("-").map(Number);
  const todayAnchor = Date.UTC(ty, tm - 1, td);
  const todayYmd = `${ty}-${pad(tm)}-${pad(td)}`;
  const nowHour = Number(melbHour.format(new Date()));

  const columns = Array.from({ length: 7 }, (_, i) => {
    const date = new Date(todayAnchor + (weekOffset * 7 + i) * DAY_MS);
    const y = date.getUTCFullYear();
    const m = date.getUTCMonth() + 1;
    const d = date.getUTCDate();
    return {
      ymd: `${y}-${pad(m)}-${pad(d)}`,
      label: colLabel.format(date),
      isWeekday: date.getUTCDay() >= 1 && date.getUTCDay() <= 5,
      isToday: weekOffset === 0 && i === 0,
    };
  });

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");

    // Pad the window a day each side: Melbourne 9am is the prior UTC day, so a
    // slot on the first visible date can sit before its UTC midnight. We match
    // precisely by key afterwards, so over-fetching is harmless.
    const from = new Date(
      todayAnchor + (weekOffset * 7 - 1) * DAY_MS,
    ).toISOString();
    const to = new Date(
      todayAnchor + (weekOffset * 7 + 8) * DAY_MS,
    ).toISOString();

    createClient()
      .rpc("list_available_slots", { p_from: from, p_to: to })
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error || !data) {
          setStatus("error");
          setAvail(new Map());
          return;
        }
        // setof timestamptz → a bare array of ISO strings. Keep the ISO instant
        // against each slot key so the "Open" link can pass an unambiguous
        // absolute timestamp (no wall-clock → instant reconstruction / DST math).
        const slots = new Map<string, string>();
        for (const iso of data as string[]) {
          slots.set(keyForInstant(iso), iso);
        }
        setAvail(slots);
        setStatus("ok");
      });

    return () => {
      cancelled = true;
    };
  }, [weekOffset, todayAnchor]);

  const rangeLabel = `${columns[0].label} – ${columns[6].label}`;

  return (
    <section className="space-y-4 hash-target" id="availability-calendar">
      <SectionHeading
        icon={CalendarDays}
        title="Upcoming consultations"
        action={
          <div className="flex items-center gap-2">
            <span className="hidden text-sm text-muted-foreground sm:inline">
              {rangeLabel}
            </span>
            <Button
              variant="outline"
              size="icon"
              aria-label="Previous week"
              disabled={weekOffset <= 0}
              onClick={() => setWeekOffset((w) => Math.max(0, w - 1))}
            >
              <ChevronLeft size={16} />
            </Button>
            <Button
              variant="outline"
              size="icon"
              aria-label="Next week"
              onClick={() => setWeekOffset((w) => w + 1)}
            >
              <ChevronRight size={16} />
            </Button>
          </div>
        }
      />
      <p className="text-sm text-muted-foreground">
        Our time travellers are available to meet with the present version of
        you Monday to Friday, 9am to 4pm.
      </p>

      {status === "error" && (
        <p className="text-sm text-muted-foreground">
          We couldn&apos;t load live availability right now. Please try again
          shortly.
        </p>
      )}

      <div className="overflow-x-auto rounded-xl border">
        <div className="grid min-w-[640px] grid-cols-8">
          {/* header row */}
          <div className="border-b bg-muted/40 p-2" />
          {columns.map((c) => (
            <div
              key={c.ymd}
              className={cn(
                "border-b border-l bg-muted/40 p-2 text-center text-sm",
                c.isToday && "font-semibold text-foreground",
                !c.isToday && "text-muted-foreground",
              )}
            >
              {c.label}
            </div>
          ))}

          {/* one row per bookable hour */}
          {HOURS.map((hour) => (
            <Row
              key={hour}
              hour={hour}
              columns={columns}
              avail={avail}
              status={status}
              todayYmd={todayYmd}
              nowHour={nowHour}
            />
          ))}
        </div>
      </div>
    </section>
  );
}

function Row({
  hour,
  columns,
  avail,
  status,
  todayYmd,
  nowHour,
}: {
  hour: number;
  columns: { ymd: string; isWeekday: boolean }[];
  avail: Map<string, string>;
  status: Status;
  todayYmd: string;
  nowHour: number;
}) {
  const hourLabel = `${((hour + 11) % 12) + 1}${hour < 12 ? "am" : "pm"}`;

  return (
    <>
      <div className="flex items-center justify-end border-t p-2 text-sm text-muted-foreground">
        {hourLabel}
      </div>
      {columns.map((c) => {
        const key = slotKey(c.ymd, hour);
        const isPast =
          c.ymd < todayYmd || (c.ymd === todayYmd && hour <= nowHour);
        // The exact ISO instant for this slot, or undefined if not bookable.
        const startAt = avail.get(key);

        let cell;
        if (!c.isWeekday || isPast) {
          cell = <span className="text-muted-foreground/40">—</span>;
        } else if (status !== "ok") {
          cell = <span className="text-muted-foreground/40">·</span>;
        } else if (startAt) {
          cell = (
            <Link
              href={`/book?start_at=${encodeURIComponent(startAt)}`}
              className="block rounded-md bg-emerald-500/10 py-1 text-sm font-medium text-emerald-700 hover:bg-emerald-500/20 dark:text-emerald-400"
            >
              Open
            </Link>
          );
        } else {
          cell = <span className="text-sm text-muted-foreground/60">Full</span>;
        }

        return (
          <div key={c.ymd} className="border-l border-t p-1.5 text-center">
            {cell}
          </div>
        );
      })}
    </>
  );
}
