-- Red Light Green Light -- unified "My Calendar" connections
-- Run this in the Supabase SQL editor (Project > SQL Editor > New query).
--
-- Unlike apple_credentials (keyed on member_id -- one row per band
-- membership), this table is keyed on user_id (auth.users.id) directly, so
-- a person connects Google/Apple ONCE and it applies across every band and
-- session they're part of, instead of reconnecting per band membership.
--
-- Google: since the app stays in Google's "Testing" publishing status
-- (verification explicitly out of scope for the private beta), a stored
-- refresh token still expires after 7 days -- that's a Google policy for
-- unverified apps, not something we control. google_token_expires_at tracks
-- that so the UI can prompt "reconnect" proactively instead of only finding
-- out when a refresh call fails.
--
-- Same security posture as apple_credentials: RLS enabled, ZERO policies.
-- The anon/authenticated client can never read or write this table at all,
-- from any device, even a user's own row -- only the server-side
-- service-role client (app/api/my-calendar/*) can touch it.

create table user_calendar_connections (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade not null,
  provider text not null check (provider in ('google', 'apple')),

  -- Apple (CalDAV) fields
  apple_email text,
  encrypted_password text,

  -- Google (OAuth) fields
  google_email text,
  encrypted_refresh_token text,
  google_token_expires_at timestamptz,

  updated_at timestamptz default now(),
  unique (user_id, provider)
);

alter table user_calendar_connections enable row level security;
-- Deliberately no policies -- see comment above.
