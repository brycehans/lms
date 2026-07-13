import type { Metadata } from "next";
import { ForgotPasswordForm } from "@/components/forgot-password-form";
import { BrandMark } from "@/components/BrandMark";

export const metadata: Metadata = {
  title: "Reset your password",
};

export default function Page() {
  return (
    <div className="flex min-h-svh w-full items-center justify-center bg-gradient-to-b from-accent/50 to-background p-6 md:p-10">
      <div className="flex w-full max-w-sm flex-col items-center gap-6">
        <BrandMark />
        <ForgotPasswordForm className="w-full" />
      </div>
    </div>
  );
}
