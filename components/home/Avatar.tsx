"use client";

import { useEffect, useRef, useState } from "react";
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
  // Track the *src* that failed, not a bare boolean. This means a changed `src`
  // is retried, but a src already known to be broken never reloads — so there's
  // no error→re-render→reload thrash on a persistently-missing image.
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const failed = src != null && failedSrc === src;

  const imgRef = useRef<HTMLImageElement | null>(null);

  // The image is server-rendered, so it can 404/error before React hydrates and
  // attaches `onError` — that error would otherwise be missed, leaving a broken
  // <img> the browser keeps retrying. On mount, catch an already-errored image
  // (loaded but zero-size) and fall back immediately.
  useEffect(() => {
    const img = imgRef.current;
    if (img && img.complete && img.naturalWidth === 0) {
      setFailedSrc(src ?? null);
    }
  }, [src]);

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
        ref={imgRef}
        src={src}
        alt={name}
        className={base}
        onError={() => setFailedSrc(src)}
      />
    );
  }

  return (
    <span className={base} aria-hidden>
      {initials(name) || "?"}
    </span>
  );
}
