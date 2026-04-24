function encodeCursor(ts, id) { return Buffer.from(`${ts}:${id}`).toString("base64url"); }
function decodeCursor(c) {
  const [ts, id] = Buffer.from(c, "base64url").toString().split(":");
  return { ts, id };
}
async function paginatedSearch(query, cursor, limit = 20) {
  const params = [query];
  let where = "WHERE search_vector @@ plainto_tsquery($1)";
  if (cursor) {
    const { ts, id } = decodeCursor(cursor);
    params.push(ts, id);
    where += ` AND (created_at, id) < ($2, $3)`;
  }
  params.push(limit + 1);
  const { rows } = await db.query(`SELECT * FROM records ${where} ORDER BY created_at DESC, id DESC LIMIT $${params.length}`, params);
  const hasMore = rows.length > limit;
  return { items: hasMore ? rows.slice(0, -1) : rows, hasMore };
}
module.exports = { paginatedSearch };
