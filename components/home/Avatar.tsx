"use client";

import { useState } from "react";
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
 * Round avatar. Renders `src` when given (e.g. a portrait under
 * /public/travellers); if that image is missing or fails to load, it falls back
 * to the person's initials on a muted disc — so travellers without a portrait
 * (and any 404) degrade gracefully rather than showing a broken image.
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
  const [failed, setFailed] = useState(false);

  const base = cn(
    "shrink-0 rounded-lg overflow-hidden bg-muted text-muted-foreground",
    "flex items-center justify-center font-medium select-none",
    "size-12 text-sm",
    className,
  );

  if (src && !failed) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt={name}
        className={base}
        onError={() => setFailed(true)}
      />
    );
  }

  return (
    <span className={base} aria-hidden>
      {initials(name) || "?"}
    </span>
  );
}
