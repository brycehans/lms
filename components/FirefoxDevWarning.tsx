"use client";

import { useEffect, useState } from "react";
import { TriangleAlert, X } from "lucide-react";

const DISMISS_KEY = "firefox-dev-warning-dismissed";

/**
 * Bottom bar warning graders/devs about the known Firefox reload loop in
 * `next dev` (upstream Next bug — see CLAUDE.md "Known issues"). It's dev-only
 * and Firefox-only, so we only render it under those conditions to avoid crying
 * wolf. Dismissal is remembered for the session.
 *
 * Detection runs in an effect (never during SSR) so the server and first client
 * render agree — the bar fades in only after we've confirmed the browser.
 */
export function FirefoxDevWarning() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (process.env.NODE_ENV !== "development") return;
    const isFirefox = navigator.userAgent.toLowerCase().includes("firefox");
    if (!isFirefox) return;
    if (sessionStorage.getItem(DISMISS_KEY) === "1") return;
    setShow(true);
  }, []);

  if (!show) return null;

  return (
    <div
      role="status"
      className="fixed inset-x-0 bottom-0 z-50 border-t border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100"
    >
      <div className="mx-auto flex max-w-5xl items-start gap-3 px-4 py-2.5 text-sm">
        <TriangleAlert size={16} className="mt-0.5 shrink-0" />
        <p className="flex-1">
          <span className="font-medium">Heads up — you&apos;re on Firefox.</span>{" "}
          A{" "}
          <a
            href="https://github.com/vercel/next.js/issues/94634"
            target="_blank"
            rel="noreferrer"
            className="font-medium underline underline-offset-2"
          >
            known upstream Next.js dev-server bug
          </a>{" "}
          can make pages reload in a loop in Firefox (dev only — never in a
          production build; fixed in Next 16.3). It&apos;s harmless to the app.
          For a smooth local demo, use <span className="font-medium">Chrome</span>
          .
        </p>
        <button
          type="button"
          aria-label="Dismiss warning"
          className="-m-1 shrink-0 rounded p-1 hover:bg-amber-100 dark:hover:bg-amber-900"
          onClick={() => {
            sessionStorage.setItem(DISMISS_KEY, "1");
            setShow(false);
          }}
        >
          <X size={16} />
        </button>
      </div>
    </div>
  );
}
