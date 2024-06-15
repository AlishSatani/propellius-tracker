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
