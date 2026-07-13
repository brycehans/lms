import { cn } from "@/lib/utils";

/**
 * Inline validation message for a single form field. Rendered as `role="alert"`
 * so it's announced when it appears after a submit attempt, and given a stable
 * `id` that the control references via `aria-describedby` (see `errorAttrs`).
 * Renders nothing when there's no message, so call sites can drop the `&&` guard.
 */
export function FieldError({
  id,
  className,
  children,
}: {
  id: string;
  className?: string;
  children?: React.ReactNode;
}) {
  if (!children) return null;
  return (
    <p id={id} role="alert" className={cn("text-sm text-destructive", className)}>
      {children}
    </p>
  );
}
