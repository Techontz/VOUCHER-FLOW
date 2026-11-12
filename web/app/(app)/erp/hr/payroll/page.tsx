"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp } from "@/lib/erp";
import { currentPeriod, monthLabel, n, type PayrollRun, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Tabs, Toolbar } from "@/components/app-ui";
import { fill, FilterChips } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload, Tzs, useLookups } from "@/components/hr-ui";

interface Loan { id: number; number: string; type: string; principal: string; installment: string; balance: string; start_period: string; issued_on: string; status: string; reason: string | null; employee?: { full_name: string; employee_number: string } }
interface LoanDetail { data: Loan & { repayments: { id: number; period: string; amount: string; balance_after: string }[] }; schedule: { period: string; amount: number; balance_after: number }[] }
interface PayItem { id: number; employee_id: number; kind: string; category: string; description: string; amount: string; start_period: string; end_period: string | null; is_active: boolean; employee?: { full_name: string } }
type Tab = "runs" | "loans" | "items";

const PAYROLL = ["hr.payroll.prepare", "hr.payroll.authorise", "hr.payroll.post"];

export default function PayrollPage() {
  return <HrGate anyOf={PAYROLL}><Payroll /></HrGate>;
}

function Payroll() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("runs");
  return (
    <div className="erp-page">
      <PageHeader title={t("hrPayroll")} subtitle={t("hrPayrollSub")}
        actions={<Link className="btn btn-secondary" href="/erp/hr/statutory"><Icon name="ph-bank" size={18} /> {t("hrStatutory")}</Link>} />
      <Tabs label={t("hrPayroll")} value={tab} onChange={setTab} items={[
        { value: "runs", label: t("hrRuns") }, { value: "loans", label: t("hrLoans") }, { value: "items", label: t("hrPayItems") },
      ]} />
      {tab === "runs" && <Runs />}
      {tab === "loans" && <Loans />}
      {tab === "items" && <Items />}
    </div>
  );
}

function Runs() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const [rows, setRows] = useState<Paginated<PayrollRun> | null>(null);
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [preparing, setPreparing] = useState(false);

  const load = useCallback(() => { api.get<Paginated<PayrollRun>>("/erp/hr/payroll-runs", { page }).then(setRows).catch((e) => setError(e.message)); }, [page]);
  useEffect(load, [load]);

  return (
    <>
      {can("hr.payroll.prepare") && <Toolbar><button className="btn btn-primary" onClick={() => setPreparing(true)}><Icon name="ph-calculator" size={18} /> {t("hrPrepareRun")}</button></Toolbar>}
      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-money" title={t("hrNoRuns")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrPeriod")}</th><th className="num">{t("hrPeople")}</th><th className="num">{t("hrGross")}</th><th className="num">{t("hrPaye")}</th><th className="num">{t("hrNet")}</th><th>{t("hrPreparedBy")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className="is-clickable" onClick={() => router.push(`/erp/hr/payroll/${r.id}`)}>
                    <td><Link className="erp-cell-link" href={`/erp/hr/payroll/${r.id}`}><span className="erp-cell-title">{monthLabel(r.period, locale)}</span><span className="erp-cell-sub tnum">{r.number}</span></Link></td>
                    <td className="num">{r.employees_count}</td>
                    <td className="num"><Tzs value={r.gross} /></td><td className="num"><Tzs value={r.paye} /></td><td className="num"><strong><Tzs value={r.net} /></strong></td>
                    <td>{r.preparer?.name ?? "-"}<span className="erp-cell-sub">{formatDate(r.prepared_at, locale)}</span></td>
                    <td><HrStatus status={r.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
      <FormDialog open={preparing} title={t("hrPrepareRun")} submitLabel={t("hrPrepare")} onClose={() => setPreparing(false)}
        intro={<p className="erp-muted">{t("hrPrepareHint")}</p>}
        initial={{ period: currentPeriod() }}
        fields={[{ name: "period", label: t("hrPeriod"), type: "month", required: true }, { name: "notes", label: t("hrNotes"), wide: true }]}
        onSubmit={async (v) => {
          const r = await api.post<{ message: string; data: PayrollRun; skipped: string[] }>("/erp/hr/payroll-runs", payload(v));
          toast(r.message, r.skipped.length ? fill(t("hrSkippedN"), { n: r.skipped.length }) : undefined, r.skipped.length ? "warn" : "ok");
          setPreparing(false); router.push(`/erp/hr/payroll/${r.data.id}`);
        }} />
    </>
  );
}

