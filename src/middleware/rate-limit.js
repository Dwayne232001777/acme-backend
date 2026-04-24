const redis = require("./redis");
module.exports = function rateLimit({ key, limit, windowMs }) {
  return async (req, res, next) => {
    const k = `rl:${key}:${req.user.id}`;
    const count = await redis.incr(k);
    if (count === 1) await redis.pexpire(k, windowMs);
    if (count > limit) {
      const ttl = await redis.pttl(k);
      res.set("Retry-After", Math.ceil(ttl / 1000));
      return res.status(429).json({ error: "Too many requests" });
    }
    next();
  };
};
