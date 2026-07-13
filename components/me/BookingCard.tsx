import { CalendarClock } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { formatSlot, STATUS_LABEL, type BookingStatus } from "./booking-utils";

const STATUS_VARIANT: Record<
  BookingStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  upcoming: "secondary",
  past: "outline",
  completed: "default",
  cancelled: "destructive",
};

/**
 * Presentational booking row shared by every role's list. Pure (no hooks), so
 * it renders fine inside server or client components. `details` carries the
 * role-specific body (counterparty, university…) and `actions` the optional
 * button row a student's own bookings get.
 */
export function BookingCard({
  startsAt,
  status,
  details,
  actions,
}: {
  startsAt: string;
  status: BookingStatus;
  details: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-3 p-4">
        <div className="flex items-start gap-3">
          <span className="mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <CalendarClock size={18} />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex items-start justify-between gap-2">
              <p className="font-medium">{formatSlot(startsAt)}</p>
              <Badge variant={STATUS_VARIANT[status]} className="shrink-0">
                {STATUS_LABEL[status]}
              </Badge>
            </div>
            <div className="mt-0.5 text-sm text-muted-foreground">
              {details}
            </div>
          </div>
        </div>
        {actions}
      </CardContent>
    </Card>
  );
}
