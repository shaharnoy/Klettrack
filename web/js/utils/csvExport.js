export function escapeCSVCell(value) {
  const text = String(value ?? "");
  if (!text) {
    return "";
  }
  if (text.includes(",") || text.includes("\"") || text.includes("\n")) {
    return `"${text.replaceAll("\"", "\"\"")}"`;
  }
  return text;
}

export function buildCSV(columns, rows) {
  const header = columns.map((column) => escapeCSVCell(column.label)).join(",");
  const body = rows
    .map((row) => columns.map((column) => escapeCSVCell(row[column.key])).join(","))
    .join("\n");
  return body.length > 0 ? `${header}\n${body}` : header;
}

export function downloadCSV({ filename, csvText }) {
  const blob = new Blob([csvText], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = sanitizeFileName(filename);
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function sanitizeFileName(value) {
  const safe = String(value || "export.csv").replaceAll(/[^a-zA-Z0-9._-]/g, "-");
  return safe.endsWith(".csv") ? safe : `${safe}.csv`;
}
