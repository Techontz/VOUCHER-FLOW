"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import type { AccountRef, ReconciliationDetail, StatementLine } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, Banner, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { Amount, FinanceTabs, Flow } from "@/components/finance-ui";

export default function ReconciliationPage() {
  return <ErpGate module="accounting" permission="finance.view"><Reconcile /></ErpGate>;
}

function Reconcile() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [rec, setRec] = useState<ReconciliationDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [line, setLine] = useState({ line_date: "", description: "", reference: "", amount: "" });
  const [csv, setCsv] = useState("");
  const [importing, setImporting] = useState(false);
  const [booking, setBooking] = useState<StatementLine | null>(null);
  const [accounts, setAccounts] = useState<AccountRef[]>([]);
  const [bookAccount, setBookAccount] = useState("");
  const [confirm, setConfirm] = useState<"complete" | "delete" | null>(null);

  const load = useCallback(() => {
    api.get<{ data: ReconciliationDetail }>(`/erp/finance/reconciliations/${id}`).then((r) => setRec(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function run(fn: () => Promise<{ message?: string }>, after?: () => void) {
    setBusy(true); setActionError(null);
    try {
      const r = await fn();
      if (r?.message) toast(r.message, undefined, "ok");
      after?.(); load();
    } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!rec) return <LoadingBlock rows={6} />;

  const s = rec.summary;
  const open = rec.status === "open";
  const may = open && can("finance.bank");
  const base = `/erp/finance/reconciliations/${rec.id}`;

  async function readFile(file: File | undefined) {
    if (file) setCsv(await file.text());
  }

  function openBooking(l: StatementLine) {
    setBooking(l); setBookAccount(""); setActionError(null);
    if (!accounts.length) api.get<{ data: AccountRef[] }>("/erp/finance/cashbook/accounts").then((r) => setAccounts(r.data)).catch(() => setAccounts([]));
  }

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/finance/reconciliations" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("finTabReconcile")}</Link>}
        kicker={rec.number}
        title={rec.bank_account?.name ?? ""}
        subtitle={`${t("finStatementDate")}: ${formatDate(rec.statement_date, locale)}`}
        actions={<>
          <Badge tone={open ? "info" : "ok"} dot>{t(open ? "finInProgress" : "finCompleted")}</Badge>
          {may && <button className="btn btn-secondary" disabled={busy} onClick={() => run(() => api.post(`${base}/auto-match`))}><Icon name="ph-magic-wand" size={17} /> {t("finAutoMatch")}</button>}
          {may && <button className="btn btn-secondary" onClick={() => setConfirm("delete")}><Icon name="ph-trash" size={17} /> {t("erpDelete")}</button>}
          {may && <button className="btn btn-primary" onClick={() => { setActionError(null); setConfirm("complete"); }}><Icon name="ph-check-circle" size={18} /> {t("finComplete")}</button>}
        </>}
      />
      <FinanceTabs />

      <StatPills items={[
        { label: t("finBookBalance"), value: amount(s.book_balance), icon: "ph-notebook" },
        { label: t("finStatementBalance"), value: amount(s.statement_closing_balance), icon: "ph-bank" },
        { label: t("finClearedBalance"), value: amount(s.cleared_balance), icon: "ph-check-square" },
        { label: t("finDifference"), value: amount(s.difference), icon: Math.abs(s.difference) < 0.005 ? "ph-check-circle" : "ph-warning", tone: Math.abs(s.difference) < 0.005 ? "ok" : "bad" },
      ]} />

      {actionError && <Banner tone="danger" icon="ph-warning">{actionError}</Banner>}
      {open && Math.abs(s.statement_lines_difference) >= 0.005 && (
        <Banner tone="warn" icon="ph-warning">{fill(t("finLinesDontAddUp"), { diff: amount(s.statement_lines_difference) })}</Banner>
      )}

      <div className="erp-grid">
        <GlassCard title={t("finReconciliationMath")} pad={false}>
          <table className="table vf-table fin-statement">
            <tbody>
              <tr><td>{t("finStatementClosing")}</td><td className="num"><Amount value={s.statement_closing_balance} /></td></tr>
              <tr><td>{t("finAddDepositsInTransit")}</td><td className="num"><Amount value={s.deposits_in_transit} /></td></tr>
              <tr><td>{t("finLessOutstandingPayments")}</td><td className="num"><Amount value={-s.outstanding_payments} /></td></tr>
              <tr className="fin-total"><td>{t("finAdjustedBank")}</td><td className="num"><Amount value={s.adjusted_bank_balance} /></td></tr>
              <tr><td>{t("finBookBalance")}</td><td className="num"><Amount value={s.book_balance} /></td></tr>
              <tr><td>{t("finAddUnbookedLines")}</td><td className="num"><Amount value={s.unmatched_statement_total} /></td></tr>
              <tr className="fin-total"><td>{t("finAdjustedBook")}</td><td className="num"><Amount value={s.adjusted_book_balance} /></td></tr>
              <tr className="fin-grand"><td>{t("finDifference")}</td><td className="num"><Amount value={s.difference} /></td></tr>
            </tbody>
          </table>
        </GlassCard>

        {may && (
          <GlassCard title={t("finAddStatementLines")} subtitle={t("finCsvHint")}>
            <div className="erp-form-grid">
              <Field label={t("erpDate")} htmlFor="l-date"><input id="l-date" type="date" className="input" value={line.line_date} onChange={(e) => setLine({ ...line, line_date: e.target.value })} /></Field>
              <Field label={t("finDescription")} htmlFor="l-desc"><input id="l-desc" className="input" value={line.description} onChange={(e) => setLine({ ...line, description: e.target.value })} /></Field>
              <Field label={t("finSignedAmount")} htmlFor="l-amt" hint={t("finSignedAmountHint")}><input id="l-amt" className="input tnum" inputMode="decimal" value={line.amount} onChange={(e) => setLine({ ...line, amount: e.target.value })} /></Field>
              <Field label={t("erpReference")} htmlFor="l-ref"><input id="l-ref" className="input" value={line.reference} onChange={(e) => setLine({ ...line, reference: e.target.value })} /></Field>
            </div>
            <div className="fin-row-actions">
              <button className="btn btn-secondary" onClick={() => setImporting(true)}><Icon name="ph-file-csv" size={17} /> {t("finImportCsv")}</button>
              <button className="btn btn-primary" disabled={busy || !line.line_date || !line.description || !Number(line.amount)}
                onClick={() => run(() => api.post(`${base}/lines`, { lines: [{ ...line, reference: line.reference || null }] }), () => setLine({ line_date: "", description: "", reference: "", amount: "" }))}>
                <Icon name="ph-plus" size={17} /> {t("finAddLine")}
              </button>
            </div>
          </GlassCard>
        )}

        <GlassCard className="erp-span-2" title={t("finStatementLines")} subtitle={fill(t("finMatchedOf"), { n: s.matched_count, total: rec.lines.length })} pad={false}>
          {rec.lines.length === 0 ? <EmptyState icon="ph-list" title={t("finNoStatementLines")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpDate")}</th><th>{t("finDescription")}</th><th className="num">{t("finAmount")}</th><th>{t("finMatch")}</th><th /></tr></thead>
                <tbody>
                  {rec.lines.map((l) => (
                    <tr key={l.id}>
                      <td className="tnum">{formatDate(l.line_date, locale)}</td>
                      <td>{l.description}{l.reference && <span className="erp-cell-sub">{l.reference}</span>}</td>
                      <td className="num"><Flow value={Number(l.amount)} /></td>
                      <td>
                        {l.journal_line_id ? (
                          <span><Badge tone="ok">{t("finMatched")}</Badge> <span className="erp-cell-sub tnum">{l.journal_line?.entry?.number} · {formatDate(l.journal_line?.entry?.entry_date, locale)}</span></span>
                        ) : (
                          <>
                            <Badge tone="warn">{t("finUnmatched")}</Badge>
                            {may && l.suggestions.length > 0 && (
                              <div className="fin-suggest">
                                {l.suggestions.map((sg) => (
                                  <button key={sg.journal_line_id} className="btn btn-secondary btn-sm" disabled={busy} title={sg.memo}
                                    onClick={() => run(() => api.post(`${base}/lines/${l.id}/match`, { journal_line_id: sg.journal_line_id }))}>
                                    <Icon name="ph-link" size={14} /> {sg.number} · {formatDate(sg.entry_date, locale)}
                                  </button>
                                ))}
                              </div>
                            )}
                          </>
                        )}
                      </td>
                      <td>
                        {may && <div className="fin-row-actions">
                          {l.journal_line_id
                            ? <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => run(() => api.post(`${base}/lines/${l.id}/unmatch`))}>{t("finUnmatch")}</button>
                            : <>
                              {can("finance.cashbook") && <button className="btn btn-secondary btn-sm" onClick={() => openBooking(l)}>{t("finCreateEntry")}</button>}
                              <button className="btn btn-secondary btn-sm" aria-label={t("erpDelete")} disabled={busy} onClick={() => run(() => api.delete(`${base}/lines/${l.id}`))}><Icon name="ph-trash" size={14} /></button>
                            </>}
                        </div>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("finOutstandingItems")} subtitle={t("finOutstandingHint")} pad={false}>
          {rec.outstanding.length === 0 ? <EmptyState icon="ph-check-circle" title={t("finNothingOutstanding")} tone="ok" /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpDate")}</th><th>{t("erpReference")}</th><th>{t("finDescription")}</th><th className="num">{t("finAmount")}</th></tr></thead>
                <tbody>
                  {rec.outstanding.map((o) => (
                    <tr key={o.id}>
                      <td className="tnum">{formatDate(o.entry_date, locale)}</td>
                      <td className="tnum">{o.number}</td>
                      <td>{o.description || o.memo}</td>
                      <td className="num"><Flow value={o.amount} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      </div>

      <Dialog open={importing} title={t("finImportCsv")} sub={t("finCsvHint")} onClose={() => setImporting(false)} busy={busy} wide
        actions={<>
          <button className="btn btn-secondary" onClick={() => setImporting(false)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy || !csv.trim()} onClick={() => run(() => api.post(`${base}/import`, { csv }), () => { setImporting(false); setCsv(""); })}>{t("finImport")}</button>
        </>}>
        <Field label={t("finCsvFile")} htmlFor="csv-file"><input id="csv-file" type="file" accept=".csv,text/csv,text/plain" className="input" onChange={(e) => readFile(e.target.files?.[0])} /></Field>
        <Field label={t("finCsvPaste")} htmlFor="csv-text"><textarea id="csv-text" className="input" rows={8} value={csv} onChange={(e) => setCsv(e.target.value)} placeholder={"Date,Description,Amount,Reference\n2026-10-03,Deposit,300000,D1"} /></Field>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>

      <Dialog open={!!booking} title={t("finCreateEntry")} sub={t("finCreateEntryHint")} onClose={() => setBooking(null)} busy={busy}
        summary={booking ? [{ label: t("finDescription"), value: booking.description }, { label: t("finAmount"), value: <Flow value={Number(booking.amount)} /> }] : undefined}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setBooking(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy || !bookAccount} onClick={() => booking && run(() => api.post(`${base}/lines/${booking.id}/create-entry`, { account_id: Number(bookAccount) }), () => setBooking(null))}>{t("finPostAndMatch")}</button>
        </>}>
        <Field label={t("erpAccount")} htmlFor="bk-acct" required>
          <select id="bk-acct" className="input" value={bookAccount} onChange={(e) => setBookAccount(e.target.value)}>
            <option value="">{t("finChoose")}</option>
            {accounts.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
          </select>
        </Field>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>

      <Dialog open={!!confirm} onClose={() => setConfirm(null)} busy={busy} tone={confirm === "delete" ? "warn" : "info"}
        icon={confirm === "delete" ? "ph-trash" : "ph-check-circle"}
        title={t(confirm === "delete" ? "finDeleteReconciliationQ" : "finCompleteQ")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          {confirm === "delete"
            ? <button className="btn btn-danger" disabled={busy} onClick={async () => { setBusy(true); try { await api.delete(base); router.push("/erp/finance/reconciliations"); } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); setBusy(false); } }}>{t("erpDelete")}</button>
            : <button className="btn btn-primary" disabled={busy} onClick={() => run(() => api.post(`${base}/complete`), () => setConfirm(null))}>{t("finComplete")}</button>}
        </>}>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>
    </div>
  );
}
