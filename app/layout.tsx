import type { Metadata } from "next";
import { Geist } from "next/font/google";
import { ThemeProvider } from "next-themes";
import { FirefoxDevWarning } from "@/components/FirefoxDevWarning";
import "./globals.css";

const defaultUrl = process.env.VERCEL_URL
  ? `https://${process.env.VERCEL_URL}`
  : "http://localhost:1955";

export const metadata: Metadata = {
  metadataBase: new URL(defaultUrl),
  title: {
    default: "Course Prophecies",
    template: "Course Prophecies | %s",
  },
  description:
    "Find out what you scored on your future exams with our time travellers.",
};

const geistSans = Geist({
  variable: "--font-geist-sans",
  display: "swap",
  subsets: ["latin"],
});

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-scroll-behavior="smooth" suppressHydrationWarning>
      <body className={`${geistSans.className} antialiased`}>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
          <FirefoxDevWarning />
        </ThemeProvider>
      </body>
    </html>
  );
}
