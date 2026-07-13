import { cn } from "@/lib/utils";

/**
 * Form-level feedback banner for the whole form (a submit error surfaced from
 * the server, or a success confirmation) — as opposed to <FieldError>, which
 * annotates a single control.
 *
 * The variant picks the live-region semantics so assistive tech announces it:
 * errors are `role="alert"` (assertive — interrupt), successes are `role="status"`
 * (polite — wait for a pause). Renders nothing without children.
 */
export function FormMessage({
  variant = "error",
  className,
  children,
}: {
  variant?: "error" | "success";
  className?: string;
  children?: React.ReactNode;
}) {
  if (!children) return null;
  const isError = variant === "error";
  return (
    <p
      role={isError ? "alert" : "status"}
      aria-live={isError ? "assertive" : "polite"}
      className={cn(
        "text-sm",
        isError ? "text-destructive" : "text-emerald-600 dark:text-emerald-400",
        className,
      )}
    >
      {children}
    </p>
  );
}
