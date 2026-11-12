"use client";

import { type ReactNode, useEffect, useState } from "react";
import { api, ApiError, download, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { amount, type Permission, useErp } from "@/lib/erp";
import { type LeaveBalance, monthLabel, n, type Payslip, statusTone } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";

/*
 * Pieces the HR screens share: a gate that admits any of several
 * permissions, status badges, a field-driven form dialog that shows the
 * API's per-field errors, and the payslip view used by payroll and My HR.
 */

/** The HR module gate, open to anyone holding at least one of `anyOf`. */
export function HrGate({ anyOf, children }: { anyOf: Permission[]; children: ReactNode }) {
  return (
    <ErpGate module="hr">
      <AnyOf anyOf={anyOf}>{children}</AnyOf>
    </ErpGate>
  );
}

function AnyOf({ anyOf, children }: { anyOf: Permission[]; children: ReactNode }) {
  const { t } = useApp();
  const { can } = useErp();
  if (!anyOf.some((p) => can(p))) return <EmptyState icon="ph-lock-simple" title={t("erpNoAccess")} />;
  return <>{children}</>;
}

const STATUS_KEY: Record<string, MessageKey> = {
  active: "hrStActive", suspended: "hrStSuspended", exited: "hrStExited",
  pending: "hrStPending", approved: "hrStApproved", rejected: "hrStRejected", cancelled: "hrStCancelled",
  draft: "hrStDraft", authorised: "hrStAuthorised", locked: "hrStLocked", posted: "hrStPosted", paid: "hrStPaid",
  present: "hrStPresent", late: "hrStLate", absent: "hrStAbsent", leave: "hrStLeave", off: "hrStOff",
  open: "hrStOpen", closed: "hrStClosed", filled: "hrStFilled", in_progress: "hrStInProgress", completed: "hrStCompleted",
  planned: "hrStPlanned", submitted: "hrStSubmitted", superseded: "hrStSuperseded", ended: "hrStEnded", settled: "hrStSettled",
  applied: "hrStApplied", screening: "hrStScreening", interview: "hrStInterview", offer: "hrStOffer", hired: "hrStHired",
};

export function useStatusLabel() {
  const { t } = useApp();
  return (status: string) => (STATUS_KEY[status] ? t(STATUS_KEY[status]) : status.replace(/_/g, " "));
}

export function HrStatus({ status }: { status: string }) {
  const label = useStatusLabel();
  return <Badge tone={statusTone(status)} dot>{label(status)}</Badge>;
}

/** Money as the screens show it: grouped, two decimals only when there are cents. */
export function Tzs({ value }: { value: string | number | null | undefined }) {
  return <span className="tnum">{amount(value ?? 0)}</span>;
}

export interface FieldSpec {
  name: string;
  label: string;
  type?: "text" | "number" | "date" | "month" | "time" | "email" | "select" | "textarea" | "checkbox" | "file";
  options?: { value: string | number; label: string }[];
  required?: boolean;
  hint?: string;
  /** Spans the whole row. */
  wide?: boolean;
}

export type FormValues = Record<string, string | boolean | File | null>;

/**
 * A dialog that renders `fields`, submits the values and shows the API's
 * field errors under each field and its message at the top.
 */
interface FormDialogProps {
  open: boolean; title: string; fields: FieldSpec[]; initial?: FormValues; submitLabel?: string; intro?: ReactNode;
  tone?: "info" | "warn" | "bad";
  onClose: () => void; onSubmit: (values: FormValues) => Promise<void>;
}

/* Mounted only while open, so every opening starts from `initial`. */
export function FormDialog(props: FormDialogProps) {
  return props.open ? <FormDialogBody {...props} /> : null;
}

function FormDialogBody({ open, title, fields, initial, submitLabel, onClose, onSubmit, intro, tone }: FormDialogProps) {
  const { t } = useApp();
  const [values, setValues] = useState<FormValues>(initial ?? {});
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true); setError(null);
    try {
      await onSubmit(values);
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  const set = (name: string, value: string | boolean | File | null) => setValues((v) => ({ ...v, [name]: value }));

  return (
    <Dialog open={open} wide={fields.length > 4} title={title} onClose={onClose} busy={busy} tone={tone}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>{submitLabel ?? t("erpSave")}</button>
      </>}>
      {intro}
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <div className="erp-form-grid">
        {fields.map((f) => {
          const id = `hrf-${f.name}`;
          const value = values[f.name];
          const err = error?.field(f.name);
          const style = f.wide ? { gridColumn: "1 / -1" } : undefined;
          if (f.type === "checkbox") {
            return (
              <label key={f.name} className="erp-check" style={style}>
                <input type="checkbox" checked={!!value} onChange={(e) => set(f.name, e.target.checked)} />
                <span><span className="erp-check-label">{f.label}</span>{f.hint && <span className="erp-check-hint">{f.hint}</span>}</span>
              </label>
            );
          }
          return (
            <div key={f.name} style={style}>
              <Field label={f.label} htmlFor={id} required={f.required} hint={f.hint} error={err}>
                {f.type === "select" ? (
                  <select id={id} className="input" value={String(value ?? "")} onChange={(e) => set(f.name, e.target.value)}>
                    <option value="">-</option>
                    {f.options?.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                ) : f.type === "textarea" ? (
                  <textarea id={id} className="input" rows={3} value={String(value ?? "")} onChange={(e) => set(f.name, e.target.value)} />
                ) : f.type === "file" ? (
                  <input id={id} className="input" type="file" accept=".csv,text/csv" onChange={(e) => set(f.name, e.target.files?.[0] ?? null)} />
                ) : (
                  <input id={id} className="input" type={f.type ?? "text"} value={String(value ?? "")} onChange={(e) => set(f.name, e.target.value)} />
                )}
              </Field>
            </div>
          );
        })}
      </div>
    </Dialog>
  );
}

/** Empty strings become null, number fields numbers, so the API's validation reads them right. */
export function payload(values: FormValues, numbers: string[] = []): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(values)) {
    if (v === "" || v === undefined) out[k] = null;
    else if (numbers.includes(k) && typeof v === "string") out[k] = Number(v);
    else out[k] = v;
  }
  return out;
}

