import { createHash } from "crypto";

/**
 * Gravatar URL for an email. Uses the `identicon` fallback so there is always
 * an image (no broken <img>), which lets the <Avatar> render it without any
 * client-side error handling.
 */
export function gravatarUrl(email: string, size = 160): string {
  const hash = createHash("md5")
    .update(email.trim().toLowerCase())
    .digest("hex");
  return `https://www.gravatar.com/avatar/${hash}?d=identicon&s=${size}`;
}
