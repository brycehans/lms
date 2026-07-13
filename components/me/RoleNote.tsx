import {
  GraduationCap,
  Telescope,
  ShieldCheck,
  Crown,
  type LucideIcon,
} from "lucide-react";
import type { AppRole } from "./roles";

/**
 * The account-page equivalent of the login screen's role blurbs: for each role
 * the signed-in user holds, an accent callout explaining what that role means
 * for their experience. A user may hold more than one (e.g. student +
 * traveller), so we render one note per role.
 */
const NOTES: Record<
  AppRole,
  { label: string; icon: LucideIcon; blurb: string }
> = {
  student: {
    label: "Student",
    icon: GraduationCap,
    blurb:
      "You book consultations and manage your own bookings — reschedule or cancel upcoming ones, and mark past sessions as complete. You only ever see bookings you made.",
  },
  traveller: {
    label: "Time traveller",
    icon: Telescope,
    blurb:
      "You appear in the public roster and are auto-assigned to students' bookings. You can see the sessions assigned to you; scheduling is driven by the students, so there's nothing here for you to change.",
  },
  admin: {
    label: "Administrator",
    icon: ShieldCheck,
    blurb:
      "You oversee every booking at the universities you administer. This is a read-only vantage point — you don't book, reschedule, or cancel.",
  },
  superadmin: {
    label: "Superadmin",
    icon: Crown,
    blurb:
      "You have an unscoped view of every booking across all universities. Read-only oversight, nothing hidden.",
  },
};

export function RoleNote({ roles }: { roles: AppRole[] }) {
  if (roles.length === 0) {
    return (
      <div className="rounded-md bg-accent p-3 px-5 text-sm text-foreground">
        Your account doesn&apos;t have a role assigned yet, so there&apos;s
        nothing to show. Contact an administrator if you think this is a
        mistake.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {roles.map((role) => {
        const note = NOTES[role];
        const Icon = note.icon;
        return (
          <div
            key={role}
            className="flex gap-3 rounded-md bg-accent p-3 px-5 text-sm text-foreground"
          >
            <Icon
              size={18}
              strokeWidth={2}
              className="mt-0.5 shrink-0 text-primary"
            />
            <p>
              <span className="font-semibold">
                You have assumed role of {note.label}:&nbsp;
              </span>
              {note.blurb}
            </p>
          </div>
        );
      })}
    </div>
  );
}
