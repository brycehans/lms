import { createClient } from "@/lib/supabase/server";
import { gravatarUrl } from "@/lib/gravatar";
import { Avatar } from "./Avatar";
import { Card, CardContent } from "@/components/ui/card";
import { GraduationCap } from "lucide-react";

/**
 * Logged-in user's identity card: gravatar (from their auth email), name (own
 * profile row, visible via the `users_can_see_their_own_profiles` RLS policy),
 * and enrolled university.
 *
 * CONTRACT — enrolled university:
 *   `student_enrolments` currently has RLS enabled but NO select policy and NO
 *   grant, so it's deny-all to `authenticated` and the query below returns
 *   nothing. To light this up, expose a self-read, e.g.:
 *
 *     grant select on public.student_enrolments to authenticated;
 *     create policy read_own_enrolment on public.student_enrolments
 *       for select to authenticated
 *       using (student_id = auth.uid());
 *
 *   (universities already grants select(id, name) to public, so the embedded
 *   `universities(name)` join resolves once the enrolment row is readable.)
 *   Until then this degrades to "Not enrolled yet".
 */
export async function ProfileSummary({
  userId,
  email,
}: {
  userId: string;
  email?: string;
}) {
  const supabase = await createClient();

  const { data: profile } = await supabase
    .from("profiles")
    .select("first_name, last_name")
    .eq("id", userId)
    .maybeSingle();

  const { data: enrolment } = await supabase
    .from("student_enrolments")
    .select("universities(name)")
    .eq("student_id", userId)
    .maybeSingle();

  const name = profile
    ? `${profile.first_name} ${profile.last_name}`
    : (email ?? "You");

  // supabase-js types an embedded to-one as an array in some versions; be lax.
  const uni = enrolment?.universities as { name: string } | null | undefined;
  const universityName = Array.isArray(uni) ? uni[0]?.name : uni?.name;

  return (
    <Card>
      <CardContent className="flex items-center gap-4 p-5">
        <Avatar
          name={name}
          src={email ? gravatarUrl(email) : undefined}
          className="size-16 text-lg"
        />
        <div className="min-w-0">
          <p className="text-lg font-semibold leading-tight">{name}</p>
          <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
            <GraduationCap size={15} strokeWidth={2} />
            {universityName ?? "Not enrolled yet"}
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
