"use client";

import type { CrossAnalysis } from "./types";

interface Props {
  data: CrossAnalysis;
}

function Section({ title, items, emptyMsg }: { title: string; items: string[]; emptyMsg: string }) {
  return (
    <div>
      <h3 style={{ fontSize: "14px", fontWeight: 600, color: "#374151", marginBottom: "8px" }}>{title}</h3>
      {items.length === 0 ? (
        <p style={{ fontSize: "12px", color: "#9ca3af" }}>{emptyMsg}</p>
      ) : (
        <ul style={{ paddingLeft: "16px", margin: 0 }}>
          {items.map((item, i) => (
            <li key={i} style={{ fontSize: "14px", color: "#4b5563", marginBottom: "4px" }}>{item}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function CrossAnalysisPanel({ data }: Props) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: "24px", padding: "16px" }}>
      <Section title="Contradictions" items={data.contradictions} emptyMsg="None detected" />
      <Section title="Untracked debts" items={data.untracked_debts} emptyMsg="None detected" />
      <Section title="Coverage gaps" items={data.coverage_gaps} emptyMsg="None detected" />
    </div>
  );
}
