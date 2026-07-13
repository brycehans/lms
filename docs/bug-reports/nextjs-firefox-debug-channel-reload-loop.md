# Bug report (draft): Firefox dev-server hard reload loop via React debug channel

> **DO NOT FILE — already tracked and fixed upstream.**
> This turned out to be a known bug: vercel/next.js#94634, fixed by
> vercel/next.js#94128 (merged 2026-05-26). Root cause matches this draft
> exactly — Firefox keeps `PerformanceNavigationTiming.transferSize === 0` for
> the whole window while a streaming body arrives, so `wasServedFromCache()` in
> `debug-channel.js` false-positives and the `location.reload()` safety net
> loops.
>
> Introduced in `16.2.1-canary.46`; fixed in `16.3.0-canary.30`. As of this
> writing the fix is only on `canary` / `preview` — stable `latest` is still
> `16.2.10` (what we ship), so we keep the Chrome guidance + warning bar until
> 16.3 goes stable. Kept for the investigation record only.

## Summary

With `cacheComponents: true`, the Next.js **dev server** puts Firefox into an
infinite full-page reload loop (~3 reloads/sec) on any route that renders
dynamic (uncached) content inside a Suspense boundary. The reload originates
inside Next's own dev **React debug channel**
(`next/dist/client/dev/debug-channel.js`), which calls `location.reload()` when
it believes the document was served from cache but cannot restore the debug
channel from `sessionStorage`.

- **Dev-only.** A production build never ships the debug channel, so it never
  reproduces in prod.
- **Firefox-only.** Chrome does not reload-loop (it revalidates the document, so
  `PerformanceNavigationTiming.transferSize` is non-zero and the guarded branch
  is skipped).
- `experimental.reactDebugChannel` defaults to `true`, so no user opt-in is
  required to hit this.

## Environment

- Next.js: **16.2.10**
- React / React-DOM: 19.2.7
- Node: 24.17.0
- OS: macOS 26.4 (Darwin)
- Browser: **Firefox** (reproduces) — exact version: `TODO`
- Not reproduced in: Chrome
- Relevant config: `next.config.ts` → `{ cacheComponents: true }` (no other
  experimental flags; `experimental.reactDebugChannel` is left at its default
  of `true`)

## Steps to reproduce

1. A Next 16.2.10 app with `cacheComponents: true`.
2. A route that renders dynamic content (reads cookies / `Date.now()` / an
   uncached DB query) inside `<Suspense>`.
3. `next dev`, open the route in **Firefox**.
4. Reload the page a couple of times.

**Expected:** the page loads and stays put.

**Actual:** Firefox enters a full-document reload loop (~290ms cadence). No
console error, no build error, no HMR/Fast-Refresh activity. It reloads before
React hydrates.

## Evidence

Captured server-side (via a logging proxy) and client-side (via a parse-time
`<script>` beacon, since the loop is pre-hydration):

- Requests are **full document navigations**, not RSC/prefetch:
  `sec-fetch-mode: navigate`, `sec-fetch-dest: document`, `rsc: null`,
  `next-router-prefetch: null`.
- `PerformanceNavigationTiming.type === "reload"` on every load.
- `PerformanceNavigationTiming.transferSize === 0` on every load (Firefox
  serves the document from cache).
- The auth-cookie value is byte-identical across loads → not an auth/session
  issue; no token rotation, no redirect.
- The loop is **pre-hydration**: the parse-time script fires with
  `document.readyState === "loading"` and no post-hydration `useEffect` runs
  before the next reload.
- `self.__next_r` is `null` on the cache-served document, while `sessionStorage`
  accumulates multiple `__next_debug_channel:<requestId>` entries whose ids do
  not match — so the restore lookup fails.
- A `beforeunload` stack trace points at `createDebugChannel` →
  Turbopack module instantiation (Next dev client), i.e. not application code.

## Root cause

`next/dist/client/dev/debug-channel.js`, `createDebugChannel()`:

```js
if (!requestHeaders && wasServedFromCache()) {
  const readable = restoreDebugChannelFromSessionStorage(requestId);
  if (readable) {
    return { readable };
  }
  // Debug channel can't be restored — debug deps would block hydration.
  // Force a fresh page load from the server. ...
  location.reload();               // <-- the loop
  return { readable: new ReadableStream() };
}
```

where:

```js
function wasServedFromCache() {
  const entry = performance.getEntriesByType('navigation')[0];
  return entry?.transferSize === 0;   // true in Firefox for these loads
}
```

The loop:

1. Firefox serves the dev `/me` document from cache → `transferSize === 0` →
   `wasServedFromCache()` is `true`.
2. `restoreDebugChannelFromSessionStorage(requestId)` returns `undefined` (the
   `requestId` — `self.__next_r` — doesn't match a stored entry; observed
   `null`).
3. → `location.reload()`.
4. The reload is again served from cache → back to step 1, forever.

The debug channel is created unconditionally on the client when the feature is
enabled (`next/dist/client/app-index.js`):

```js
if (process.env.__NEXT_DEV_SERVER && process.env.__NEXT_REACT_DEBUG_CHANNEL && typeof window !== 'undefined') {
  const { createDebugChannel } = require('./dev/debug-channel');
  debugChannel = createDebugChannel(undefined);
}
```

and `__NEXT_REACT_DEBUG_CHANNEL` comes from `experimental.reactDebugChannel`,
which **defaults to `true`** (`next/dist/server/config-shared.js`, in
`defaultConfig.experimental`).

Why an app-level `Cache-Control: no-store` header cannot work around it: in dev,
Next hardcodes the document cache-control and discards any computed value
(`next/dist/server/base-server.js`):

```js
if (this.dev) {
  res.setHeader('Cache-Control', 'no-cache, must-revalidate');
  cacheControl = undefined;
}
```

`no-cache` still allows Firefox to satisfy the reload from cache
(`transferSize === 0`); only `no-store` would prevent it, and middleware/route
attempts to set it are overwritten by the line above.

## Suggested fixes (for maintainers)

- Don't treat `transferSize === 0` as "served from cache" in Firefox without a
  corroborating signal, or fall back to re-establishing the channel instead of
  an unconditional `location.reload()` (which can loop when the reloaded
  document is itself cache-served).
- Guard against reload loops (e.g. cap reload attempts per document, or key off
  a monotonically changing marker so a second identical cache-serve doesn't
  reload again).
- Consider emitting `Cache-Control: no-store` for dev HTML so the browser always
  fetches fresh, side-stepping the `transferSize === 0` heuristic entirely.

## Workaround

Set `experimental.reactDebugChannel: false` in `next.config.ts` (disables the
debug channel and the reload path; costs some dev-tooling introspection), or use
Chrome for local development. This project has chosen to keep the feature on and
develop in Chrome — see `CLAUDE.md` → Known issues.
