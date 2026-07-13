import type { Metadata } from "next";
import { AlertTriangle } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BrandMark } from "@/components/BrandMark";
import { Suspense } from "react";

export const metadata: Metadata = {
  title: "Something went wrong",
};

async function ErrorContent({
  searchParams,
}: {
  searchParams: Promise<{ error: string }>;
}) {
  const params = await searchParams;

  return (
    <>
      {params?.error ? (
        <p className="text-sm text-muted-foreground">
          Code error: {params.error}
        </p>
      ) : (
        <p className="text-sm text-muted-foreground">
          An unspecified error occurred.
        </p>
      )}
    </>
  );
}

export default function Page({
  searchParams,
}: {
  searchParams: Promise<{ error: string }>;
}) {
  return (
    <div className="flex min-h-svh w-full items-center justify-center bg-gradient-to-b from-accent/50 to-background p-6 md:p-10">
      <div className="flex w-full max-w-sm flex-col items-center gap-6">
        <BrandMark />
        <div className="flex w-full flex-col gap-6">
          <Card>
            <CardHeader>
              <span className="mb-1 inline-flex size-11 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                <AlertTriangle size={24} />
              </span>
              <CardTitle className="text-2xl">
                Sorry, something went wrong.
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Suspense>
                <ErrorContent searchParams={searchParams} />
              </Suspense>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
