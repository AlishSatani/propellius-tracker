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
