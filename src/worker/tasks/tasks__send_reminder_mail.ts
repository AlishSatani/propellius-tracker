import { Task } from "graphile-worker";
import { formatDate } from "../../utility";
import { EmailPayload } from "./send_email";

interface Payload {
  taskId: string;
  userId: string;
}

const task: Task = async (payload, { addJob, query }) => {
  const { taskId, userId } = payload as Payload;

  const logme = (...args) =>
    console.log(
      `[tasks__send_reminder_mail] [${taskId}] [${userId}]: `,
      ...args
    );

  const {
    rows: [task],
  } = await query(
    `
    SELECT
        users.email,
        users.username,
        tasks.title,
        tasks.due_date
      FROM app_public.tasks
        join app_public.users
          on tasks.user_id = users.id
      where
        tasks.id = $1
        and users.id = $2
    `,
    [taskId, userId]
  );

  if (!task) return logme("Task not found.");

  const emailPayload: EmailPayload = {
    options: {
      to: task.email,
      subject: "Upcoming events",
      text: `Hello ${task.username}! It's a reminder for ${
        task.title
      } due on ${formatDate(task.due_date, "DD-MM-YYYY")}.`,
    },
  };

  await addJob("send_email", emailPayload);

  return;
};

export default task;