export interface Lookups {
  departments: { id: number; name: string }[];
  shifts: { id: number; name: string }[];
  employees: { id: number; full_name: string; employee_number: string; department_id: number | null; job_title: string | null; user_id: number | null }[];
}

/** Departments, shifts and people for pickers; empty lists for callers without hr.view. */
export function useLookups(): Lookups {
  const { can } = useErp();
  const allowed = can("hr.view");
  const [data, setData] = useState<Lookups>({ departments: [], shifts: [], employees: [] });
  useEffect(() => {
    if (allowed) api.get<{ data: Lookups }>("/erp/hr/lookups").then((r) => setData(r.data)).catch(() => undefined);
  }, [allowed]);
  return data;
}

/** One payslip, laid out like the printed one. */
export function PayslipView({ slip }: { slip: Payslip }) {
  const { t, locale } = useApp();
  const lines = slip.lines ?? {};
  const earnings: [string, number][] = [
    [t("hrBasic"), n(slip.basic)], [t("hrHousing"), n(slip.housing_allowance)], [t("hrTransport"), n(slip.transport_allowance)],
    [t("hrOtherAllowance"), n(slip.other_allowance)], [`${t("hrOvertime")} (${n(slip.overtime_hours)} h)`, n(slip.overtime)],
    ...(lines.earnings ?? []).map((l): [string, number] => [l.description, n(l.amount)]),
    [`${t("hrAbsenceDeduction")} (${n(slip.unpaid_days)})`, -n(slip.absence_deduction)],
  ];
  const deductions: [string, number][] = [
    [t("hrNssfEmployee"), n(slip.nssf_employee)], [t("hrPaye"), n(slip.paye)], [t("hrHeslb"), n(slip.heslb)],
    ...(lines.loans ?? []).map((l): [string, number] => [`${t("hrLoan")} ${l.number}`, n(l.amount)]),
    ...(lines.deductions ?? []).map((l): [string, number] => [l.description, n(l.amount)]),
  ];
  const table = (title: string, rows: [string, number][], total: number, totalLabel: string) => (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead><tr><th>{title}</th><th className="num">TZS</th></tr></thead>
        <tbody>
          {rows.filter(([, v]) => v !== 0).map(([label, v]) => <tr key={label}><td>{label}</td><td className="num"><Tzs value={v} /></td></tr>)}
          <tr><td><strong>{totalLabel}</strong></td><td className="num"><strong><Tzs value={total} /></strong></td></tr>
        </tbody>
      </table>
    </div>
  );

  return (
    <div className="erp-grid">
      <GlassCard className="erp-span-2" title={`${slip.employee_name} · ${slip.employee_number}`}
        subtitle={`${slip.run ? monthLabel(slip.run.period, locale) : ""} · ${slip.department ?? "-"} · ${slip.job_title ?? "-"}`}>
        <div className="erp-form-grid">
          <Field label={t("hrBank")}><div>{slip.bank_name ?? "-"} {slip.bank_account_number}</div></Field>
          <Field label={t("hrDaysPaid")}><div className="tnum">{n(slip.days_paid)}</div></Field>
          <Field label={t("hrTaxable")}><div><Tzs value={slip.taxable} /></div></Field>
          <Field label={t("hrPaymentDate")}><div>{formatDate(slip.run?.payment_date, locale)}</div></Field>
        </div>
      </GlassCard>
      <GlassCard title={t("hrEarnings")} pad={false}>{table(t("hrEarnings"), earnings, n(slip.gross), t("hrGross"))}</GlassCard>
      <GlassCard title={t("hrDeductions")} pad={false}>{table(t("hrDeductions"), deductions, n(slip.total_deductions), t("hrTotalDeductions"))}</GlassCard>
      <GlassCard title={t("hrNetPay")}><div className="vf-statpill-value tnum" style={{ fontSize: 30 }}>TZS <Tzs value={slip.net} /></div></GlassCard>
      <GlassCard title={t("hrEmployerCosts")} pad={false}>
        {table(t("hrEmployerCosts"), [[t("hrNssfEmployer"), n(slip.nssf_employer)], [t("hrWcf"), n(slip.wcf)], [t("hrSdl"), n(slip.sdl)]], n(slip.nssf_employer) + n(slip.wcf) + n(slip.sdl), t("erpTotal"))}
      </GlassCard>
    </div>
  );
}