function Loans() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const [status, setStatus] = useState("active");
  const [rows, setRows] = useState<Paginated<Loan> | null>(null);
  const [open, setOpen] = useState<LoanDetail | null>(null);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const prepare = can("hr.payroll.prepare");

  const load = useCallback(() => { api.get<Paginated<Loan>>("/erp/hr/loans", { status: status || undefined }).then(setRows).catch((e) => setError(e.message)); }, [status]);
  useEffect(load, [load]);

  async function cancel(loan: Loan) {
    try { const r = await api.post<{ message: string }>(`/erp/hr/loans/${loan.id}/cancel`); toast(r.message, undefined, "ok"); setOpen(null); load(); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }

  return (
    <>
      <Toolbar end={prepare && <button className="btn btn-primary" onClick={() => setAdding(true)}><Icon name="ph-hand-coins" size={18} /> {t("hrNewLoan")}</button>}>
        <FilterChips value={status} onChange={setStatus} items={[{ value: "active", label: t("hrStActive") }, { value: "settled", label: t("hrStSettled") }, { value: "cancelled", label: t("hrStCancelled") }, { value: "", label: t("erpAll") }]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-hand-coins" title={t("hrNoLoans")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrLoan")}</th><th>{t("hrEmployee")}</th><th className="num">{t("hrPrincipal")}</th><th className="num">{t("hrInstallment")}</th><th className="num">{t("hrBalance")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {rows.data.map((l) => (
                <tr key={l.id} className="is-clickable" onClick={() => api.get<LoanDetail>(`/erp/hr/loans/${l.id}`).then(setOpen)}>
                  <td><span className="erp-cell-title tnum">{l.number}</span><span className="erp-cell-sub">{l.type === "advance" ? t("hrAdvance") : t("hrLoan")} · {formatDate(l.issued_on, locale)}</span></td>
                  <td>{l.employee?.full_name}</td>
                  <td className="num"><Tzs value={l.principal} /></td><td className="num"><Tzs value={l.installment} /></td><td className="num"><strong><Tzs value={l.balance} /></strong></td>
                  <td><HrStatus status={l.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {open && (
        <FormDialog open title={`${open.data.number} · ${open.data.employee?.full_name ?? ""}`} fields={[]} onClose={() => setOpen(null)} submitLabel={t("hrClose")}
          onSubmit={async () => setOpen(null)}
          intro={<>
            <p className="erp-muted">{open.data.reason}</p>
            <h3 className="erp-subhead">{t("hrRepayments")}</h3>
            {open.data.repayments.length === 0 ? <p className="erp-muted">{t("hrNoneYet")}</p> : (
              <div className="vf-table-wrap"><table className="table vf-table"><thead><tr><th>{t("hrPeriod")}</th><th className="num">{t("hrAmount")}</th><th className="num">{t("hrBalance")}</th></tr></thead>
                <tbody>{open.data.repayments.map((r) => <tr key={r.id}><td>{monthLabel(r.period, locale)}</td><td className="num"><Tzs value={r.amount} /></td><td className="num"><Tzs value={r.balance_after} /></td></tr>)}</tbody></table></div>
            )}
            <h3 className="erp-subhead">{t("hrSchedule")}</h3>
            {open.schedule.length === 0 ? <p className="erp-muted">{t("hrNothingDue")}</p> : (
              <div className="vf-table-wrap"><table className="table vf-table"><thead><tr><th>{t("hrPeriod")}</th><th className="num">{t("hrAmount")}</th><th className="num">{t("hrBalance")}</th></tr></thead>
                <tbody>{open.schedule.map((r) => <tr key={r.period}><td>{monthLabel(r.period, locale)}</td><td className="num"><Tzs value={r.amount} /></td><td className="num"><Tzs value={r.balance_after} /></td></tr>)}</tbody></table></div>
            )}
            {prepare && open.data.status === "active" && open.data.repayments.length === 0 && <button className="btn btn-danger" onClick={() => cancel(open.data)}>{t("hrCancelLoan")}</button>}
          </>} />
      )}

      <FormDialog open={adding} title={t("hrNewLoan")} onClose={() => setAdding(false)} initial={{ type: "loan", start_period: currentPeriod(1), issued_on: today() }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "type", label: t("erpType"), type: "select", required: true, options: [{ value: "loan", label: t("hrLoan") }, { value: "advance", label: t("hrAdvance") }] },
          { name: "principal", label: t("hrPrincipal"), type: "number", required: true },
          { name: "installment", label: t("hrInstallment"), type: "number", required: true },
          { name: "start_period", label: t("hrFirstDeduction"), type: "month", required: true },
          { name: "issued_on", label: t("hrIssuedOn"), type: "date", required: true },
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { const r = await api.post<{ message: string }>("/erp/hr/loans", payload(v, ["employee_id", "principal", "installment"])); toast(r.message, undefined, "ok"); setAdding(false); load(); }} />
    </>
  );
}

function Items() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const [rows, setRows] = useState<Paginated<PayItem> | null>(null);
  const [editing, setEditing] = useState<PayItem | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const prepare = can("hr.payroll.prepare");
  const load = useCallback(() => { api.get<Paginated<PayItem>>("/erp/hr/pay-items", { per_page: 100 }).then(setRows).catch((e) => setError(e.message)); }, []);
  useEffect(load, [load]);
  const CATS = ["arrears", "bonus", "commission", "other_earning", "union", "insurance", "other_deduction"];

  return (
    <>
      {prepare && <Toolbar><button className="btn btn-primary" onClick={() => setEditing("new")}><Icon name="ph-plus" size={18} /> {t("hrNewPayItem")}</button></Toolbar>}
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-list-plus" title={t("hrNoPayItems")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrEmployee")}</th><th>{t("hrDescription")}</th><th>{t("erpType")}</th><th className="num">{t("hrAmount")}</th><th>{t("hrMonths")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {rows.data.map((i) => (
                <tr key={i.id} className={prepare ? "is-clickable" : undefined} onClick={prepare ? () => setEditing(i) : undefined}>
                  <td>{i.employee?.full_name}</td><td>{i.description}<span className="erp-cell-sub">{i.category.replace(/_/g, " ")}</span></td>
                  <td>{i.kind === "earning" ? t("hrEarning") : t("hrDeduction")}</td>
                  <td className="num"><Tzs value={i.kind === "earning" ? n(i.amount) : -n(i.amount)} /></td>
                  <td className="tnum">{i.start_period}{i.end_period === i.start_period ? "" : ` - ${i.end_period ?? t("hrOngoing")}`}</td>
                  <td><HrStatus status={i.is_active ? "active" : "cancelled"} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <FormDialog open={!!editing} title={editing === "new" ? t("hrNewPayItem") : t("hrPayItem")} onClose={() => setEditing(null)}
        initial={editing && editing !== "new" ? { employee_id: String(editing.employee_id), kind: editing.kind, category: editing.category, description: editing.description, amount: String(n(editing.amount)), start_period: editing.start_period, end_period: editing.end_period ?? "", is_active: editing.is_active } : { kind: "earning", category: "arrears", start_period: currentPeriod(), end_period: currentPeriod(), is_active: true }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "kind", label: t("erpType"), type: "select", required: true, options: [{ value: "earning", label: t("hrEarning") }, { value: "deduction", label: t("hrDeduction") }] },
          { name: "category", label: t("hrCategory"), type: "select", required: true, options: CATS.map((c) => ({ value: c, label: c.replace(/_/g, " ") })) },
          { name: "description", label: t("hrDescription"), required: true },
          { name: "amount", label: t("hrAmount"), type: "number", required: true },
          { name: "start_period", label: t("hrFromMonth"), type: "month", required: true },
          { name: "end_period", label: t("hrToMonth"), type: "month", hint: t("hrBlankOngoing") },
          { name: "is_active", label: t("erpActive"), type: "checkbox" },
        ]}
        onSubmit={async (v) => {
          const body = payload(v, ["employee_id", "amount"]);
          if (editing === "new") await api.post("/erp/hr/pay-items", body); else if (editing) await api.put(`/erp/hr/pay-items/${editing.id}`, body);
          toast(t("erpSaved"), undefined, "ok"); setEditing(null); load();
        }} />
    </>
  );
}
