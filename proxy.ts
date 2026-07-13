import { updateSession } from "@/lib/supabase/proxy";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Optional site-wide HTTP Basic Auth gate.
 *
 * Enabled only when `DEMO_BASIC_AUTH` ("user:password") is set — which we do on
 * the hosted Vercel demo and never locally, so graders who clone the repo are
 * never prompted. It runs on the edge before any Supabase work and gates
 * *everything* the middleware matches (pages AND `/api/**`, including the
 * one-click Quick-login panel). That edge gate is what lets us safely publish
 * demo credentials: only a reviewer who clears Basic Auth reaches the app at
 * all, so it stands in for Vercel Access Protection without needing a paid plan.
 *
 * Deliberately a server-only var (no `NEXT_PUBLIC_` prefix) so the password
 * never ships in the client bundle.
 */
function basicAuthGate(request: NextRequest): NextResponse | null {
  const expected = process.env.DEMO_BASIC_AUTH;
  if (!expected) return null; // gate disabled — the default (e.g. local dev)

  const challenge = () =>
    new NextResponse("Authentication required.", {
      status: 401,
      headers: {
        "WWW-Authenticate":
          'Basic realm="Course Prophecies (demo)", charset="UTF-8"',
      },
    });

  const header = request.headers.get("authorization");
  if (!header?.startsWith("Basic ")) return challenge();

  let decoded: string;
  try {
    decoded = atob(header.slice("Basic ".length).trim());
  } catch {
    return challenge();
  }

  return timingSafeEqual(decoded, expected) ? null : challenge();
}

/**
 * Constant-time string comparison — avoids leaking the password via response
 * timing. Length is compared first (which does leak length), acceptable for a
 * shared demo secret.
 */
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

export async function proxy(request: NextRequest) {
  const gate = basicAuthGate(request);
  if (gate) return gate;

  return await updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - images - .svg, .png, .jpg, .jpeg, .gif, .webp
     * Feel free to modify this pattern to include more paths.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
