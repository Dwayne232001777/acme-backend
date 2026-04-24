const stripe = require("stripe")(process.env.STRIPE_SECRET);
const WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET;
module.exports = function verifyStripeWebhook(req, res, next) {
  const sig = req.headers["stripe-signature"];
  try {
    req.stripeEvent = stripe.webhooks.constructEvent(req.rawBody, sig, WEBHOOK_SECRET);
    next();
  } catch (err) {
    console.error("Invalid Stripe signature", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }
};
