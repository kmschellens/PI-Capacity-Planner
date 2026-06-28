create table profiles (
  id uuid references auth.users not null,
  updated_at timestamp with time zone,
  username text unique,
  avatar_url text,
  website text,

  primary key (id),
  unique(username),
  constraint username_length check (char_length(username) >= 3)
);

alter table profiles enable row level security;

create policy "Public profiles are viewable by the owner."
  on profiles for select
  using ( auth.uid() = id );

create policy "Users can insert their own profile."
  on profiles for insert
  with check ( auth.uid() = id );

create policy "Users can update own profile."
  on profiles for update
  using ( auth.uid() = id );

create table boards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null default auth.uid(),
  name text not null,
  state jsonb not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint board_name_length check (char_length(trim(name)) >= 1)
);

create unique index boards_user_name_unique
  on boards (user_id, lower(trim(name)));

create table board_collaborators (
  id uuid primary key default gen_random_uuid(),
  board_id uuid references boards on delete cascade not null,
  user_email text not null,
  permission text not null default 'read' check (permission in ('read', 'write')),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint board_collaborator_email_length check (char_length(trim(user_email)) >= 3),
  unique (board_id, user_email)
);

create or replace function board_access_permission(check_board_id uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when exists (
      select 1 from boards
      where id = check_board_id
        and user_id = auth.uid()
    ) then 'owner'
    else coalesce((
      select permission from board_collaborators
      where board_id = check_board_id
        and lower(user_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      limit 1
    ), 'none')
  end;
$$;

create or replace function preserve_board_owner()
returns trigger
language plpgsql
as $$
begin
  new.user_id := old.user_id;
  return new;
end;
$$;

create trigger boards_preserve_owner
  before update on boards
  for each row execute function preserve_board_owner();

alter table boards enable row level security;
alter table board_collaborators enable row level security;

create policy "Users can view accessible boards."
  on boards for select
  using ( board_access_permission(id) in ('owner', 'read', 'write') );

create policy "Users can insert their own boards."
  on boards for insert
  with check ( auth.uid() = user_id );

create policy "Owners and writers can update boards."
  on boards for update
  using ( board_access_permission(id) in ('owner', 'write') )
  with check ( board_access_permission(id) in ('owner', 'write') );

create policy "Users can delete their own boards."
  on boards for delete
  using ( auth.uid() = user_id );

create policy "Accessible users can view board collaborators."
  on board_collaborators for select
  using ( board_access_permission(board_id) in ('owner', 'read', 'write') );

create policy "Owners can add board collaborators."
  on board_collaborators for insert
  with check ( board_access_permission(board_id) = 'owner' );

create policy "Owners can update board collaborators."
  on board_collaborators for update
  using ( board_access_permission(board_id) = 'owner' )
  with check ( board_access_permission(board_id) = 'owner' );

create policy "Owners can delete board collaborators."
  on board_collaborators for delete
  using ( board_access_permission(board_id) = 'owner' );

-- Set up Realtime
begin;
  drop publication if exists supabase_realtime;
  create publication supabase_realtime;
commit;
alter publication supabase_realtime add table profiles;
alter publication supabase_realtime add table boards;
alter publication supabase_realtime add table board_collaborators;

-- Set up Storage
insert into storage.buckets (id, name)
values ('avatars', 'avatars');

create policy "Avatar images are publicly accessible."
  on storage.objects for select
  using ( bucket_id = 'avatars' );

create policy "Anyone can upload an avatar."
  on storage.objects for insert
  with check ( bucket_id = 'avatars' );

create policy "Anyone can update an avatar."
  on storage.objects for update
  with check ( bucket_id = 'avatars' );
