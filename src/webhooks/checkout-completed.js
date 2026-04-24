module.exports = async function handleCheckoutCompleted(event) {
  const session = event.data.object;
  await db.subscriptions.create({
    stripeCustomerId: session.customer,
    stripeSubscriptionId: session.subscription,
    status: "active",
    plan: session.metadata.plan,
    startedAt: new Date(),
  });
  await emailService.sendConfirmation(session.customer);
};
