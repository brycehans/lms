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

@scripts/db/seed.sql -- selecting on non-unique data (first_name) only works for toys. real version would have to select on a provably unique column

- homepage should show weekly business-hours calendar with "n available 1-hour slots" for users, with CTA to sign up / sign in to commit to a session. authed users should see their sessions in that calendar rather than just unavailable blocks. if a user who is both a student and a traveller already has a session booked, they can't book another in the same timeslot as their other role. (can't be in two places at once)

re: deleting -- user deletion cascade is blocked by FK on delete no action, but we want oauth disconnect (unlink identity) to succeed without tearing apart the row integrity
