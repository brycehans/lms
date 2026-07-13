import { cn } from "@/lib/utils";

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

/**
 * Round avatar. Renders `src` when given (e.g. a Gravatar URL); otherwise falls
 * back to the person's initials on a muted disc. Travellers have no readable
 * email (profiles stores no email, auth.users isn't exposed), so their tiles
 * use the initials fallback.
 */
export function Avatar({
  name,
  src,
  className,
}: {
  name: string;
  src?: string;
  className?: string;
}) {
  const base = cn(
    "shrink-0 rounded-full overflow-hidden bg-muted text-muted-foreground",
    "flex items-center justify-center font-medium select-none",
    "size-12 text-sm",
    className,
  );

  if (src) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={name} className={base} />;
  }

  return (
    <span className={base} aria-hidden>
      {initials(name) || "?"}
    </span>
  );
}
