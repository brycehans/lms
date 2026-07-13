import { createClient } from "@/lib/supabase/server";
import { Card, CardContent } from "@/components/ui/card";
import { Building2, School } from "lucide-react";
import { SectionHeading } from "./SectionHeading";

/**
 * The universities we support. `universities` grants select(id, name) to
 * `public` and the `public_read_universities` policy already filters out
 * soft-deleted rows, so this works for anonymous visitors too — no gating.
 */
export async function UniversitiesList() {
  const supabase = await createClient();

  const { data: universities } = await supabase
    .from("universities")
    .select("id, name")
    .order("name", { ascending: true });

  if (!universities || universities.length === 0) return null;

  return (
    <section className="space-y-4">
      <SectionHeading icon={School} title="Supported universities" />
      <ul className="grid gap-3 sm:grid-cols-2">
        {universities.map((u) => (
          <li key={u.id}>
            <Card>
              <CardContent className="flex items-center gap-3 p-4">
                <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <Building2 size={18} />
                </span>
                <span className="font-medium">{u.name}</span>
              </CardContent>
            </Card>
          </li>
        ))}
      </ul>
    </section>
  );
}
