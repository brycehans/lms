import Link from "next/link";
import { Telescope } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * The Course Prophecies wordmark + logo lockup. Links home. Used in the nav
 * and as the header above the auth cards.
 */
export function BrandMark({ className }: { className?: string }) {
  return (
    <Link
      href="/"
      className={cn(
        "inline-flex items-center gap-2 font-semibold text-foreground",
        className,
      )}
    >
      <span className="inline-flex h-7 w-7 items-center justify-center rounded-lg bg-primary text-primary-foreground">
        <Telescope size={16} />
      </span>
      Course Prophecies
    </Link>
  );
}
