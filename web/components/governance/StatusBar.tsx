"use client";

import type { AuditStatus } from "./types";

interface Props {
  status: AuditStatus;
}

export function StatusBar({ status }: Props) {
  const lastRun = status.last_run !== "unknown"
    ? new Date(status.last_run).toLocaleString()
    : "—";

  return (
    <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "12px", padding: "16px", borderBottom: "1px solid #e5e7eb" }}>
      <span style={{ background: "#dcfce7", color: "#166534", borderRadius: "9999px", padding: "4px 12px", fontSize: "14px", fontWeight: 600 }}>
        Pass <strong>{status.pass}</strong>
      </span>
      <span style={{ background: "#fef9c3", color: "#854d0e", borderRadius: "9999px", padding: "4px 12px", fontSize: "14px", fontWeight: 600 }}>
        Warn <strong>{status.warn}</strong>
      </span>
      <span style={{ background: "#fee2e2", color: "#991b1b", borderRadius: "9999px", padding: "4px 12px", fontSize: "14px", fontWeight: 600 }}>
        Fail <strong>{status.fail}</strong>
      </span>
      <span style={{ marginLeft: "auto", fontSize: "13px", color: "#6b7280" }}>
        Last run: <time dateTime={status.last_run}>{lastRun}</time>
      </span>
      {status.avg_score !== undefined && (
        <span style={{ fontSize: "13px", color: "#6b7280" }}>
          Avg AI score: <strong>{status.avg_score.toFixed(1)}</strong>
        </span>
      )}
    </div>
  );
}
