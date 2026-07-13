- redo homepage to show public brochureware if not logged in
  - if logged in, show upcoming consultations
    - if admin, show extra superpowers
- brand is "course prophecies" -- book in a consultation with a time-traveller who knows what grade you got for a subject and you can ask them if you passed

## Questions

learn and remember what `SECURITY DEFINER` in supabase does to enforce RBAC constraints in the model level

db design constraint: "students are Enrolled in one uni at a time" -- how would the app/design change if students could be enrolled in multiple unis? or if travellers were uni-scoped?

```
  Bookings need a university_id so admins can filter by "their" uni. It comes from the student's enrollment — but denormalize it onto the
  booking at creation, don't join through to the student's current uni.

  Reason: a student who transfers unis shouldn't retroactively drag their past bookings into the new uni's admin view. The booking
  happened at UTS; it stays UTS forever. Freezing the tenant at creation keeps history correct and means admin scope queries never chase
  a moving value. Prophecies inherit the uni through their booking — no column needed.
```

"users" table is called "profiles" because - by convention with supabase - and to avoid conceptual conflict with supabase auth.users table - even though separated by schema, better for devs to not be confused since they often need to both be referenced

DB: name fields use `TEXT` not `VARCHAR(n)` because in postgres, they have the same implementation/perf but varchar just enforces a length constraint. If there's no business rule behind this, we shouldn't enforce length here. Presentaition layer truncation can happen in view layer.

db: users are soft-deletable, this would be troublesome if we needed GDPR compliance with real hard-deletes etc: you'd need a real delete cascae on `profiles(id)`

```
The one gap to accept consciously: you can't distinguish "consult happened" from "student no-showed" — both are just "past, not
  cancelled." For a toy, probably fine. If you ever want no-show tracking, that's when a real status enum (or an attended_at) earns its
  place. Just know the door's slightly ajar there.
```

- homepage should show weekly business-hours calendar with "n available 1-hour slots" for users, with CTA to sign up / sign in to commit to a session. authed users should see their sessions in that calendar rather than just unavailable blocks. if a user who is both a student and a traveller already has a session booked, they can't book another in the same timeslot as their other role. (can't be in two places at once)

re: deleting -- user deletion cascade is blocked by FK on delete no action, but we want oauth disconnect (unlink identity) to succeed without tearing apart the row integrity

- RLS is row-level, not column-level. This policy lets a user change any column on their own row (name, created_at, deleted_at). That's
  fine here — and notice why: there's no role column on profiles to escalate with. Roles live in user_roles. This is your junction-table
  design decision quietly paying a security dividend — if roles were a column on profiles, this same policy would let anyone promote
  themselves to superadmin.

- APIs: supabase is designed to work without a server where you can keep secrets and trust payloads so the architecture it supports is a little different to a simple db layer. this assignment requires the use of server-side APIs so we need to build compat with that workflow. using server side machine-to-db calls is a simpler security model than FE-to-supabase so when hooked up we'll write as though supabase is only hit via our server layer. this means we must enforce connection origins etc but it also frees us up to send sensitive content in there and have supabase layer trust that input is not directly from clients.

decision: only students can make a booking.

Q: why have a user roles table when student status can be derived from enrolment rows, and admins from their administration roles?

A:

```

admin lives in user_roles and has university_administrations bindings. Nobody would say "the admin role is
redundant because you could derive it from who administers a university." The two aren't the same fact:

- user_roles.role = the persona — what this person is (student / traveller / admin / superadmin).
- the junction table = the binding/scope — the specific relationship (which unis they administer, which uni
  they're enrolled at).

  The one real risk you've identified is that persona and binding can drift (a student role with no enrolment, or
  vice versa). But the fix for that — if you even want it in a toy — is a write-path invariant (a trigger keeping
  them consistent), not deleting either table. For Course Prophecies that's overkill; just be aware the door's ajar.

```

schema stress testing:
the plan.md open questions: what changes if students can enrol in multiple unis at once (your
student_enrolments PK currently forbids it), or if travellers become uni-scoped? This stress-tests the tenancy model you just froze.

Demo ergonomics: we should make an account switcher, and maybe also a seed button so they can see valid-to-their-current-week kinds of data. or "sign in as student with existing bookings", "sign in as student with no bookings", "sign in as admin of XYZ uni", "sign in as superadmin" etc.

onboarding: signup needs an onboarding blocker where students pick the uni they're enrolled in.

complete/incomplete toggle: can only be done by a student. why? it makes more sense for the prophesying traveller to mark off having delivered a consultation/booking, but in the reqs doc, the functionality is directly bulleted under the student auth area mention.
students don't re-enrol themselves into arbitrary universities

rls vs rpc: we expose mutations via rpc calls which have security definer permissions so rls does nothign for them. but we use rls for read calls which don't require rpc indirection

local supabase via dockerisation -- why not dockerise the next app for full uniformity? next has already a good local setup system and the network fiddly bits are a big cost compared to the relative cost of having the native machine own the runtime.

local supabase 0.0.0.0 bind exposed: Just don't demo it from public wifi with the stack exposed.

annoying duplications:
1: valid booking times are written in a domain check, in prose on the website and also in another place in the rpc layer. This is annoying and all three must stay in sync.
   - PARTIALLY ADDRESSED: the rpc/generator copies (previously spelled out inline
     in both `list_available_slots` and `list_reschedule_slots`) are now DRY'd
     behind `private.is_bookable_slot(timestamptz)` — see migration
     `20260713163940_extract_is_bookable_slot.sql`. Still a conscious 3-way
     contract to keep in sync by hand: (a) the `is_bookable_start_time` DOMAIN
     (rejects bad inputs at cast time), (b) `is_bookable_slot` (filters generated
     candidate slots — same rule, different job, so it mirrors rather than reuses
     the domain), and (c) the `'Australia/Melbourne'` tz constant + the prose on
     the website. Deliberately did NOT collapse the domain into the helper:
     redefining an applied domain cascades to every column/signature that
     references `is_bookable_start_time`.

reschedule slot mismatch (fixed): the reschedule dropdown was populated by
`list_available_slots` — the NEW-booking query ("is there >=1 traveller free?").
But `reschedule_booking` keeps the SAME assigned traveller and also checks the
student's own calendar, so it rejected slots where that specific traveller was
busy (another being free) or the student was already booked. Fix: new
`list_reschedule_slots(p_current_start, p_from, p_to)` RPC whose predicate mirrors
reschedule_booking's checks exactly (migration
`20260713163529_list_reschedule_slots.sql`); `components/me/StudentBookings.tsx`
now calls it.
