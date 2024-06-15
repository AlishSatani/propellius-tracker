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
