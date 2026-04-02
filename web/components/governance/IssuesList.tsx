"use client";

import type { ValidationResult } from "./types";

interface Props {
  results: ValidationResult[];
}

const severityOrder: Record<string, number> = { error: 0, warning: 1, info: 2 };
const severityBorder: Record<string, string> = {
  error: "4px solid #ef4444",
  warning: "4px solid #eab308",
  info: "4px solid #3b82f6",
};

export function IssuesList({ results }: Props) {
  const issues = results
    .flatMap((r) => r.details.map((d) => ({ ...d, filepath: r.filepath })))
    .sort((a, b) => (severityOrder[a.severity] ?? 3) - (severityOrder[b.severity] ?? 3));

  if (issues.length === 0) {
    return <p style={{ padding: "16px", color: "#6b7280", fontSize: "14px" }}>No issues found.</p>;
  }

  return (
    <ul style={{ listStyle: "none", padding: "16px", margin: 0, display: "flex", flexDirection: "column", gap: "8px" }}>
      {issues.map((issue, i) => (
        <li key={i} style={{ borderLeft: severityBorder[issue.severity] ?? "4px solid #d1d5db", padding: "8px 12px", borderRadius: "4px", fontSize: "14px", background: "#f9fafb" }}>
          <span style={{ fontWeight: 600, textTransform: "capitalize" }}>{issue.severity}</span>
          {" · "}
          <span style={{ color: "#4b5563" }}>{issue.check}</span>
          {" · "}
          {issue.message}
          <div style={{ fontSize: "12px", color: "#9ca3af", marginTop: "2px", fontFamily: "monospace" }}>{issue.filepath.split("/").pop()}</div>
        </li>
      ))}
    </ul>
  );
}
