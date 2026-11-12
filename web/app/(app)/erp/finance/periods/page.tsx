"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type PeriodMonth, type PeriodsYear, periodLabel } from "@/lib/finance-api";
import { formatDate, formatDateTime } from "@/lib/format";
import { Badge, Banner, Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { FinanceTabs } from "@/components/finance-ui";

export default function PeriodsPage() {
  return <ErpGate module="accounting" permission="finance.view"><Periods /></ErpGate>;
}

function Periods() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<PeriodsYear | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<{ kind: "close" | "reopen"; month: PeriodMonth } | "year" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const may = can("finance.close");

  const load = useCallback(() => {
    api.get<{ data: PeriodsYear }>("/erp/finance/periods", { year }).then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [year]);
  useEffect(load, [load]);

  async function act() {
    if (!confirm) return;
    setBusy(true); setActionError(null);
    try {
      const r = confirm === "year"
        ? await api.post<{ message: string }>(`/erp/finance/years/${year}/close`)
        : await api.post<{ message: string }>(`/erp/finance/periods/${confirm.month.period}/${confirm.kind}`, confirm.kind === "reopen" ? { reason } : undefined);
      toast(r.message, undefined, "ok");
      setConfirm(null); setReason(""); load();
    } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabPeriods")} subtitle={t("finPeriodsSub")}
        actions={may && data?.can_close_year && <button className="btn btn-primary" onClick={() => { setActionError(null); setConfirm("year"); }}><Icon name="ph-calendar-check" size={17} /> {fill(t("finCloseYear"), { year })}</button>} />
      <FinanceTabs />

      <div className="fin-filters">
        <button className="btn btn-secondary btn-sm" aria-label={t("back")} onClick={() => setYear((y) => y - 1)}><Icon name="ph-caret-left" size={14} /></button>
        <Field label={t("finFiscalYear")} htmlFor="p-year"><input id="p-year" type="number" className="input tnum" value={year} onChange={(e) => setYear(Number(e.target.value))} /></Field>
        <button className="btn btn-secondary btn-sm" aria-label={t("next")} onClick={() => setYear((y) => y + 1)}><Icon name="ph-caret-right" size={14} /></button>
      </div>

      {error ? <ErrorState message={error} onRetry={load} /> : !data || data.fiscal_year !== year ? <LoadingBlock rows={8} /> : <>
        {data.year_end && (
          <Banner tone="accent" icon="ph-seal-check" title={fill(t("finYearClosed"), { year: data.fiscal_year })}>
            {fill(t("finYearClosedBody"), { amount: amount(data.year_end.net_profit), number: data.year_end.journal?.number ?? "" })}
          </Banner>
        )}
        <GlassCard title={`${formatDate(data.starts_on, locale)} · ${formatDate(data.ends_on, locale)}`} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("finPeriod")}</th><th className="num">{t("finEntries")}</th><th>{t("erpStatus")}</th><th>{t("finHistory")}</th><th /></tr></thead>
              <tbody>
                {data.months.map((m) => (
                  <tr key={m.period}>
                    <td>{periodLabel(m.period, locale)}</td>
                    <td className="num">{m.entries}</td>
                    <td><Badge tone={m.status === "closed" ? "warn" : m.ended ? "info" : "ok"} dot>{t(m.status === "closed" ? "finClosed" : "finOpen")}</Badge></td>
                    <td className="erp-muted">
                      {m.closed_by && <>{t("finClosed")}: {m.closed_by}, {formatDateTime(m.closed_at, locale)}. </>}
                      {m.reopened_by && <>{t("finReopened")}: {m.reopened_by}, {formatDateTime(m.reopened_at, locale)} ({m.reopen_reason})</>}
                    </td>
                    <td>
                      {may && !data.year_end && m.status === "open" && m.ended && <button className="btn btn-secondary btn-sm" onClick={() => { setActionError(null); setConfirm({ kind: "close", month: m }); }}><Icon name="ph-lock-simple" size={14} /> {t("finCloseMonth")}</button>}
                      {may && !data.year_end && m.status === "closed" && <button className="btn btn-secondary btn-sm" onClick={() => { setActionError(null); setConfirm({ kind: "reopen", month: m }); }}><Icon name="ph-lock-simple-open" size={14} /> {t("finReopen")}</button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>
        {data.closed_years.length > 0 && (
          <GlassCard title={t("finClosedYears")} pad={false}>
            <ul className="erp-list">
              {data.closed_years.map((y) => (
                <li key={y.id} className="erp-list-row">
                  <span className="erp-list-main"><span className="erp-list-title tnum">{y.fiscal_year}</span><span className="erp-list-sub">{formatDateTime(y.created_at, locale)}</span></span>
                  <span className="tnum">{amount(y.net_profit)}</span>
                </li>
              ))}
            </ul>
          </GlassCard>
        )}
      </>}

      <Dialog open={!!confirm} onClose={() => setConfirm(null)} busy={busy} tone="warn"
        icon={confirm === "year" ? "ph-calendar-check" : confirm?.kind === "reopen" ? "ph-lock-simple-open" : "ph-lock-simple"}
        title={confirm === "year" ? fill(t("finCloseYear"), { year }) : confirm ? `${t(confirm.kind === "close" ? "finCloseMonth" : "finReopen")}: ${periodLabel(confirm.month.period, locale)}` : ""}
        sub={confirm === "year" ? t("finCloseYearHint") : confirm?.kind === "close" ? t("finCloseMonthHint") : t("finReopenHint")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-primary" onClick={act} disabled={busy || (confirm !== "year" && confirm?.kind === "reopen" && reason.trim().length < 3)}>{t("finConfirm")}</button>
        </>}>
        {confirm !== "year" && confirm?.kind === "reopen" && <Field label={t("erpReason")} htmlFor="p-reason" required><input id="p-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>}
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>
    </div>
  );
}
