# School Management Platform

Front + backend, same pattern as Style NG: Supabase for the backend (database,
auth, row-level security), plain HTML/React-via-CDN for the frontend — no
build step, so it deploys straight to Vercel by drag-and-drop.

## Files
- `schema.sql` — full database schema + row-level security policies. Run this
  once in your Supabase project's SQL editor.
- `admin.html` — the staff dashboard: students, attendance, teacher check-in,
  fees & payments, report cards, admissions, announcements, CBT.
- `index.html` — the public marketing/landing page with the pricing card and
  a sign-up form that saves leads straight into the `leads` table.

## Setup (15–20 minutes)

1. **Create a Supabase project** at supabase.com (free tier is fine to start).
2. **Run the schema**: open the SQL editor in Supabase, paste in the full
   contents of `schema.sql`, and run it. This creates every table and turns
   on row-level security so one school can never see another school's data.
3. **Create your first school row**: in the Supabase Table Editor, add a row
   to `schools` (name, a slug, your brand color).
4. **Create your first admin user**: in Supabase Authentication, add a user
   with an email + password. Then add a matching row in `profiles` with that
   user's `id`, the `school_id` from step 3, `role = 'school_admin'`.
5. **Plug in your keys**: in both `admin.html` and `index.html`, replace
   `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` with the values from
   Supabase → Settings → API.
6. **Deploy**: drag both files (plus schema.sql for reference) into a new
   Vercel project, or push to GitHub and import into Vercel. `index.html`
   becomes your public marketing page; share `admin.html` as the login link
   for school staff.

## How it's structured for multiple schools

Every table carries a `school_id`. Row-level security policies mean a
logged-in user only ever sees rows belonging to their own school — so this
one deployment can serve many schools at once (each school just needs a row
in `schools` and its own admin login), the same way you'd pitch it as a
subscription product rather than building one-off sites per school.

## What's next to build out

This scaffold gives you working CRUD for every module in the flyer. Natural
next additions, in rough priority order:
1. **CBT question editor + student-facing test-taking screen** (schema is
   ready — `cbt_questions`, `cbt_submissions`, `cbt_answers` — just needs UI).
2. **Assessment score entry** feeding automatically into report card averages.
3. **Branded per-school theming** (logo + primary_color from the `schools`
   table applied to the admin sidebar).
4. **Parent-facing view** (read-only: their child's attendance, fees, report
   card) — the `parent` role is already in the schema.
5. **Payment gateway webhooks** (Paystack/Remita/PalmPay) writing straight
   into `payments`, matching the reconciliation work you already do manually.
