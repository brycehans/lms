<a href="https://demo-nextjs-with-supabase.vercel.app/">
  <img alt="Next.js and Supabase Starter Kit - the fastest way to build apps with Next.js and Supabase" src="https://demo-nextjs-with-supabase.vercel.app/opengraph-image.png">
  <h1 align="center">Next.js and Supabase Starter Kit</h1>
</a>

<p align="center">
 The fastest way to build apps with Next.js and Supabase
</p>

<p align="center">
  <a href="#features"><strong>Features</strong></a> ·
  <a href="#demo"><strong>Demo</strong></a> ·
  <a href="#deploy-to-vercel"><strong>Deploy to Vercel</strong></a> ·
  <a href="#clone-and-run-locally"><strong>Clone and run locally</strong></a> ·
  <a href="#feedback-and-issues"><strong>Feedback and issues</strong></a>
  <a href="#more-supabase-examples"><strong>More Examples</strong></a>
</p>
<br/>

## Sitemap

Reads are **Server Components** hitting the Supabase SDK directly (RLS scopes what
each role sees). Mutations go through **API Route Handlers** that call `SECURITY
DEFINER` RPCs — the only client-writable surface (no direct table DML).

Legend: ✅ built · 🔲 to build · ⚙️ starter-kit sample (not part of the app)

### Pages

```
/                       ✅ public landing (availability calendar, traveller roster, universities)
/book                   ✅ booking form — session dropdown (deep-linked via ?start_at=),
                             editable first/last name (prefilled from profile), reason
/me                     ✅ account page — identity + per-role bookings:
  ├─ student            ✅   own consultations (reason/datetime/traveller/state),
  │                            mark complete/incomplete, cancel, reschedule
  ├─ traveller          ✅   own assigned sessions (read-only)
  └─ admin/superadmin   ✅   oversight — consultations scoped by RLS
                             (admin: their universities · superadmin: all), read-only
  └─ profile edit       🔲   first/last name form (update_profile RPC already exists)
/auth/login             ✅ email + password sign-in (+ one-click demo logins)
/auth/sign-up           ✅ sign-up — captures first/last name + university, which the
                             handle_new_user trigger turns into a profile + student role
                             + enrolment
/auth/sign-up-success   ✅ account-ready notice; email confirmation is OFF, so signup
                             leaves the user logged in and the CTA continues any pending
                             booking
/auth/forgot-password   ✅ request a reset link
/auth/update-password   ✅ set a new password
/auth/confirm           ✅ email-confirmation / OTP callback (route handler)
/auth/error             ✅ auth error page
/protected              ⚙️ starter-kit sample (dumps JWT claims); superseded by /me
```

### API Route Handlers (mutations → RPC)

Every write goes through a handler that calls one `SECURITY DEFINER` RPC — there
is no direct table DML from the client.

```
POST   /api/auth/signup           ✅ -> auth.signUp (metadata drives the profile trigger)
POST   /api/bookings/create       ✅ -> create_booking(starts_at, reason, first_name, last_name)
POST   /api/bookings/cancel       ✅ -> cancel_booking(starts_at)
POST   /api/bookings/reschedule   ✅ -> reschedule_booking(current_start, new_start)
POST   /api/bookings/complete     ✅ -> set_booking_completion(booking_id, is_complete)
       /api/profile               🔲 -> update_profile(first_name, last_name)  (RPC exists, no handler yet)
```

> Booking cancel/reschedule key off `starts_at` (the RPCs identify a booking by
> student + slot), while completion keys off `booking_id`.

## Features

