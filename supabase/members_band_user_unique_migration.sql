-- Prevents a person from ever ending up with two `members` rows on the
-- same band. Found 2026-09-02: Malarie hit this two ways in one sitting --
-- once as a genuine duplicate (client-side double-submit on the new
-- "add myself as a member" flow), and once as a stale row from an old,
-- abandoned Supabase auth account (malariemcconaha@gmail.com, since
-- deleted) that had joined the same bands as her real login
-- (m.mcconaha@feverdreamevents.com). Either way, a second members row for
-- the same (band_id, user_id) silently breaks anything that does a
-- single-row lookup keyed on user_id + band_id (My Calendar's aggregation
-- picks one of the two arbitrarily; a couple of `.single()`/`.maybeSingle()`
-- calls in the app start erroring outright).
--
-- Run this once in the Supabase SQL Editor. Safe to run even if a
-- duplicate still exists elsewhere -- Postgres will refuse to add the
-- constraint and tell you which (band_id, user_id) pair is still doubled
-- up, rather than silently deleting anything.
alter table members
  add constraint members_band_user_unique unique (band_id, user_id);
