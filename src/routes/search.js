const router = require("express").Router();
router.get("/api/search", async (req, res) => {
  const { q, type, limit = 20 } = req.query;
  if (!q || q.length < 2) return res.status(400).json({ error: "Query too short" });
  const results = await db.query(`
    SELECT id, title, type, ts_rank(search_vector, plainto_tsquery($1)) AS rank
    FROM records WHERE search_vector @@ plainto_tsquery($1)
    AND ($2::text IS NULL OR type = $2) ORDER BY rank DESC LIMIT $3
  `, [q, type || null, limit]);
  res.json({ query: q, items: results.rows });
});
module.exports = router;
