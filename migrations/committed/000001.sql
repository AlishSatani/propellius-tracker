--! Previous: -
--! Hash: sha1:d0e4af26e80cf612c44fbf349fb1c3b12e544a4d

--! split: 1-setup-schema.sql
-- Enter migration here

drop schema if exists app_public cascade;
drop schema if exists app_hidden cascade;
drop schema if exists app_private cascade;

revoke all on schema public from public;

alter default privileges revoke all on sequences from public;
alter default privileges revoke all on functions from public;

grant all on schema public to :DATABASE_OWNER;

create schema app_public;
create schema app_hidden;
create schema app_private;

grant usage on schema public, app_public, app_hidden to :DATABASE_VISITOR;

alter default privileges in schema public, app_public, app_hidden
  grant usage, select on sequences to :DATABASE_VISITOR;

alter default privileges in schema public, app_public, app_hidden
  grant execute on functions to :DATABASE_VISITOR;

--! split: 2-common-triggers.sql
create function app_private.tg__add_job() returns trigger as $$
begin
  perform graphile_worker.add_job(tg_argv[0], json_build_object('id', NEW.id));
  return NEW;
end;
$$ language plpgsql volatile security definer;
comment on function app_private.tg__add_job() is
  E'Useful shortcut to create a job on insert/update. Pass the task name as the first trigger argument, and optionally the queue name as the second argument. The record id will automatically be available on the JSON payload.';

create function app_private.tg__timestamps() returns trigger as $$
begin
  NEW.created_at = (case when TG_OP = 'INSERT' then NOW() else OLD.created_at end);
  NEW.updated_at = (case when TG_OP = 'UPDATE' and OLD.updated_at >= NOW() then OLD.updated_at + interval '1 millisecond' else NOW() end);
  return NEW;
end;
$$ language plpgsql volatile;
comment on function app_private.tg__timestamps() is
  E'This trigger should be called on all tables with created_at, updated_at - it ensures that they cannot be manipulated and that updated_at will always be larger than the previous updated_at.';

--! split: 3-pg-session.sql
create table app_private.connect_pg_simple_sessions (
  sid varchar not null,
	sess json not null,
	expire timestamp not null
);

alter table app_private.connect_pg_simple_sessions
  enable row level security;

alter table app_private.connect_pg_simple_sessions
  add constraint session_pkey primary key (sid) not deferrable initially immediate;

--! split: 4-session.sql
create table app_private.sessions (
  uuid uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  last_active timestamptz not null default now()
);

create index on app_private.sessions (user_id);

alter table app_private.sessions enable row level security;

create function app_public.current_session_id() returns uuid as $$
  select nullif(pg_catalog.current_setting('jwt.claims.session_id', true), '')::uuid;
$$ language sql stable;
comment on function app_public.current_session_id() is
  E'Handy method to get the current session ID.';

create function app_public.current_user_id() returns uuid as $$
  select user_id from app_private.sessions where uuid = app_public.current_session_id();
$$ language sql stable security definer;
comment on function app_public.current_user_id() is
  E'Handy method to get the current user ID for use in RLS policies, etc; in GraphQL, use `currentUser{id}` instead.';

--! split: 5-user.sql
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

--! split: 6-user-secrets.sql
create table app_private.user_secrets (
  user_id uuid not null primary key references app_public.users on delete cascade,
  password_hash text,
  last_login_at timestamptz not null default now(),
  failed_password_attempts int not null default 0,
  first_failed_password_attempt timestamptz
);

alter table app_private.user_secrets enable row level security;

create function app_private.tg_user_secrets__insert_with_user() returns trigger as
$$
begin
  insert into app_private.user_secrets(user_id)
  values (NEW .id);

  return NEW;
end;
$$ language plpgsql volatile;

create trigger _insert_secrets
  after insert on app_public.users
  for each row
  execute procedure app_private.tg_user_secrets__insert_with_user();

--! split: 7-login.sql
create function app_private.login(username citext, password text) returns app_private.sessions as $$
declare
  v_user app_public.users;
  v_user_secret app_private.user_secrets;
  v_login_attempt_window_duration interval = interval '5 minutes';
  v_session app_private.sessions;
begin
  select users.* into v_user
  from app_public.users
  where users.username = login.username or users.email = login.username;

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    -- Have there been too many login attempts?
    if (
      v_user_secret.first_failed_password_attempt is not null
    and
      v_user_secret.first_failed_password_attempt > NOW() - v_login_attempt_window_duration
    and
      v_user_secret.failed_password_attempts >= 3
    ) then
      raise exception 'User account locked - too many login attempts. Try again after 5 minutes.' using errcode = 'LOCKD';
    end if;

    if v_user_secret.password_hash = crypt(password, v_user_secret.password_hash) then
      update app_private.user_secrets
      set failed_password_attempts = 0, first_failed_password_attempt = null, last_login_at = now()
      where user_id = v_user.id;

      insert into app_private.sessions (user_id) values (v_user.id) returning * into v_session;

      return v_session;
    else
      update app_private.user_secrets
      set
        failed_password_attempts = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then 1 else failed_password_attempts + 1 end),
        first_failed_password_attempt = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then now() else first_failed_password_attempt end)
      where user_id = v_user.id;

      return null; -- Must not throw otherwise transaction will be aborted and attempts won't be recorded
    end if;
  else
    return null;
  end if;
