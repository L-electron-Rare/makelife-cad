"use client";

import { useState } from "react";
import type { ValidationResult } from "./types";

type SortKey = "filepath" | "status" | "score" | "last_modified";

interface Props {
  results: ValidationResult[];
}

const statusColor: Record<ValidationResult["status"], string> = {
  pass: "#16a34a",
  warn: "#ca8a04",
  fail: "#dc2626",
};

export function AuditTable({ results }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>("status");
  const [asc, setAsc] = useState(true);

  const sorted = [...results].sort((a, b) => {
    const va = a[sortKey] ?? "";
    const vb = b[sortKey] ?? "";
    return asc ? String(va).localeCompare(String(vb)) : String(vb).localeCompare(String(va));
  });

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setAsc(!asc);
    } else {
      setSortKey(key);
      setAsc(true);
    }
  };

  const thStyle: React.CSSProperties = { padding: "8px 16px", textAlign: "left", fontSize: "12px", fontWeight: 600, textTransform: "uppercase", cursor: "pointer", background: "#f9fafb", userSelect: "none" };

  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ minWidth: "100%", fontSize: "14px", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            {(["filepath", "status", "score", "last_modified"] as SortKey[]).map((key) => (
              <th key={key} style={thStyle} onClick={() => handleSort(key)}>
                {key === "filepath" ? "File" : key === "last_modified" ? "Last modified" : key.charAt(0).toUpperCase() + key.slice(1)}
                {sortKey === key ? (asc ? " ↑" : " ↓") : ""}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => (
            <tr key={r.filepath} style={{ borderTop: "1px solid #f3f4f6" }}>
              <td style={{ padding: "8px 16px", fontFamily: "monospace", fontSize: "12px" }}>{r.filepath.split("/").pop()}</td>
              <td style={{ padding: "8px 16px", fontWeight: 600, color: statusColor[r.status] }}>{r.status}</td>
              <td style={{ padding: "8px 16px" }}>{r.score !== undefined ? r.score.toFixed(1) : "—"}</td>
              <td style={{ padding: "8px 16px", color: "#6b7280" }}>
                {r.last_modified ? new Date(r.last_modified).toLocaleDateString() : "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
