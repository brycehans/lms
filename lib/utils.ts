import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Slugify a display name for filesystem/URL lookup: lowercase, non-alphanumerics
 * collapsed to single hyphens, trimmed. "Amara Okafor" -> "amara-okafor". Used to
 * resolve a traveller's portrait at /public/travellers/<slug>.webp.
 */
export function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * Sanitize a post-auth redirect target. Only same-origin, path-absolute URLs
 * (a single leading "/", not "//host" and not "/\host") are trusted; anything
 * else — a full URL, a protocol-relative "//evil.com", a missing value — falls
 * back to `/me`. This is the open-redirect guard for the `?next=` param we thread
 * through the login gate so a booking deep-link survives a round-trip to login.
 */
export function safeNext(next: string | null | undefined): string {
  if (typeof next !== "string") return "/me";
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) {
    return "/me";
  }
  return next;
}

/**
 * A11y attributes tying a form control to its <FieldError>. When the field is
 * invalid we mark the control `aria-invalid` (which the Input/Textarea/Select
 * primitives style with a destructive border) and point screen readers at the
 * message via `aria-describedby`. `errorId` must match the id passed to the
 * matching <FieldError>. Spread onto the control: `{...errorAttrs(!!errors.x, "x-error")}`.
 */
export function errorAttrs(hasError: boolean, errorId: string) {
  return {
    "aria-invalid": hasError || undefined,
    "aria-describedby": hasError ? errorId : undefined,
  } as const;
}
