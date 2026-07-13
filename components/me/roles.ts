/** The persona enum stored in `user_roles.role`. */
export type AppRole = "student" | "traveller" | "admin" | "superadmin";

// Stable display order, so multi-role users always see their notes/sections in
// the same sequence.
const ORDER: AppRole[] = ["student", "traveller", "admin", "superadmin"];

export function sortRoles(roles: AppRole[]): AppRole[] {
  return ORDER.filter((r) => roles.includes(r));
}
