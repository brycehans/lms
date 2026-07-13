"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Controller, useForm } from "react-hook-form";
import { CalendarClock } from "lucide-react";

import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { FieldError } from "@/components/ui/field-error";
import { FormMessage } from "@/components/ui/form-message";
import { errorAttrs } from "@/lib/utils";
import { formatSlot } from "@/components/me/booking-utils";

const DAY_MS = 86_400_000;
// How far ahead we offer bookable slots in the dropdown.
const BOOKING_WINDOW_DAYS = 28;

type FormValues = {
  startsAt: string;
  firstName: string;
  lastName: string;
  reason: string;
};

type SlotsStatus = "loading" | "ok" | "error";

/**
 * The booking form. The session dropdown is populated from `list_available_slots`
 * (any-traveller availability — the same RPC the home calendar reads), so every
 * offered slot has at least one free traveller. `initialStart` (from the
 * `?start_at=` deep-link on the calendar's "Open" cells) is preselected.
 *
 * The name fields are prefilled from the caller's profile but are editable: they
 * are what `create_booking` snapshots onto THIS booking, so editing them here
 * changes only this record — never the profile row. Submitting POSTs to the
 * create route (the only client-writable surface), then routes to /me.
 */
export function BookingForm({
  initialStart,
  defaultFirstName,
  defaultLastName,
}: {
  initialStart?: string;
  defaultFirstName: string;
  defaultLastName: string;
}) {
  const router = useRouter();
  const {
    register,
    control,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    defaultValues: {
      startsAt: initialStart ?? "",
      firstName: defaultFirstName,
      lastName: defaultLastName,
      reason: "",
    },
  });

  const [slots, setSlots] = useState<string[]>([]);
  const [slotsStatus, setSlotsStatus] = useState<SlotsStatus>("loading");

  useEffect(() => {
    let cancelled = false;
    setSlotsStatus("loading");
    const now = Date.now();
    const from = new Date(now).toISOString();
    const to = new Date(now + BOOKING_WINDOW_DAYS * DAY_MS).toISOString();

    createClient()
      .rpc("list_available_slots", { p_from: from, p_to: to })
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error || !data) {
          setSlotsStatus("error");
          setSlots([]);
          return;
        }
        // setof timestamptz → bare ISO strings, ascending from the RPC.
        setSlots(data as string[]);
        setSlotsStatus("ok");
      });

    return () => {
      cancelled = true;
    };
  }, []);

  // Options = the fetched slots, plus the deep-linked slot if it isn't already
  // in the list (so the prefill always shows, even at the edge of the window /
  // before the fetch resolves). `create_booking` remains the source of truth —
  // if that slot was taken since the link was minted, the submit is rejected.
  const options = useMemo(() => {
    const all = initialStart && !slots.includes(initialStart)
      ? [initialStart, ...slots]
      : slots;
    return all.map((iso) => ({ iso, label: formatSlot(iso) }));
  }, [slots, initialStart]);

  const onSubmit = async (values: FormValues) => {
    try {
      const res = await fetch("/api/bookings/create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          startsAt: values.startsAt,
          firstName: values.firstName.trim(),
          lastName: values.lastName.trim(),
          reason: values.reason.trim(),
        }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(json.error ?? "Something went wrong. Please try again.");
      }
      router.push("/me");
      router.refresh();
    } catch (error: unknown) {
      setError("root", {
        message: error instanceof Error ? error.message : "An error occurred",
      });
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-lg">
          <CalendarClock size={18} />
          Consultation details
        </CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6">
          {/* Session slot */}
          <div className="grid gap-2">
            <Label htmlFor="startsAt">Session time</Label>
            <Controller
              name="startsAt"
              control={control}
              rules={{ required: "Please pick a session time." }}
              render={({ field }) => (
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger
                    id="startsAt"
                    className="w-full"
                    {...errorAttrs(!!errors.startsAt, "startsAt-error")}
                  >
                    <SelectValue
                      placeholder={
                        slotsStatus === "loading"
                          ? "Loading available times…"
                          : "Pick a session time…"
                      }
                    />
                  </SelectTrigger>
                  <SelectContent>
                    {options.map((o) => (
                      <SelectItem key={o.iso} value={o.iso}>
                        {o.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            />
            {slotsStatus === "error" && (
              <p className="text-sm text-muted-foreground">
                We couldn&apos;t load live availability. Please try again
                shortly.
              </p>
            )}
            {slotsStatus === "ok" && options.length === 0 && (
              <p className="text-sm text-muted-foreground">
                No open slots in the next {BOOKING_WINDOW_DAYS} days.
              </p>
            )}
            <FieldError id="startsAt-error">
              {errors.startsAt?.message}
            </FieldError>
          </div>

          {/* Name snapshot — prefilled from the profile, editable per booking */}
          <fieldset className="grid gap-4 rounded-lg border p-4 sm:grid-cols-2">
            <legend className="px-1 text-sm font-medium">
              Name on this booking
            </legend>
            <div className="grid gap-2">
              <Label htmlFor="firstName">First name</Label>
              <Input
                id="firstName"
                type="text"
                {...errorAttrs(!!errors.firstName, "firstName-error")}
                {...register("firstName", {
                  required: "First name is required.",
                })}
              />
              <FieldError id="firstName-error">
                {errors.firstName?.message}
              </FieldError>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="lastName">Last name</Label>
              <Input
                id="lastName"
                type="text"
                {...errorAttrs(!!errors.lastName, "lastName-error")}
                {...register("lastName", {
                  required: "Last name is required.",
                })}
              />
              <FieldError id="lastName-error">
                {errors.lastName?.message}
              </FieldError>
            </div>
            <p className="text-xs text-muted-foreground sm:col-span-2">
              We snapshot these onto the booking as it stands now — editing them
              here won&apos;t change your profile.
            </p>
          </fieldset>

          {/* Reason */}
          <div className="grid gap-2">
            <Label htmlFor="reason">What would you like prophesied?</Label>
            <Textarea
              id="reason"
              rows={3}
              placeholder="e.g. my final grade for Intro to Chronology"
              {...errorAttrs(!!errors.reason, "reason-error")}
              {...register("reason", {
                required: "Please tell us what to prophesy.",
              })}
            />
            <FieldError id="reason-error">
              {errors.reason?.message}
            </FieldError>
          </div>

          <FormMessage>{errors.root?.message}</FormMessage>

          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? "Booking…" : "Confirm booking"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