/** Leave balances for one person: entitlement, earned so far, taken, available. */
export function BalanceTable({ balances }: { balances: LeaveBalance[] }) {
  const { t } = useApp();
  return (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead><tr><th>{t("hrLeaveType")}</th><th className="num">{t("hrEntitled")}</th><th className="num">{t("hrAccrued")}</th><th className="num">{t("hrTaken")}</th><th className="num">{t("hrAvailable")}</th></tr></thead>
        <tbody>
          {balances.map((b) => (
            <tr key={b.id}><td>{b.leave_type.name}</td>
              <td className="num">{b.limited ? b.entitled : "-"}</td><td className="num">{b.limited ? b.accrued : "-"}</td>
              <td className="num">{b.taken}</td><td className="num"><strong>{b.available ?? t("hrUnlimited")}</strong></td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * A payslip page body: loads one payslip from `endpoint`, shows it, and
 * offers the PDF. Used by payroll (any payslip) and My HR (own ones only).
 */
export function PayslipPage({ endpoint, back }: { endpoint: string; back: ReactNode }) {
  const { t, locale, toast } = useApp();
  const [slip, setSlip] = useState<Payslip | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.get<{ data: Payslip }>(endpoint).then((r) => setSlip(r.data)).catch((e) => setError(e.message)); }, [endpoint]);

  async function pdf() {
    try { saveBlob(await download(`${endpoint}/pdf`), `payslip-${slip?.employee_number}-${slip?.run?.period}.pdf`); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }

  if (error) return <ErrorState message={error} />;
  if (!slip) return <LoadingBlock rows={5} />;

  return (
    <div className="erp-page">
      <PageHeader back={back} kicker={slip.run?.number} title={`${t("hrPayslip")} · ${slip.run ? monthLabel(slip.run.period, locale) : ""}`} subtitle={slip.employee_name}
        actions={<>
          {slip.run && <HrStatus status={slip.run.status} />}
          <button className="btn btn-secondary" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("hrPrint")}</button>
          <button className="btn btn-primary" onClick={pdf}><Icon name="ph-file-pdf" size={17} /> PDF</button>
        </>} />
      <PayslipView slip={slip} />
    </div>
  );
}
