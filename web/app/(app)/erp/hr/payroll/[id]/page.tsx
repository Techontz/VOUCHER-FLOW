"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, download, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { monthLabel, n, type Payslip, type PayrollRun, today } from "@/lib/hr";
import { formatDateTime } from "@/lib/format";
import { Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { fill } from "@/components/erp-ui";
import { HrGate, HrStatus, Tzs } from "@/components/hr-ui";

type Action = "recalculate" | "authorise" | "return" | "lock" | "post" | "pay" | "delete";
interface Detail {
  data: PayrollRun; payslips: Payslip[];
  posting: { account: string; debit?: string | number; credit?: string | number }[];
  can: Record<Action, boolean>;
}

export default function PayrollRunPage() {
  return <HrGate anyOf={["hr.payroll.prepare", "hr.payroll.authorise", "hr.payroll.post"]}><Run /></HrGate>;
}

const ACTION_KEY = {
  recalculate: "hrRecalculate", authorise: "hrAuthorise", return: "hrReturnToDraft", lock: "hrLock", post: "hrPostToLedger", pay: "hrRecordPayment", delete: "hrDeleteDraft",
} as const;
const ACTION_HINT = {
  recalculate: "hrRecalculateHint", authorise: "hrAuthoriseHint", return: "hrReturnHint", lock: "hrLockHint", post: "hrPostHint", pay: "hrPayHint", delete: "hrDeleteHint",
} as const;
const ACCOUNT_KEY: Record<string, string> = {
  salaries: "6000", nssf_employer_expense: "6010", wcf_expense: "6020", sdl_expense: "6030", paye_payable: "2310", nssf_payable: "2320",
  wcf_payable: "2330", sdl_payable: "2340", heslb_payable: "2350", net_salaries_payable: "2360", staff_loan_recoveries: "2370", payroll_deductions_payable: "2380",
};

function Run() {
  const { t, locale, toast } = useApp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [d, setD] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<Action | null>(null);
  const [reason, setReason] = useState("");
  const [accounts, setAccounts] = useState<{ id: number; code: string; name: string }[]>([]);
  const [accountId, setAccountId] = useState("");
  const [payDate, setPayDate] = useState(today());
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [q, setQ] = useState("");

  const load = useCallback(() => { api.get<Detail>(`/erp/hr/payroll-runs/${id}`).then(setD).catch((e) => setError(e.message)); }, [id]);
  useEffect(load, [load]);
  useEffect(() => {
    if (action === "pay") api.get<{ data: typeof accounts }>("/erp/hr/payment-accounts").then((r) => { setAccounts(r.data); setAccountId(String(r.data.find((a) => a.code === "1200")?.id ?? r.data[0]?.id ?? "")); }).catch(() => undefined);
  }, [action]);

  async function act() {
    if (!d || !action) return;
    setBusy(true); setActionError(null);
    try {
      if (action === "delete") {
        await api.delete(`/erp/hr/payroll-runs/${d.data.id}`);
        toast(t("hrDeleted"), undefined, "ok"); router.push("/erp/hr/payroll"); return;
      }
      const body = action === "return" ? { reason } : action === "pay" ? { account_id: Number(accountId), payment_date: payDate } : undefined;
      const r = await api.post<{ message: string; skipped?: string[] }>(`/erp/hr/payroll-runs/${d.data.id}/${action}`, body);
      toast(r.message, r.skipped?.length ? fill(t("hrSkippedN"), { n: r.skipped.length }) : undefined, "ok");
      setAction(null); setReason(""); load();
    } catch (e) { setActionError((e as Error).message); } finally { setBusy(false); }
  }

  async function pdf(slip: Payslip) {
    try { saveBlob(await download(`/erp/hr/payslips/${slip.id}/pdf`), `payslip-${slip.employee_number}-${d?.data.period}.pdf`); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }

  if (error) return <ErrorState message={error} />;
  if (!d) return <LoadingBlock rows={6} />;

  const run = d.data;
  const slips = d.payslips.filter((s) => !q || `${s.employee_name} ${s.employee_number} ${s.department ?? ""}`.toLowerCase().includes(q.toLowerCase()));
  const actions = (Object.keys(d.can) as Action[]).filter((a) => d.can[a]);
  const timeline: [string, string | null, string | undefined][] = [
    [t("hrStPrepared"), run.prepared_at, run.preparer?.name], [t("hrStAuthorised"), run.authorised_at, run.authoriser?.name],
    [t("hrStLocked"), run.locked_at, run.locker?.name], [t("hrStPosted"), run.posted_at, run.poster?.name], [t("hrStPaid"), run.paid_at, run.payer?.name],
  ];

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/hr/payroll" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("hrPayroll")}</Link>}
        kicker={run.number}
        title={monthLabel(run.period, locale)}
        subtitle={`${run.employees_count} ${t("hrPayslips").toLowerCase()}${run.notes ? ` · ${run.notes}` : ""}`}
        actions={<>
          <HrStatus status={run.status} />
          {actions.map((a) => (
            <button key={a} className={`btn ${["authorise", "lock", "post", "pay"].includes(a) ? "btn-primary" : "btn-secondary"}`} onClick={() => { setActionError(null); setAction(a); }}>{t(ACTION_KEY[a])}</button>
          ))}
        </>} />

      {run.status === "draft" && !d.can.authorise && run.prepared_by !== null && <div className="vf-alert tone-info"><span className="vf-alert-text">{t("hrAwaitingAuthoriser")}</span></div>}

      <StatPills items={[
        { label: t("hrGross"), value: `TZS ${Number(run.gross).toLocaleString("en-US")}` },
        { label: t("hrTotalDeductions"), value: `TZS ${Number(run.total_deductions).toLocaleString("en-US")}` },
        { label: t("hrNet"), value: `TZS ${Number(run.net).toLocaleString("en-US")}`, tone: "ok" },
        { label: t("hrEmployerCosts"), value: `TZS ${(n(run.nssf_employer) + n(run.wcf) + n(run.sdl)).toLocaleString("en-US")}` },
      ]} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("hrPreview")} subtitle={t("hrPreviewSub")} pad={false}
          action={<input className="input" placeholder={t("erpSearch")} value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 200 }} />}>
          <div className="vf-table-wrap" data-scroll>
            <table className="table vf-table">
              <thead><tr>
                <th>{t("hrEmployee")}</th><th className="num">{t("hrBasic")}</th><th className="num">{t("hrAllowances")}</th><th className="num">{t("hrOvertime")}</th>
                <th className="num">{t("hrOtherEarnings")}</th><th className="num">{t("hrAbsenceShort")}</th><th className="num">{t("hrGross")}</th><th className="num">{t("hrNssfShort")}</th>
                <th className="num">{t("hrPaye")}</th><th className="num">{t("hrHeslb")}</th><th className="num">{t("hrLoans")}</th><th className="num">{t("hrOtherShort")}</th><th className="num">{t("hrNet")}</th><th />
              </tr></thead>
              <tbody>
                {slips.map((s) => (
                  <tr key={s.id}>
                    <td><Link className="erp-cell-link" href={`/erp/hr/payslips/${s.id}`}><span className="erp-cell-title">{s.employee_name}</span><span className="erp-cell-sub tnum">{s.employee_number}{s.department ? ` · ${s.department}` : ""}</span></Link></td>
                    <td className="num"><Tzs value={s.basic} /></td>
                    <td className="num"><Tzs value={n(s.housing_allowance) + n(s.transport_allowance) + n(s.other_allowance)} /></td>
                    <td className="num"><Tzs value={s.overtime} /></td><td className="num"><Tzs value={s.other_earnings} /></td>
                    <td className="num">{n(s.absence_deduction) ? <>-<Tzs value={s.absence_deduction} /></> : 0}</td>
                    <td className="num"><strong><Tzs value={s.gross} /></strong></td>
                    <td className="num"><Tzs value={s.nssf_employee} /></td><td className="num"><Tzs value={s.paye} /></td><td className="num"><Tzs value={s.heslb} /></td>
                    <td className="num"><Tzs value={s.loans} /></td><td className="num"><Tzs value={s.other_deductions} /></td>
                    <td className="num"><strong><Tzs value={s.net} /></strong></td>
                    <td><button className="btn btn-ghost btn-sm" aria-label="PDF" onClick={() => pdf(s)}><Icon name="ph-file-pdf" size={16} /></button></td>
                  </tr>
                ))}
                <tr>
                  <td><strong>{t("erpTotal")}</strong></td>
                  {(["basic", "allowances", "overtime", "other_earnings", "absence_deduction", "gross", "nssf_employee", "paye", "heslb", "loans", "other_deductions", "net"] as const).map((k) => (
                    <td key={k} className="num"><strong><Tzs value={run[k]} /></strong></td>
                  ))}
                  <td />
                </tr>
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("hrJournal")} subtitle={run.journal ? `${run.journal.number}` : t("hrJournalPreview")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrAccount")}</th><th className="num">{t("hrDebit")}</th><th className="num">{t("hrCredit")}</th></tr></thead>
              <tbody>
                {d.posting.map((l) => (
                  <tr key={l.account}><td><span className="tnum">{ACCOUNT_KEY[l.account]}</span> {l.account.replace(/_/g, " ")}</td>
                    <td className="num">{l.debit !== undefined ? <Tzs value={l.debit} /> : ""}</td><td className="num">{l.credit !== undefined ? <Tzs value={l.credit} /> : ""}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
          {run.payment_journal && <p className="erp-muted" style={{ padding: "8px 16px" }}>{t("hrPaidVia")} {run.payment_journal.number} · {run.payment_account?.code} {run.payment_account?.name}</p>}
        </GlassCard>

        <GlassCard title={t("hrStatutory")}>
          <div className="erp-form-grid">
            <Field label={t("hrPaye")}><div><Tzs value={run.paye} /></div></Field>
            <Field label={`${t("hrNssfShort")} (${t("hrEmployee").toLowerCase()} + ${t("hrEmployer").toLowerCase()})`}><div><Tzs value={n(run.nssf_employee) + n(run.nssf_employer)} /></div></Field>
            <Field label={t("hrWcf")}><div><Tzs value={run.wcf} /></div></Field>
            <Field label={t("hrSdl")}><div><Tzs value={run.sdl} /></div></Field>
            <Field label={t("hrHeslb")}><div><Tzs value={run.heslb} /></div></Field>
          </div>
        </GlassCard>

        <GlassCard title={t("hrTimeline")}>
          <div className="erp-list">
            {timeline.map(([label, at, who]) => (
              <div key={label} className="erp-list-row">
                <span className="erp-list-icon"><Icon name={at ? "ph-check-circle" : "ph-circle"} size={18} weight={at ? "fill" : "regular"} /></span>
                <span className="erp-list-main"><span className="erp-list-title">{label}</span><span className="erp-list-sub">{at ? `${who ?? ""} · ${formatDateTime(at, locale)}` : "-"}</span></span>
              </div>
            ))}
          </div>
        </GlassCard>
      </div>

      <Dialog open={!!action} busy={busy} title={action ? t(ACTION_KEY[action]) : ""} tone={action === "delete" ? "bad" : "info"} onClose={() => setAction(null)}
        summary={[{ label: t("hrPeriod"), value: monthLabel(run.period, locale) }, { label: t("hrNet"), value: <>TZS <Tzs value={run.net} /></> }, { label: t("hrPeople"), value: run.employees_count }]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setAction(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className={`btn ${action === "delete" ? "btn-danger" : "btn-primary"}`} onClick={act} disabled={busy || (action === "return" && reason.trim().length < 3) || (action === "pay" && !accountId)}>{t("hrConfirm")}</button>
        </>}>
        {action && <p className="erp-muted">{t(ACTION_HINT[action])}</p>}
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
        {action === "return" && <Field label={t("hrReasonRequired")} htmlFor="ret-reason"><input id="ret-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>}
        {action === "pay" && (
          <div className="erp-form-grid">
            <Field label={t("hrPayFrom")} htmlFor="pay-acc"><select id="pay-acc" className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}</select></Field>
            <Field label={t("hrPaymentDate")} htmlFor="pay-date"><input id="pay-date" className="input" type="date" value={payDate} max={today()} onChange={(e) => setPayDate(e.target.value)} /></Field>
          </div>
        )}
      </Dialog>
    </div>
  );
}
