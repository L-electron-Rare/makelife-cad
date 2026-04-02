"use client";

import { useEffect, useState, useCallback } from "react";
import type { AuditStatus, AuditReport } from "../types";

const LIFE_CORE_URL = process.env.NEXT_PUBLIC_LIFE_CORE_URL ?? "http://localhost:8000";
const POLL_INTERVAL_MS = 30_000;

export interface AuditDataState {
  status: AuditStatus | null;
  report: AuditReport | null;
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

export function useAuditData(): AuditDataState {
  const [status, setStatus] = useState<AuditStatus | null>(null);
  const [report, setReport] = useState<AuditReport | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [statusRes, reportRes] = await Promise.all([
        fetch(`${LIFE_CORE_URL}/audit/status`),
        fetch(`${LIFE_CORE_URL}/audit/report`),
      ]);
      if (!statusRes.ok || !reportRes.ok) {
        throw new Error(`Fetch failed: status=${statusRes.status} report=${reportRes.status}`);
      }
      const [statusData, reportData] = await Promise.all([
        statusRes.json() as Promise<AuditStatus>,
        reportRes.json() as Promise<AuditReport>,
      ]);
      setStatus(statusData);
      setReport(reportData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const id = setInterval(fetchData, POLL_INTERVAL_MS);
    return () => clearInterval(id);
  }, [fetchData]);

  return { status, report, loading, error, refresh: fetchData };
}
