"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { type BankAccount, type Reconciliation, monthEnd } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { FinanceTabs } from "@/components/finance-ui";

export default function ReconciliationsPage() {
  return <ErpGate module="accounting" permission="finance.view"><Reconciliations /></ErpGate>;
}

function Reconciliations() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const preselect = useQueryValue("bank");
  const [status, setStatus] = useState<"" | "open" | "completed">("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Reconciliation> | null>(null);
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [startingChoice, setStarting] = useState<boolean | null>(null);
  const [form, setForm] = useState({ bank_account_id: "", statement_date: monthEnd(-1), statement_opening_balance: "", statement_closing_balance: "", notes: "" });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => { api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts", { active: 1 }).then((r) => setBanks(r.data)).catch(() => setBanks([])); }, []);
  useEffect(() => {
    api.get<Paginated<Reconciliation>>("/erp/finance/reconciliations", { status: status || undefined, page }).then(setRows).catch((e) => setError(e.message));
  }, [status, page]);
  const starting = startingChoice ?? (!!preselect && can("finance.bank"));
  const bankId = form.bank_account_id || preselect || "";

  async function start() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: Reconciliation }>("/erp/finance/reconciliations", {
        ...form, bank_account_id: bankId, statement_opening_balance: form.statement_opening_balance === "" ? null : form.statement_opening_balance, notes: form.notes || null,
      });
      router.push(`/erp/finance/reconciliations/${r.data.id}`);
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); setBusy(false); }
  }

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabReconcile")} subtitle={t("finReconcileSub")}
        actions={can("finance.bank") && <button className="btn btn-primary" onClick={() => setStarting(true)}><Icon name="ph-plus" size={18} /> {t("finStartReconciliation")}</button>} />
      <FinanceTabs />

      <Toolbar>
        <FilterChips<"" | "open" | "completed"> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "open", label: t("finInProgress") }, { value: "completed", label: t("finCompleted") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-checks" title={t("finNoReconciliations")} body={t("finReconcileSub")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("finBankAccount")}</th><th>{t("finStatementDate")}</th><th className="num">{t("finStatementBalance")}</th><th className="num">{t("finLines")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className="is-clickable" onClick={() => router.push(`/erp/finance/reconciliations/${r.id}`)}>
                    <td><Link className="erp-cell-link" href={`/erp/finance/reconciliations/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span></Link></td>
                    <td>{r.bank_account?.name}</td>
                    <td className="tnum">{formatDate(r.statement_date, locale)}</td>
                    <td className="num">{amount(r.statement_closing_balance)}</td>
                    <td className="num">{r.lines_count}</td>
                    <td><Badge tone={r.status === "completed" ? "ok" : "info"} dot>{t(r.status === "completed" ? "finCompleted" : "finInProgress")}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <Dialog open={starting} title={t("finStartReconciliation")} sub={t("finStartReconciliationHint")} onClose={() => setStarting(false)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setStarting(false)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={start} disabled={busy || !bankId || form.statement_closing_balance === ""}>{t("finStart")}</button>
        </>}>
        {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
        <div className="erp-form-grid">
          <Field label={t("finBankAccount")} htmlFor="r-bank" required error={formError?.field("bank_account_id")}>
            <select id="r-bank" className="input" value={bankId} onChange={(e) => setForm({ ...form, bank_account_id: e.target.value })}>
              <option value="">{t("finChoose")}</option>
              {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </Field>
          <Field label={t("finStatementDate")} htmlFor="r-date" required error={formError?.field("statement_date")}>
            <input id="r-date" type="date" className="input" value={form.statement_date} onChange={(e) => setForm({ ...form, statement_date: e.target.value })} />
          </Field>
          <Field label={t("finStatementOpening")} htmlFor="r-open" hint={t("finStatementOpeningHint")} error={formError?.field("statement_opening_balance")}>
            <input id="r-open" className="input tnum" inputMode="decimal" value={form.statement_opening_balance} onChange={(e) => setForm({ ...form, bank_account_id: bankId, statement_opening_balance: e.target.value })} />
          </Field>
          <Field label={t("finStatementClosing")} htmlFor="r-close" required error={formError?.field("statement_closing_balance")}>
            <input id="r-close" className="input tnum" inputMode="decimal" value={form.statement_closing_balance} onChange={(e) => setForm({ ...form, statement_closing_balance: e.target.value })} />
          </Field>
          <Field label={t("finNotes")} htmlFor="r-notes" error={formError?.field("notes")}>
            <input id="r-notes" className="input" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
          </Field>
        </div>
      </Dialog>
    </div>
  );
}
