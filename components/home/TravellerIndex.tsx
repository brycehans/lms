import { createClient } from "@/lib/supabase/server";
import { Avatar } from "./Avatar";
import { Card, CardContent } from "@/components/ui/card";
import { Sparkles } from "lucide-react";
import { SectionHeading } from "./SectionHeading";

/**
 * The roster of time travellers. `user_roles` exposes traveller rows (the
 * `allow_authenticated_to_see_travellers` policy) and `profiles` exposes their
 * names (`authenticated_users_browse_travellers`) — but both are `to
 * authenticated`, so an anonymous visitor sees an empty roster. If you want
 * this public for brochureware, the two policies would need a `public` grant.
 */
export async function TravellerIndex() {
  const supabase = await createClient();

  const { data: roles } = await supabase
    .from("user_roles")
    .select("user_id")
    .eq("role", "traveller");

  const ids = [...new Set((roles ?? []).map((r) => r.user_id))];

  const travellers = ids.length
    ? ((
        await supabase
          .from("profiles")
          .select("id, first_name, last_name")
          .in("id", ids)
      ).data ?? [])
    : [];

  return (
    <section className="space-y-4">
      <SectionHeading icon={Sparkles} title="Meet our time travellers" />
      {travellers.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Sign in to meet the certified time travellers ready to prophesy your
          grades.
        </p>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {travellers.map((t) => {
            const name = `${t.first_name} ${t.last_name}`;
            return (
              <li key={t.id}>
                <Card>
                  <CardContent className="flex items-center gap-3 p-4">
                    <Avatar name={name} />
                    <div className="min-w-0">
                      <p className="truncate font-medium">{name}</p>
                      <p className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Sparkles size={12} className="text-primary" />
                        Certified diviner
                      </p>
                    </div>
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
