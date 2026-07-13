import type { LucideIcon } from "lucide-react";
import { SectionHeading } from "@/components/home/SectionHeading";

/**
 * Result of a Supabase read that distinguishes an EMPTY result from a FAILED one.
 *
 * The account sections previously did `const rows = data ?? []`, which collapses
 * every failure mode — an RLS regression, a dropped connection, a schema drift,
 * a network blip — into a silent "no rows". That is both a lie to the user
 * ("you have no bookings" when the query actually errored) and an observability
 * blind spot (nothing logged). `loaded()` logs the failure with a context label
 * and hands back a discriminated result so the caller can render an explicit
 * failure state instead of a plausible-but-wrong empty one.
 */
export type Loaded<T> = { ok: true; rows: T[] } | { ok: false };

export function loaded<T>(
  res: { data: T[] | null; error: { message: string } | null },
  context: string,
): Loaded<T> {
  if (res.error) {
    // Server Component — lands in the server logs with enough context to trace.
    console.error(`[/me] query failed (${context}): ${res.error.message}`);
    return { ok: false };
  }
  return { ok: true, rows: res.data ?? [] };
}

/**
 * Explicit, non-alarming failure panel for a /me section — rendered in place of
 * the list when its primary query fails, so a failure never masquerades as "no
 * bookings". Mirrors the section layout (same heading) so the page stays coherent.
 */
export function SectionError({
  icon,
  title,
  message = "We couldn't load this section just now. Please refresh to try again.",
}: {
  icon: LucideIcon;
  title: string;
  message?: string;
}) {
  return (
    <section className="space-y-4">
      <SectionHeading icon={icon} title={title} />
      <div
        role="alert"
        className="rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm text-foreground"
      >
        {message}
      </div>
    </section>
  );
}
