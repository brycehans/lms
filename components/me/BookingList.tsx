"use client";

import { useMemo, useState, type ReactNode } from "react";
import { ArrowDownUp, Building2, ListFilter } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  sortBookings,
  SORT_LABEL,
  STATUS_LABEL,
  STATUS_ORDER,
  type BookingStatus,
  type SortMode,
} from "./booking-utils";

export type BookingListItem = {
  id: string;
  startsAt: string;
  status: BookingStatus;
  /**
   * The booking's frozen university snapshot. Optional because not every caller
   * has it (e.g. the traveller view doesn't fetch it). When present across ≥2
   * distinct universities, the toolbar grows a university filter — handy for a
   * transferred student with old + new bookings, or staff narrowing by tenant.
   */
  universityId?: string;
  universityName?: string;
  /** The fully-rendered row (a `BookingCard`, with any role-specific actions). */
  card: ReactNode;
};

type StatusFilter = "all" | BookingStatus;
type UniversityFilter = "all" | string;

/**
 * Wraps a role's bookings with a client-side filter + sort toolbar. The rows
 * themselves are rendered by the caller (server or client) and handed in as
 * `card` nodes, so this component stays agnostic about what a booking shows —
 * it only needs `startsAt` + `status` to order and filter. The toolbar only
 * appears once there's more than one booking (nothing to sort a single row).
 */
export function BookingList({
  items,
  emptyMessage,
}: {
  items: BookingListItem[];
  emptyMessage: ReactNode;
}) {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [universityFilter, setUniversityFilter] =
    useState<UniversityFilter>("all");
  const [sort, setSort] = useState<SortMode>("lifecycle");

  // Which statuses are actually present, with counts, for the filter dropdown.
  const counts = useMemo(() => {
    const c = new Map<BookingStatus, number>();
    for (const it of items) c.set(it.status, (c.get(it.status) ?? 0) + 1);
    return c;
  }, [items]);

  // Distinct universities present (id → name + count), sorted by name so the
  // dropdown order is stable. Items with no university snapshot are ignored.
  const universities = useMemo(() => {
    const m = new Map<string, { name: string; count: number }>();
    for (const it of items) {
      if (!it.universityId) continue;
      const prev = m.get(it.universityId);
      m.set(it.universityId, {
        name: it.universityName ?? "Unknown university",
        count: (prev?.count ?? 0) + 1,
      });
    }
    return [...m.entries()].sort((a, b) => a[1].name.localeCompare(b[1].name));
  }, [items]);

  const visible = useMemo(() => {
    const filtered = items.filter(
      (it) =>
        (statusFilter === "all" || it.status === statusFilter) &&
        (universityFilter === "all" || it.universityId === universityFilter),
    );
    return sortBookings(filtered, sort);
  }, [items, statusFilter, universityFilter, sort]);

  if (items.length === 0) {
    return <p className="text-sm text-muted-foreground">{emptyMessage}</p>;
  }

  const presentStatuses = STATUS_ORDER.filter((s) => counts.has(s));
  const clearFilters = () => {
    setStatusFilter("all");
    setUniversityFilter("all");
  };

  return (
    <div className="space-y-3">
      {items.length > 1 && (
        <div className="flex flex-wrap items-center gap-2">
          <Select
            value={statusFilter}
            onValueChange={(v) => setStatusFilter(v as StatusFilter)}
          >
            <SelectTrigger size="sm" className="min-w-[11rem]">
              <ListFilter />
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All ({items.length})</SelectItem>
              {presentStatuses.map((s) => (
                <SelectItem key={s} value={s}>
                  {STATUS_LABEL[s]} ({counts.get(s)})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          {universities.length > 1 && (
            <Select
              value={universityFilter}
              onValueChange={(v) => setUniversityFilter(v as UniversityFilter)}
            >
              <SelectTrigger size="sm" className="min-w-[13rem]">
                <Building2 />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">
                  All universities ({items.length})
                </SelectItem>
                {universities.map(([id, { name, count }]) => (
                  <SelectItem key={id} value={id}>
                    {name} ({count})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}

          <Select value={sort} onValueChange={(v) => setSort(v as SortMode)}>
            <SelectTrigger size="sm" className="min-w-[11rem]">
              <ArrowDownUp />
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {(Object.keys(SORT_LABEL) as SortMode[]).map((m) => (
                <SelectItem key={m} value={m}>
                  {SORT_LABEL[m]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      {visible.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {universityFilter === "all" && statusFilter !== "all"
            ? `No ${STATUS_LABEL[statusFilter as BookingStatus].toLowerCase()} bookings.`
            : "No bookings match these filters."}{" "}
          <button
            type="button"
            className="underline underline-offset-2 hover:text-foreground"
            onClick={clearFilters}
          >
            Show all
          </button>
        </p>
      ) : (
        visible.map((it) => <div key={it.id}>{it.card}</div>)
      )}
    </div>
  );
}
