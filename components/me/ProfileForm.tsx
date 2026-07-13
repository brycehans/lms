"use client";

import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field-error";
import { FormMessage } from "@/components/ui/form-message";
import { errorAttrs } from "@/lib/utils";

type FormValues = {
  firstName: string;
  lastName: string;
};

/**
 * Edit the signed-in user's profile name. POSTs to the profile route (the only
 * client-writable surface), which calls the `update_profile` RPC. On success we
 * refresh the server components so the identity header re-reads the new name.
 *
 * This edits the profile only — booking name snapshots are frozen at creation,
 * so renaming here never rewrites past bookings (that's what /book's per-booking
 * name fields are for).
 */
export function ProfileForm({
  defaultFirstName,
  defaultLastName,
}: {
  defaultFirstName: string;
  defaultLastName: string;
}) {
  const router = useRouter();
  const {
    register,
    handleSubmit,
    reset,
    setError,
    clearErrors,
    formState: { errors, isSubmitting, isSubmitSuccessful },
  } = useForm<FormValues>({
    defaultValues: {
      firstName: defaultFirstName,
      lastName: defaultLastName,
    },
  });

  const onSubmit = async (values: FormValues) => {
    const firstName = values.firstName.trim();
    const lastName = values.lastName.trim();
    try {
      const res = await fetch("/api/profile", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ firstName, lastName }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(json.error ?? "Something went wrong. Please try again.");
      }
      // Reset to the just-saved values so the form is clean (and the success
      // banner only shows while these remain the current values).
      reset({ firstName, lastName });
      router.refresh();
    } catch (error: unknown) {
      setError("root", {
        message: error instanceof Error ? error.message : "An error occurred",
      });
    }
  };

  return (
    <form
      onSubmit={handleSubmit(onSubmit)}
      // Clear the success banner as soon as the user edits again.
      onChange={() => clearErrors("root")}
      className="grid gap-4 sm:grid-cols-2"
    >
      <div className="grid gap-2">
        <Label htmlFor="profile-firstName">First name</Label>
        <Input
          id="profile-firstName"
          type="text"
          {...errorAttrs(!!errors.firstName, "profile-firstName-error")}
          {...register("firstName", { required: "First name is required." })}
        />
        <FieldError id="profile-firstName-error">
          {errors.firstName?.message}
        </FieldError>
      </div>

      <div className="grid gap-2">
        <Label htmlFor="profile-lastName">Last name</Label>
        <Input
          id="profile-lastName"
          type="text"
          {...errorAttrs(!!errors.lastName, "profile-lastName-error")}
          {...register("lastName", { required: "Last name is required." })}
        />
        <FieldError id="profile-lastName-error">
          {errors.lastName?.message}
        </FieldError>
      </div>

      <div className="flex items-center gap-4 sm:col-span-2">
        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Saving…" : "Save changes"}
        </Button>
        <FormMessage variant={errors.root ? "error" : "success"}>
          {errors.root?.message ??
            (isSubmitSuccessful ? "Profile updated." : null)}
        </FormMessage>
      </div>
    </form>
  );
}
