"use client";

import { cn, safeNext } from "@/lib/utils";
import { createClient } from "@/lib/supabase/client";
import { QuickLogin } from "@/components/QuickLogin";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";

type LoginFormValues = {
  email: string;
  password: string;
};

export function LoginForm({
  className,
  next,
  ...props
}: React.ComponentPropsWithoutRef<"div"> & { next?: string }) {
  const router = useRouter();
  // Where to land after auth: the sanitized `?next=` deep-link (e.g. the booking
  // slot the visitor was gated out of), or their account page by default.
  const dest = safeNext(next);
  const {
    register,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormValues>();

  const onSubmit = async ({ email, password }: LoginFormValues) => {
    const supabase = createClient();

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (error) throw error;
      // Land on the requested deep-link if any, else the user's account page.
      router.push(dest);
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
          <CardTitle className="text-2xl">Login</CardTitle>
        </CardHeader>
        <CardContent>
          {/* Preferred entry for reviewers; self-hides unless demo logins are on. */}
          <QuickLogin className="mb-6" next={dest} />
          <form onSubmit={handleSubmit(onSubmit)}>
            <p className="text-sm mb-4">
              Enter your email below to login to your account
            </p>
            <div className="flex flex-col gap-6">
              <div className="grid gap-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="m@example.com"
                  {...register("email", { required: true })}
                />
              </div>
              <div className="grid gap-2">
                <div className="flex items-center">
                  <Label htmlFor="password">Password</Label>
                  <Link
                    href="/auth/forgot-password"
                    className="ml-auto inline-block text-sm underline-offset-4 hover:underline"
                  >
                    Forgot your password?
                  </Link>
                </div>
                <Input
                  id="password"
                  type="password"
                  {...register("password", { required: true })}
                />
              </div>
              {errors.root && (
                <p className="text-sm text-red-500">{errors.root.message}</p>
              )}
              <Button type="submit" className="w-full" disabled={isSubmitting}>
                {isSubmitting ? "Logging in..." : "Login"}
              </Button>
            </div>
            <div className="mt-4 text-center text-sm">
              Don&apos;t have an account?{" "}
              <Link
                href={
                  next
                    ? `/auth/sign-up?next=${encodeURIComponent(dest)}`
                    : "/auth/sign-up"
                }
                className="underline underline-offset-4"
              >
                Sign up
              </Link>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
