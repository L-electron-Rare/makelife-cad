/** Mirrors /audit/status response from life-core. */
export interface AuditStatus {
  last_run: string;
  total_audits: number;
  pass: number;
  warn: number;
  fail: number;
  avg_score?: number; // optional, added when AI analysis runs
}

/** One check detail inside a validation result. */
export interface CheckResult {
  check: string;
  severity: "error" | "warning" | "info";
  message: string;
  auto_fixable: boolean;
}

/** Per-file validation result inside /audit/report. */
export interface ValidationResult {
  filepath: string;
  status: "pass" | "warn" | "fail";
  errors: number;
  warnings: number;
  score?: number;
  last_modified?: string;
  details: CheckResult[];
}

/** Cross-analysis findings inside /audit/report. */
export interface CrossAnalysis {
  contradictions: string[];
  untracked_debts: string[];
  coverage_gaps: string[];
}

/** Mirrors /audit/report response from life-core. */
export interface AuditReport {
  timestamp: string;
  total_files: number;
  summary: { pass: number; warn: number; fail: number };
  results: ValidationResult[];
  cross_analysis?: CrossAnalysis;
}
