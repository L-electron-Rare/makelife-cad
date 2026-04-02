"use client";

import type { ReactNode } from "react";
import { useAuditData } from "./hooks/useAuditData";
import { StatusBar } from "./StatusBar";
import { AuditTable } from "./AuditTable";
import { IssuesList } from "./IssuesList";
import { CrossAnalysisPanel } from "./CrossAnalysisPanel";

interface Props {
  /** Override fetch base URL — useful when env var name differs. */
  apiBaseUrl?: string;
}

export function GovernanceDashboard(_props: Props) {
  const { status, report, loading, error, refresh } = useAuditData();

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "192px", color: "#9ca3af" }}>
        Loading audit data…
      </div>
    );
  }

  if (error) {
    return (
      <div style={{ padding: "16px", color: "#dc2626" }}>
        <p style={{ fontWeight: 600 }}>Failed to load audit data</p>
        <p style={{ fontSize: "14px", marginTop: "4px" }}>{error}</p>
        <button onClick={refresh} style={{ marginTop: "8px", fontSize: "14px", textDecoration: "underline", background: "none", border: "none", cursor: "pointer", color: "#dc2626" }}>
          Retry
        </button>
      </div>
    );
  }

  if (!status || !report) return null;

  const section = (title: string, children: ReactNode) => (
    <section style={{ background: "#fff", borderRadius: "8px", border: "1px solid #e5e7eb", overflow: "hidden", boxShadow: "0 1px 2px rgba(0,0,0,0.05)" }}>
      <header style={{ padding: "12px 16px", borderBottom: "1px solid #f3f4f6", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <h2 style={{ fontWeight: 600, color: "#1f2937", margin: 0 }}>{title}</h2>
      </header>
      {children}
    </section>
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "16px", padding: "16px" }}>
      <StatusBar status={status} />
      {section("Audit files", <AuditTable results={report.results} />)}
      {section("Issues", <IssuesList results={report.results} />)}
      {report.cross_analysis &&
        section("Cross-analysis", <CrossAnalysisPanel data={report.cross_analysis} />)}
    </div>
  );
}
