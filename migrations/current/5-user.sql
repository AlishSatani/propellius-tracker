create table app_public.users (
  id uuid primary key default gen_random_uuid(),
  username citext unique check(
    length(username) >= 2
    and length(username) <= 24
    and username ~ '^[a-zA-Z]([_]?[a-zA-Z0-9])+$'
  ),
  email citext unique not null check (email ~ '[^@]+@[^@]+\.[^@]+'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- We couldn't implement this relationship on the sessions table until the users table existed
alter table app_private.sessions
  add constraint sessions_user_id_fkey foreign key ("user_id") references app_public.users on delete cascade;

alter table app_public.users enable row level security;

create policy select_all on app_public.users for select using (true);

create policy update_self on app_public.users for update using (id = app_public.current_user_id());

grant select on app_public.users to :DATABASE_VISITOR;

create trigger _timestamps
  before insert or update on app_public.users
  for each row execute procedure app_private.tg__timestamps();

create function app_public.current_user() returns app_public.users as $$
  select users. *
  from app_public.users
  where id = app_public.current_user_id();
$$ language sql stable;
