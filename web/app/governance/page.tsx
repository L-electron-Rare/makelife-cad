import { GovernanceDashboard } from "../../components/governance/GovernanceDashboard";

export const metadata = { title: "Governance Dashboard" };

export default function GovernancePage() {
  return (
    <main style={{ minHeight: "100vh", background: "#f9fafb" }}>
      <div style={{ maxWidth: "1152px", margin: "0 auto", padding: "32px 0" }}>
        <h1 style={{ fontSize: "24px", fontWeight: 700, color: "#111827", marginBottom: "24px", padding: "0 16px" }}>
          Governance Dashboard
        </h1>
        <GovernanceDashboard />
      </div>
    </main>
  );
}
