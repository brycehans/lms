"use client";

import { cn, errorAttrs } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/components/ui/field-error";
import { FormMessage } from "@/components/ui/form-message";
import {
  Card,
  CardContent,
  CardDescription,
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
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Controller, useForm } from "react-hook-form";

type University = { id: string; name: string };

type SignUpFormValues = {
  email: string;
  password: string;
  repeatPassword: string;
  firstName: string;
  lastName: string;
  universityId: string;
};

export function SignUpForm({
  universities,
  className,
  next,
  ...props
}: React.ComponentPropsWithoutRef<"div"> & {
  universities: University[];
  next?: string;
}) {
  const router = useRouter();
  const {
    register,
    control,
    handleSubmit,
    getValues,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<SignUpFormValues>();

  const onSubmit = async ({
    email,
    password,
    firstName,
    lastName,
    universityId,
  }: SignUpFormValues) => {
    try {
      const response = await fetch("/api/auth/signup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          password,
          firstName,
          lastName,
          universityId,
        }),
      });

      if (!response.ok) {
        const { error } = await response.json();
        throw new Error(error ?? "An error occurred");
      }

      // Signup leaves the user logged in (email confirmations off), so carry the
      // booking deep-link onto the success page — its CTA continues the booking.
      router.push(
        next
          ? `/auth/sign-up-success?next=${encodeURIComponent(next)}`
          : "/auth/sign-up-success",
      );
    } catch (error: unknown) {
      setError("root", {
        message: error instanceof Error ? error.message : "An error occurred",
      });
    }
  };

  return (
    <div className={cn("flex flex-col gap-6", className)} {...props}>
      <Card>
        <CardHeader>
          <CardTitle className="text-2xl">Sign up</CardTitle>
          <CardDescription>Create a new account</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)}>
            <div className="flex flex-col gap-6">
              <div className="grid gap-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="m@example.com"
                  {...errorAttrs(!!errors.email, "email-error")}
                  {...register("email", { required: "Email is required." })}
                />
                <FieldError id="email-error">
                  {errors.email?.message}
                </FieldError>
              </div>
              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="password">Password</Label>
                </div>
                <Input
                  id="password"
                  type="password"
                  {...errorAttrs(!!errors.password, "password-error")}
                  {...register("password", {
                    required: "Password is required.",
                  })}
                />
                <FieldError id="password-error">
                  {errors.password?.message}
                </FieldError>
              </div>

              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="repeat-password">Repeat Password</Label>
                </div>
                <Input
                  id="repeat-password"
                  type="password"
                  {...errorAttrs(!!errors.repeatPassword, "repeat-password-error")}
                  {...register("repeatPassword", {
                    required: "Please confirm your password.",
                    validate: (value) =>
                      value === getValues("password") ||
                      "Passwords do not match",
                  })}
                />
                <FieldError id="repeat-password-error">
                  {errors.repeatPassword?.message}
                </FieldError>
              </div>
              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="first-name">First Name</Label>
                </div>
                <Input
                  id="first-name"
                  type="text"
                  {...errorAttrs(!!errors.firstName, "first-name-error")}
                  {...register("firstName", {
                    required: "First name is required.",
                  })}
                />
                <FieldError id="first-name-error">
                  {errors.firstName?.message}
                </FieldError>
              </div>
              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="last-name">Last Name</Label>
                </div>
                <Input
                  id="last-name"
                  type="text"
                  {...errorAttrs(!!errors.lastName, "last-name-error")}
                  {...register("lastName", {
                    required: "Last name is required.",
                  })}
                />
                <FieldError id="last-name-error">
                  {errors.lastName?.message}
                </FieldError>
              </div>
              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="university">University</Label>
                </div>
                <Controller
                  name="universityId"
                  control={control}
                  rules={{ required: "Please select your university." }}
                  render={({ field }) => (
                    <Select value={field.value} onValueChange={field.onChange}>
                      <SelectTrigger
                        id="university"
                        className="w-full"
                        {...errorAttrs(
                          !!errors.universityId,
                          "university-error",
                        )}
                      >
                        <SelectValue placeholder="Select your university" />
                      </SelectTrigger>
                      <SelectContent>
                        {universities.map((university) => (
                          <SelectItem key={university.id} value={university.id}>
                            {university.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                />
                <FieldError id="university-error">
                  {errors.universityId?.message}
                </FieldError>
                <p className="text-xs text-muted-foreground">
                  Why do I have to specify my uni? Administrators are
                  per-university, so this lets us demonstrate the app&apos;s
                  tenancy model.
                </p>
              </div>
              <FormMessage>{errors.root?.message}</FormMessage>
              <Button type="submit" className="w-full" disabled={isSubmitting}>
                {isSubmitting ? "Creating an account..." : "Sign up"}
              </Button>
            </div>
            <div className="mt-4 text-center text-sm">
              Already have an account?{" "}
              <Link href="/auth/login" className="underline underline-offset-4">
                Login
              </Link>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
