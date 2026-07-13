-- FIX: cancel_booking could "succeed" without cancelling the live booking.
--
-- The original (20260712110829) resolved its target by (starts_at, student_id)
-- filtering only deleted_at is null + starts_at > now() — NOT cancelled_at is
-- null. The partial unique indexes (student_in_timeslot, 20260712102006) enforce
-- uniqueness among ACTIVE rows only, so a book → cancel → rebook of the same slot
-- leaves two rows sharing (starts_at, student_id): one cancelled, one live. A
-- `select … into` with no `strict`/`order by` then takes an arbitrary row; if it
-- picks the already-cancelled one it re-stamps cancelled_at, returns success, and
-- the LIVE booking survives a cancel the student believes happened.
--
-- reschedule_booking (20260712114536) resolves the same way but already includes
-- `cancelled_at is null` — under the partial index that predicate guarantees at
-- most one matching row. cancel_booking was the odd one out; this aligns it.
--
-- CONTRACT CHANGE: this drops the old "idempotent re-cancel" behaviour. Once a
-- booking is cancelled it no longer matches, so cancelling twice now raises
-- "nothing to cancel". That is the more honest contract now that rebooking a
-- cancelled slot is possible — "cancel" should only ever act on the live row.
create or replace function public.cancel_booking(p_starts_at timestamptz)
  returns void
  security definer
  set search_path = ''
  language plpgsql
  as $$
declare
  target_booking uuid;
begin
  select
    id
  into
    target_booking
  from
    public.bookings
  where
    public.bookings.starts_at = p_starts_at
    and public.bookings.student_id = auth.uid()
    and public.bookings.deleted_at is null
    and public.bookings.cancelled_at is null -- only ever cancel the LIVE row
    and public.bookings.starts_at > now();
  if target_booking is null then
    raise exception 'no live booking for this student at this time slot (already cancelled, passed, or never existed). cancelling nothing!';
  end if;
  update
    public.bookings
  set
    cancelled_at = now()
  where
    public.bookings.id = target_booking;
end;
$$;