- Works across the entire [Next.js](https://nextjs.org) stack
  - App Router
  - Pages Router
  - Proxy
  - Client
  - Server
  - It just works!
- supabase-ssr. A package to configure Supabase Auth to use cookies
- Password-based authentication block installed via the [Supabase UI Library](https://supabase.com/ui/docs/nextjs/password-based-auth)
- Styling with [Tailwind CSS](https://tailwindcss.com)
- Components with [shadcn/ui](https://ui.shadcn.com/)
- Optional deployment with [Supabase Vercel Integration and Vercel deploy](#deploy-your-own)
  - Environment variables automatically assigned to Vercel project

## Demo

You can view a fully working demo at [demo-nextjs-with-supabase.vercel.app](https://demo-nextjs-with-supabase.vercel.app/).

## Deploy to Vercel

Vercel deployment will guide you through creating a Supabase account and project.

After installation of the Supabase integration, all relevant environment variables will be assigned to the project so the deployment is fully functioning.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fvercel%2Fnext.js%2Ftree%2Fcanary%2Fexamples%2Fwith-supabase&project-name=nextjs-with-supabase&repository-name=nextjs-with-supabase&demo-title=nextjs-with-supabase&demo-description=This+starter+configures+Supabase+Auth+to+use+cookies%2C+making+the+user%27s+session+available+throughout+the+entire+Next.js+app+-+Client+Components%2C+Server+Components%2C+Route+Handlers%2C+Server+Actions+and+Middleware.&demo-url=https%3A%2F%2Fdemo-nextjs-with-supabase.vercel.app%2F&external-id=https%3A%2F%2Fgithub.com%2Fvercel%2Fnext.js%2Ftree%2Fcanary%2Fexamples%2Fwith-supabase&demo-image=https%3A%2F%2Fdemo-nextjs-with-supabase.vercel.app%2Fopengraph-image.png)

The above will also clone the Starter kit to your GitHub, you can clone that locally and develop locally.

If you wish to just develop locally and not deploy to Vercel, [follow the steps below](#clone-and-run-locally).

## Clone and run locally

1. You'll first need a Supabase project which can be made [via the Supabase dashboard](https://database.new)

2. Create a Next.js app using the Supabase Starter template npx command

   ```bash
   npx create-next-app --example with-supabase with-supabase-app
   ```

   ```bash
   yarn create next-app --example with-supabase with-supabase-app
   ```

   ```bash
   pnpm create next-app --example with-supabase with-supabase-app
   ```

3. Use `cd` to change into the app's directory

   ```bash
   cd with-supabase-app
   ```

4. Rename `.env.example` to `.env.local` and update the following:

  ```env
  NEXT_PUBLIC_SUPABASE_URL=[INSERT SUPABASE PROJECT URL]
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=[INSERT SUPABASE PROJECT API PUBLISHABLE OR ANON KEY]
  ```
  > [!NOTE]
  > This example uses `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, which refers to Supabase's new **publishable** key format.
  > Both legacy **anon** keys and new **publishable** keys can be used with this variable name during the transition period. Supabase's dashboard may show `NEXT_PUBLIC_SUPABASE_ANON_KEY`; its value can be used in this example.
  > See the [full announcement](https://github.com/orgs/supabase/discussions/29260) for more information.

  Both `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` can be found in [your Supabase project's API settings](https://supabase.com/dashboard/project/_?showConnect=true)

5. You can now run the Next.js local development server:

   ```bash
   npm run dev
   ```

   The starter kit should now be running on [localhost:3000](http://localhost:3000/).

6. This template comes with the default shadcn/ui style initialized. If you instead want other ui.shadcn styles, delete `components.json` and [re-install shadcn/ui](https://ui.shadcn.com/docs/installation/next)

> Check out [the docs for Local Development](https://supabase.com/docs/guides/getting-started/local-development) to also run Supabase locally.

## Feedback and issues

Please file feedback and issues over on the [Supabase GitHub org](https://github.com/supabase/supabase/issues/new/choose).

## More Supabase examples

- [Next.js Subscription Payments Starter](https://github.com/vercel/nextjs-subscription-payments)
- [Cookie-based Auth and the Next.js 13 App Router (free course)](https://youtube.com/playlist?list=PL5S4mPUpp4OtMhpnp93EFSo42iQ40XjbF)
- [Supabase Auth and the Next.js App Router](https://github.com/supabase/supabase/tree/master/examples/auth/nextjs)
