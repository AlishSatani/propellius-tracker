//TODO: fix credentials
export const fromEmail = "ocie.lebsack@ethereal.email";
export const mailOptions = {
  host: process.env.MAIL_HOST,
  port: process.env.MAIL_PORT,
  auth: {
    user: process.env.MAIL_USER, 
    pass: process.env.MAIL_PASSWORD,
  },
};
