import type { LucideIcon } from "lucide-react";

/**
 * A section heading with a soft green icon badge — the recurring visual motif
 * across the homepage sections. Optional right-aligned `action` slot (e.g. the
 * calendar's week pager).
 */
export function SectionHeading({
  icon: Icon,
  title,
  action,
}: {
  icon: LucideIcon;
  title: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <h2 className="flex items-center gap-3 text-2xl font-semibold">
        <span className="inline-flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <Icon size={20} strokeWidth={2} />
        </span>
        {title}
      </h2>
      {action}
    </div>
  );
}