end;
$$ language plpgsql strict volatile;

--! split: 8-logout.sql
create function app_public.logout() returns void as $$
begin
  delete from app_private.sessions where uuid = app_public.current_session_id();

  perform set_config('jwt.claims.session_id', '', true);
end;
$$ language plpgsql security definer volatile;

--! split: 9-create-user.sql
create function app_private.assert_valid_password(new_password text) returns void as $$
begin
  if length(new_password) < 8 then
    raise exception 'Password is too weak' using errcode = 'WEAKP';
  end if;
end;
$$ language plpgsql volatile;

create function app_private.really_create_user(
  username citext,
  email citext,
  password text default null
) returns app_public.users as $$
declare
  v_user app_public.users;
  v_username citext = username;
  v_email citext = email;
begin
  if v_username is null or password is null then
    raise exception 'Must provide valid username and password.' using errcode='INVLD';
  end if;

  perform app_private.assert_valid_password(password);

  v_username = regexp_replace(v_username, '^[^a-z]+', '', 'gi');
  v_username = regexp_replace(v_username, '[^a-z0-9]+', '_', 'gi');

  if exists(select 1 from app_public.users where users.username = v_username or users.email = v_email) then
    raise exception 'An account using that username or email has already been created.' using errcode='UMTKN';
  end if;

  insert into app_public.users (username, email)
  values (v_username, v_email)
    returning * into v_user;

  update app_private.user_secrets
  set password_hash = crypt(password, gen_salt('bf'))
  where user_id = v_user.id;

  select * into v_user from app_public.users where id = v_user.id;

  return v_user;
end;
$$ language plpgsql volatile;

--! split: 10-tasks.sql
create table app_public.tasks (
  id uuid primary key default gen_random_uuid(),
  title citext not null,
  description citext not null,
  due_date date not null,
  is_completed boolean not null default false,
  user_id uuid not null default app_public.current_user_id(),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table app_public.tasks
  add constraint tasks_user_id_fkey foreign key ("user_id") references app_public.users on delete cascade;

create index on app_public.tasks("user_id");

create index on app_public.tasks("due_date");

create trigger _timestamps
  before insert or update on app_public.tasks
  for each row execute procedure app_private.tg__timestamps();

alter table app_public.tasks enable row level security;

create policy select_own on app_public.tasks for select using (user_id = app_public.current_user_id());

create policy create_own on app_public.tasks for insert with check (user_id = app_public.current_user_id());

create policy update_own on app_public.tasks for update using (user_id = app_public.current_user_id() and created_at::date = now()::date);

create policy delete_own on app_public.tasks for delete using (user_id = app_public.current_user_id() and created_at::date = now()::date);

grant select, insert, update(title, description, due_date, is_completed), delete on app_public.tasks to :DATABASE_VISITOR;

create or replace function app_public.update_task_status(id uuid, is_completed boolean) returns app_public.tasks as
$$
declare
  v_task app_public.tasks;
begin
  update app_public.tasks
    set is_completed = update_task_status.is_completed
  where
    tasks.id = update_task_status.id
    and tasks.user_id = app_public.current_user_id()
  returning * into v_task;

  if v_task is null then
    raise exception 'You are not authorized to update this task.' using errcode = 'UNATH';
  end if;

  return v_task;
end;
$$ language plpgsql volatile security definer;

create or replace function app_public.delete_today_tasks() returns boolean as
$$
begin
  delete from app_public.tasks
  where
    created_at::date = now()::date
    and user_id = app_public.current_user_id();

  return true;
end;
$$ language plpgsql volatile security definer;

--! split: 11-reminder.sql
create or replace function app_public.add_reminder(id uuid, remind_at timestamptz) returns boolean as
$$
begin
  if not exists (
    select 1 from app_public.tasks
    where
      tasks.id = add_reminder.id
      and tasks.user_id = app_public.current_user_id())
  then
    raise exception 'You are not allowed to get reminder for this task.' using errcode='UNATH';
  end if;

  PERFORM graphile_worker.add_job(
    'tasks__send_reminder_mail',
    json_build_object(
      'taskId', id,
      'userId', app_public.current_user_id()
    ),
    run_at := remind_at,
    -- remove job key to prevent reminders from being overridden and allow multiple reminders for same task
    job_key := 'tasks__send_reminder_mail_' || id
  );

  return true;
end;
$$ language plpgsql volatile security definer;
