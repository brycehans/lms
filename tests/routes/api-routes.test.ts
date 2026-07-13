import { describe, it, expect, beforeEach, vi } from "vitest";

// ============================================================================
// API route-handler smoke tests.
//
// The route handlers are the app's ONLY write surface: each one shape-validates
// the JSON body, calls exactly one SECURITY DEFINER RPC (or GoTrue), and maps a
// DB error to a 400. The RPCs themselves are exhaustively tested in pgTAP
// (supabase/tests/); here we mock the Supabase client and assert the thin HTTP
// contract around them — validation, the right RPC name + argument mapping, and
// error/success propagation. No database is involved.
// ============================================================================

// Hoisted so the vi.mock factory below can close over them.
const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  maybeSingle: vi.fn(),
  signUp: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    rpc: h.rpc,
    // supports the signup route's `.from("universities").select("id").eq("id", …).maybeSingle()`
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({ maybeSingle: h.maybeSingle })),
      })),
    })),
    auth: { signUp: h.signUp },
  })),
}));

import { POST as createBooking } from "@/app/api/bookings/create/route";
import { POST as cancelBooking } from "@/app/api/bookings/cancel/route";
import { POST as rescheduleBooking } from "@/app/api/bookings/reschedule/route";
import { POST as completeBooking } from "@/app/api/bookings/complete/route";
import { POST as updateProfile } from "@/app/api/profile/route";
import { POST as signup } from "@/app/api/auth/signup/route";

const json = (body: unknown) =>
  new Request("http://test/api", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

const notJson = () =>
  new Request("http://test/api", { method: "POST", body: "}{ not json" });

beforeEach(() => {
  h.rpc.mockReset().mockResolvedValue({ error: null });
  h.maybeSingle.mockReset().mockResolvedValue({ data: { id: "u1" }, error: null });
  h.signUp.mockReset().mockResolvedValue({ error: null });
});

describe("POST /api/bookings/create", () => {
  it("rejects a malformed JSON body with 400", async () => {
    const res = await createBooking(notJson());
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it.each([
    { firstName: "A", lastName: "B", reason: "r" }, // missing startsAt
    { startsAt: "2026-01-01T00:00:00Z", lastName: "B", reason: "r" }, // missing firstName
    { startsAt: "2026-01-01T00:00:00Z", firstName: "A", reason: "r" }, // missing lastName
    { startsAt: "2026-01-01T00:00:00Z", firstName: "A", lastName: "B" }, // missing reason
  ])("400s when a required field is missing (%#)", async (body) => {
    const res = await createBooking(json(body));
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("calls create_booking with trimmed args and returns ok", async () => {
    const res = await createBooking(
      json({ startsAt: "2026-08-03T00:00:00Z", firstName: "  Sam  ", lastName: "  Owner  ", reason: "  exam  " }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(h.rpc).toHaveBeenCalledWith("create_booking", {
      p_starts_at: "2026-08-03T00:00:00Z",
      p_reason: "exam",
      p_first_name: "Sam",
      p_last_name: "Owner",
    });
  });

  it("surfaces the RPC error message as a 400", async () => {
    h.rpc.mockResolvedValue({ error: { message: "that slot was just taken" } });
    const res = await createBooking(
      json({ startsAt: "2026-08-03T00:00:00Z", firstName: "Sam", lastName: "Owner", reason: "exam" }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "that slot was just taken" });
  });
});

describe("POST /api/bookings/cancel", () => {
  it("400s on a missing startsAt without calling the RPC", async () => {
    const res = await cancelBooking(json({}));
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("calls cancel_booking with the slot", async () => {
    const res = await cancelBooking(json({ startsAt: "2026-08-03T00:00:00Z" }));
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith("cancel_booking", { p_starts_at: "2026-08-03T00:00:00Z" });
  });

  it("propagates the RPC error as 400", async () => {
    h.rpc.mockResolvedValue({ error: { message: "no live booking" } });
    const res = await cancelBooking(json({ startsAt: "2026-08-03T00:00:00Z" }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "no live booking" });
  });
});

describe("POST /api/bookings/reschedule", () => {
  it.each([{ newStart: "x" }, { currentStart: "x" }, {}])(
    "400s when currentStart/newStart is missing (%#)",
    async (body) => {
      const res = await rescheduleBooking(json(body));
      expect(res.status).toBe(400);
      expect(h.rpc).not.toHaveBeenCalled();
    },
  );

  it("maps both slots onto reschedule_booking args", async () => {
    const res = await rescheduleBooking(
      json({ currentStart: "2026-08-03T00:00:00Z", newStart: "2026-08-04T00:00:00Z" }),
    );
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith("reschedule_booking", {
      p_current_start: "2026-08-03T00:00:00Z",
      p_new_start: "2026-08-04T00:00:00Z",
    });
  });
});

describe("POST /api/bookings/complete", () => {
  it("requires isComplete to be a boolean, not just truthy", async () => {
    const res = await completeBooking(json({ bookingId: "b1", isComplete: "yes" }));
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("passes a false isComplete through (un-complete is a real operation)", async () => {
    const res = await completeBooking(json({ bookingId: "b1", isComplete: false }));
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith("set_booking_completion", {
      p_booking_id: "b1",
      p_is_complete: false,
    });
  });
});

describe("POST /api/profile", () => {
  it("400s when a name field is not a string", async () => {
    const res = await updateProfile(json({ firstName: "A" }));
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("calls update_profile with the raw names (RPC trims/validates)", async () => {
    const res = await updateProfile(json({ firstName: "New", lastName: "Name" }));
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith("update_profile", {
      p_first_name: "New",
      p_last_name: "Name",
    });
  });
});

describe("POST /api/auth/signup", () => {
  it("400s when a required field is missing", async () => {
    const res = await signup(json({ email: "a@b.co", password: "pw", firstName: "A", lastName: "B" }));
    expect(res.status).toBe(400);
    expect(h.signUp).not.toHaveBeenCalled();
  });

  it("rejects an unknown university before creating the account", async () => {
    h.maybeSingle.mockResolvedValue({ data: null, error: null });
    const res = await signup(
      json({ email: "a@b.co", password: "pw", firstName: "A", lastName: "B", universityId: "nope" }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "Invalid university selection" });
    expect(h.signUp).not.toHaveBeenCalled();
  });

  it("passes names + university into signUp metadata on success", async () => {
    const res = await signup(
      json({ email: "a@b.co", password: "pw", firstName: "A", lastName: "B", universityId: "u1" }),
    );
    expect(res.status).toBe(200);
    expect(h.signUp).toHaveBeenCalledWith(
      expect.objectContaining({
        email: "a@b.co",
        password: "pw",
        options: { data: { first_name: "A", last_name: "B", university_id: "u1" } },
      }),
    );
  });

  it("surfaces a GoTrue signUp error as 400", async () => {
    h.signUp.mockResolvedValue({ error: { message: "User already registered" } });
    const res = await signup(
      json({ email: "a@b.co", password: "pw", firstName: "A", lastName: "B", universityId: "u1" }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "User already registered" });
  });
});
