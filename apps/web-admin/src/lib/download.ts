"use client";

/** Triggers a browser download of `content` as a file. Client-only. */
export function downloadText(
  filename: string,
  content: string,
  mime = "text/csv;charset=utf-8",
) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
