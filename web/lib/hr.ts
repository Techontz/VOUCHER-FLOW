"use client";

/*
 * HR Flow & payroll: the shapes /api/erp/hr returns and small helpers the
 * HR screens share. Salary fields are optional everywhere because the API
 * leaves them out for anyone without hr.salary.
 */

export type HrStatusTone = "neutral" | "info" | "ok" | "warn" | "bad";

export interface Ref { id: number; name: string }

export interface HrContract {
  id: number; employee_id: number; type: string; start_date: string; end_date: string | null; status: string; notes: string | null;
  basic_salary?: number; housing_allowance?: number; transport_allowance?: number; other_allowance?: number; gross_salary?: number;
}

export interface HrEmployee {
  id: number; employee_number: string; full_name: string; email: string | null; phone: string | null;
  national_id: string | null; tin: string | null; nssf_number: string | null; date_of_birth: string | null; gender: string | null;
  address: string | null; next_of_kin_name: string | null; next_of_kin_phone: string | null; next_of_kin_relation: string | null;
  employment_type: string; job_title: string | null; grade: string | null; department_id: number | null;
  department?: Ref | null; manager_id: number | null; manager?: { id: number; full_name: string } | null;
  shift_id: number | null; shift?: Ref | null; user_id: number | null; user?: { id: number; name: string; email: string; role: string } | null;
  hire_date: string; probation_end: string | null; heslb_beneficiary: boolean; status: "active" | "suspended" | "exited";
  exit_date: string | null; contract?: HrContract | null; bank_name?: string | null; bank_account_number?: string | null;
  salary_visible: boolean;
}

export interface LeaveType { id: number; code: string; name: string; days_per_year: string | null; paid: boolean; accrues_monthly: boolean; counting: string; is_active: boolean }

export interface LeaveBalance {
  id: number; employee_id: number; leave_type_id: number; leave_type: { id: number; code: string; name: string; paid: boolean };
  year: number; entitled: number; accrued: number; carried_forward: number; adjustment: number; taken: number; available: number | null; limited: boolean;
}

export interface LeaveRequest {
  id: number; employee_id: number; leave_type_id: number; start_date: string; end_date: string; days: string; reason: string | null;
  status: "pending" | "approved" | "rejected" | "cancelled"; decision_note: string | null; decided_at: string | null;
  employee?: { id: number; full_name: string; employee_number?: string; department?: Ref | null };
  leave_type?: { id: number; name: string; code?: string; paid?: boolean }; decider?: Ref | null; can_decide?: boolean;
}

export interface AttendanceRecord {
  id: number; employee_id: number; date: string; check_in: string | null; check_out: string | null;
  status: "present" | "late" | "absent" | "leave" | "off"; hours_worked: string; overtime_hours: string; source: string; note: string | null;
}

export interface Shift { id: number; name: string; start_time: string; end_time: string; grace_minutes: number; is_default: boolean; hours?: number }

export type RunStatus = "draft" | "authorised" | "locked" | "posted" | "paid";

export const RUN_TOTALS = ["basic", "allowances", "overtime", "other_earnings", "absence_deduction", "gross", "nssf_employee", "paye", "heslb", "loans", "other_deductions", "total_deductions", "net", "nssf_employer", "wcf", "sdl"] as const;

export type PayrollRun = {
  id: number; number: string; period: string; period_start: string; period_end: string; status: RunStatus; employees_count: number;
  notes: string | null; prepared_at: string | null; authorised_at: string | null; locked_at: string | null; posted_at: string | null; paid_at: string | null;
  payment_date: string | null; prepared_by: number | null;
  preparer?: Ref | null; authoriser?: Ref | null; locker?: Ref | null; poster?: Ref | null; payer?: Ref | null;
  journal?: { id: number; number: string; status: string; total: string } | null;
  payment_journal?: { id: number; number: string; status: string; total: string } | null;
  payment_account?: { id: number; code: string; name: string } | null;
  rates?: { code: string; name: string; rate: number | null; effective_from: string }[] | Record<string, { code: string; name: string; rate: number | null; effective_from: string }> | null;
} & Record<(typeof RUN_TOTALS)[number], string>;

export const SLIP_MONEY = ["basic", "housing_allowance", "transport_allowance", "other_allowance", "overtime", "other_earnings", "absence_deduction", "gross", "nssf_employee", "taxable", "paye", "heslb", "loans", "other_deductions", "total_deductions", "net", "nssf_employer", "wcf", "sdl"] as const;

export type Payslip = {
  id: number; payroll_run_id: number; employee_id: number; employee_number: string; employee_name: string; department: string | null; job_title: string | null;
  bank_name: string | null; bank_account_number: string | null; days_paid: string; unpaid_days: string; overtime_hours: string;
  lines: { earnings?: { description: string; amount: number }[]; deductions?: { description: string; amount: number }[]; loans?: { number: string; amount: number }[] } | null;
  run?: { id: number; number: string; period: string; status: RunStatus; payment_date?: string | null };
} & Record<(typeof SLIP_MONEY)[number], string>;

/** Numbers from the API arrive as strings or numbers; this reads either. */
export function n(value: string | number | null | undefined): number {
  return Number(value ?? 0);
}

/** "2026-11" as "November 2026" in the reader's language. */
export function monthLabel(period: string, locale: string): string {
  const [y, m] = period.split("-").map(Number);
  return new Date(y, (m || 1) - 1, 1).toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { month: "long", year: "numeric" });
}

export function currentPeriod(offset = 0): string {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function statusTone(status: string): HrStatusTone {
  switch (status) {
    case "active": case "approved": case "paid": case "present": case "completed": case "hired": case "closed": case "filled": return "ok";
    case "pending": case "draft": case "in_progress": case "open": case "planned": case "screening": case "interview": case "offer": case "applied": case "submitted": return "info";
    case "authorised": case "locked": case "posted": return "info";
    case "suspended": case "late": case "leave": case "superseded": return "warn";
    case "rejected": case "absent": case "exited": case "cancelled": return "bad";
    default: return "neutral";
  }
}
