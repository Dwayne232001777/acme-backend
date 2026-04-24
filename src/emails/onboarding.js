const { Resend } = require("resend");
const resend = new Resend(process.env.RESEND_API_KEY);
const DRIP = [
  { delay: 0, template: "welcome", subject: "Welcome!" },
  { delay: 86400000, template: "getting-started", subject: "Getting started" },
  { delay: 604800000, template: "tips", subject: "Pro tips" },
];
async function onUserCreated(user) {
  for (const step of DRIP) {
    await scheduler.schedule("send_onboarding_email", {
      userId: user.id, email: user.email, template: step.template, subject: step.subject,
    }, { delay: step.delay });
  }
}
module.exports = { onUserCreated };
