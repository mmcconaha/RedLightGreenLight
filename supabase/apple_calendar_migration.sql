-- Red Light Green Light — Apple/iCloud calendar sync
-- Run this in the Supabase SQL editor (Project > SQL Editor > New query).
--
-- Stores each member's Apple ID email + an ENCRYPTED app-specific password
-- (encrypted in the app before it ever reaches this table — see
-- lib/appleCrypto.ts — never plaintext). Row Level Security is enabled with
-- NO policies at all, which means the anon/authenticated client can never
-- read or write this table directly, from any device, even the member's
-- own row. Only the server-side service-role client (used inside
-- app/api/apple/*) can touch it. This is intentional and stricter than
-- most of this app's other tables — there's no reason a browser ever needs
-- direct access to an encrypted credential blob.

create table apple_credentials (
  id uuid primary key default uuid_generate_v4(),
  member_id uuid references members(id) on delete cascade not null unique,
  apple_email text not null,
  encrypted_password text not null,
  updated_at timestamptz default now()
);

alter table apple_credentials enable row level security;
-- Deliberately no policies — see comment above.
