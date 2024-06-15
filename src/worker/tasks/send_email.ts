import { Task } from "graphile-worker";
import { getTestMessageUrl } from "nodemailer";
import { fromEmail } from "../config";

import { getTransport } from "../mails";

export interface EmailPayload {
  options: {
    from?: string;
    to: string | string[];
    subject: string;
    text: string;
  };
  //* can add other variables related to templates
}

const task: Task = async (payload) => {
  const { options } = payload as EmailPayload;

  const transport = await getTransport();

  const emailOptions = {
    from: fromEmail,
    ...options,
  };

  const info = await transport.sendMail(emailOptions);

  const url = getTestMessageUrl(info);

  if (url) {
    console.log(`Development email preview: ${url}`);
  }
};

export default task;
