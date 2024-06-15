import * as nodemailer from "nodemailer";
import { mailOptions } from "../config";

export const getEtherealMailTransport = () => {
  if (!mailOptions.host) {
    throw new Error("Misconfiguration: no mail options provided");
  }

  return nodemailer.createTransport(mailOptions);
};
