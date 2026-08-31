-- Red Light Green Light — schema
-- Run in the Supabase SQL editor for a fresh project.

create extension if not exists "uuid-ossp";

create table bands (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  owner_id uuid references auth.users(id) not null,
  created_at timestamptz default now()
);

create table members (
  id uuid primary key default uuid_generate_v4(),
  band_id uuid references bands(id) on delete cascade not null,
  name text not null,
  contact text, -- email or phone, used for magic link
  user_id uuid references auth.users(id), -- set once they've logged in
  created_at timestamptz default now()
);

create table sessions (
  id uuid primary key default uuid_generate_v4(),
  band_id uuid references bands(id) on delete cascade not null,
  title text not null,
  days text[] not null default '{"Mon","Tue","Wed","Thu","Fri","Sat"}',
  blocks text[] not null default '{"Morning","Afternoon","Evening"}',
  created_at timestamptz default now()
);

-- One-off respondents who never create an account.
create table guests (
  id uuid primary key default uuid_generate_v4(),
  session_id uuid references sessions(id) on delete cascade not null,
  display_name text not null,
  created_at timestamptz default now()
);

create table availability (
  id uuid primary key default uuid_generate_v4(),
  session_id uuid references sessions(id) on delete cascade not null,
  member_id uuid references members(id) on delete cascade,
  guest_id uuid references guests(id) on delete cascade,
  day_index int not null,
  block_index int not null,
  status text not null check (status in ('green','yellow','red')),
  updated_at timestamptz default now(),
  constraint one_responder check (
    (member_id is not null and guest_id is null) or
    (member_id is null and guest_id is not null)
  ),
  unique (session_id, member_id, day_index, block_index),
  unique (session_id, guest_id, day_index, block_index)
);

-- Row Level Security: individual availability rows are never readable
-- directly by other participants — only the aggregate view below is.
alter table availability enable row level security;
alter table members enable row level security;
alter table bands enable row level security;

-- Band owner can manage their band + members.
create policy "owner manages band" on bands
  for all using (auth.uid() = owner_id);

create policy "owner manages members" on members
  for all using (
    band_id in (select id from bands where owner_id = auth.uid())
  );

-- A responder can insert/update their own rows only.
create policy "member writes own availability" on availability
  for insert with check (member_id in (select id from members where user_id = auth.uid()));
create policy "member updates own availability" on availability
  for update using (member_id in (select id from members where user_id = auth.uid()));

-- Nobody selects raw availability rows directly from the client.
-- The organizer view reads from the aggregate function below instead.
create policy "no direct reads" on availability for select using (false);

-- Aggregate function: this is the ONLY way individual answers become visible,
-- and it only ever returns counts, never which member said what.
create or replace function session_summary(p_session_id uuid)
returns table (
  day_index int,
  block_index int,
  green int,
  yellow int,
  red int,
  responded int
) language sql security definer as $$
  select
    day_index,
    block_index,
    count(*) filter (where status = 'green')::int,
    count(*) filter (where status = 'yellow')::int,
    count(*) filter (where status = 'red')::int,
    count(*)::int
  from availability
  where session_id = p_session_id
  group by day_index, block_index;
$$;
