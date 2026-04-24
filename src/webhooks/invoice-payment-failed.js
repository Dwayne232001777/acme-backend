const MAX_RETRIES = 3;
const RETRY_DELAYS = [60000, 300000, 900000];
module.exports = async function handleInvoicePaymentFailed(event) {
  const invoice = event.data.object;
  const attempt = invoice.attempt_count || 1;
  if (attempt <= MAX_RETRIES) {
    await scheduler.schedule("retry_payment", {
      invoiceId: invoice.id, customerId: invoice.customer, attempt: attempt + 1,
    }, { delay: RETRY_DELAYS[attempt - 1] });
  } else {
    await db.subscriptions.update({ stripeCustomerId: invoice.customer }, { status: "past_due" });
    await emailService.sendPaymentFailedFinal(invoice.customer, invoice.id);
  }
};
