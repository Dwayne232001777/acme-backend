const BOM = "\ufeff";
function writeCSV(stream, rows) {
  stream.write(BOM);
  for (const row of rows) {
    stream.write(row.map(escapeCell).join(",") + "\n");
  }
}
function escapeCell(v) {
  const s = String(v ?? "");
  return /[,"\n]/.test(s) ? `"${s.replace(/"/g, )}"` : s;
}
module.exports = { writeCSV };
