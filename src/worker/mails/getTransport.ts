import * as nodemailer from "nodemailer";

import { getEtherealMailTransport } from "./etherealMailTransport";

let transporterPromise: Promise<nodemailer.Transporter>;

export const getTransport = (): Promise<nodemailer.Transporter> => {
  if (!transporterPromise) {
    const getTransporterPromise = async () => {
      return getEtherealMailTransport();
    };

    transporterPromise = getTransporterPromise();
  }

  return transporterPromise!;
};
