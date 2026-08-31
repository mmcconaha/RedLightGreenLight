# Red Light Green Light

One tap tells the band if you're free. No calendar, no explaining, no guilt.

## What's actually built here
- Working respond page (`/session/[id]/respond`) — tap-through grid, writes to Supabase
- Working organizer page (`/session/[id]/organizer`) — merged view + ranked suggestions
- Suggestion scoring in `lib/scoring.ts` (pure math, no AI needed)
- `/api/session/[id]/suggest` — reads the aggregate counts and asks Claude to write a one-line "why" for each suggested window
- `supabase/schema.sql` — full schema with row-level security, so raw availability rows are never directly readable by anyone; the organizer view can only ever see aggregate counts via the `session_summary` function

## What's stubbed / not yet wired up
- No `bands` or `sessions` creation UI yet — you'll need to insert a row into `sessions` manually (or build a quick form) to get an `id` to test with
- Magic-link login for repeat band members isn't wired into the UI — the schema supports it (`members` table, `user_id` column) but the respond page currently always creates a `guest` row
- No deploy config — this runs anywhere Next.js does (Vercel is the path of least resistance)

## Setup
1. Create a Supabase project, run `supabase/schema.sql` in the SQL editor
2. Copy `.env.example` to `.env.local`, fill in your Supabase URL/anon key and an Anthropic API key (optional — without it, suggestions fall back to a plain-language line instead of the LLM blurb)
3. `npm install`
4. `npm run dev`
5. Insert a test row into `sessions` (needs a `band_id`, so insert a `bands` row first), then visit `/session/<that-id>/respond`

## Design notes
Dark stage-light palette on purpose — green/yellow/red read as real traffic-light signals, not brand colors. Grid days/blocks default to Mon–Sat × Morning/Afternoon/Evening but are stored per-session (`sessions.days`, `sessions.blocks`) so this isn't hardcoded if you want finer time slots later.

Privacy is enforced at the database level, not just hidden in the UI — RLS policies mean there's no query path that returns one person's raw answer to anyone but them.
