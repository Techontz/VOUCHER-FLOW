"use client";

import { type ReactNode, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { type BalanceSheet, type BudgetVsActual, type CashFlow, exportCsv, monthEnd, monthStart, type ProfitAndLoss, today } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, FinanceTabs } from "@/components/finance-ui";

export default function StatementsPage() {
  return <ErpGate module="accounting" permission="finance.statements"><Statements /></ErpGate>;
}

type Tab = "pl" | "bs" | "cf" | "budget";

const SECTION_LABEL: Record<string, MessageKey> = {
  income: "finIncome", cost_of_sales: "finCostOfSales", operating_expenses: "finOperatingExpenses",
  current_assets: "finCurrentAssets", non_current_assets: "finNonCurrentAssets",
  current_liabilities: "finCurrentLiabilities", non_current_liabilities: "finNonCurrentLiabilities", equity: "finEquity",
  operating: "finOperating", investing: "finInvesting", financing: "finFinancing",
};

function Statements() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("pl");
  const [from, setFrom] = useState(monthStart(0));
  const [to, setTo] = useState(today());
  const [year, setYear] = useState(new Date().getFullYear());
  const [through, setThrough] = useState(new Date().getMonth() + 1);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const ranges: { label: MessageKey; from: string; to: string }[] = [
    { label: "finThisMonth", from: monthStart(0), to: today() },
    { label: "finLastMonth", from: monthStart(-1), to: monthEnd(-1) },
    { label: "finLastThreeMonths", from: monthStart(-3), to: monthEnd(-1) },
    { label: "finYearToDate", from: `${new Date().getFullYear()}-01-01`, to: today() },
  ];

  async function download() {
    setExporting(true); setExportError(null);
    try {
      if (tab === "pl") await exportCsv("/erp/finance/statements/profit-and-loss", { from, to }, `profit-and-loss-${from}-${to}.csv`);
      if (tab === "bs") await exportCsv("/erp/finance/statements/balance-sheet", { as_of: to }, `balance-sheet-${to}.csv`);
      if (tab === "cf") await exportCsv("/erp/finance/statements/cash-flow", { from, to }, `cash-flow-${from}-${to}.csv`);
      if (tab === "budget") await exportCsv("/erp/finance/statements/budget-vs-actual", { year, through_month: through }, `budget-vs-actual-${year}.csv`);
    } catch (e) { setExportError(e instanceof ApiError ? e.message : String(e)); } finally { setExporting(false); }
  }

  return (
    <div className="erp-page">
      <PageHeader title={t("finStatements")} subtitle={t("finStatementsSub")}
        actions={<button className="btn btn-secondary" onClick={download} disabled={exporting}><Icon name="ph-download-simple" size={17} /> {t("finExportCsv")}</button>} />
      <FinanceTabs />
      <Tabs label={t("finStatements")} value={tab} onChange={setTab} items={[
        { value: "pl", label: t("finProfitLoss"), icon: "ph-chart-line-up" },
        { value: "bs", label: t("finBalanceSheet"), icon: "ph-scales" },
        { value: "cf", label: t("finCashFlow"), icon: "ph-arrows-down-up" },
        { value: "budget", label: t("finBudgetVsActual"), icon: "ph-target" },
      ]} />
      {exportError && <div className="field-error" role="alert">{exportError}</div>}

      {tab === "budget" ? (
        <div className="fin-filters">
          <Field label={t("finFiscalYear")} htmlFor="st-year"><input id="st-year" type="number" className="input tnum" value={year} onChange={(e) => setYear(Number(e.target.value))} /></Field>
          <Field label={t("finThroughMonth")} htmlFor="st-through">
            <select id="st-through" className="input" value={through} onChange={(e) => setThrough(Number(e.target.value))}>
              {Array.from({ length: 12 }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1}</option>)}
            </select>
          </Field>
        </div>
      ) : (
        <div className="fin-filters">
          {tab !== "bs" && <Field label={t("finFrom")} htmlFor="st-from"><input id="st-from" type="date" className="input" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>}
          <Field label={tab === "bs" ? t("finAsOf") : t("finTo")} htmlFor="st-to"><input id="st-to" type="date" className="input" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
          {tab !== "bs" && ranges.map((r) => (
            <button key={r.label} className="btn btn-secondary btn-sm" aria-pressed={from === r.from && to === r.to} onClick={() => { setFrom(r.from); setTo(r.to); }}>{t(r.label)}</button>
          ))}
        </div>
      )}

      {tab === "pl" && <ProfitLoss from={from} to={to} />}
      {tab === "bs" && <BalanceSheetView asOf={to} />}
      {tab === "cf" && <CashFlowView from={from} to={to} />}
      {tab === "budget" && <BudgetView year={year} through={through} />}
    </div>
  );
}

function useStatement<T>(path: string, query: Record<string, string | number>) {
  // Results remember the query they answer, so a changed filter shows loading, never stale figures.
  const [state, setState] = useState<{ key: string; data: T | null; error: string | null } | null>(null);
  const key = path + JSON.stringify(query);
  useEffect(() => {
    api.get<{ data: T }>(path, JSON.parse(key.slice(path.length)))
      .then((r) => setState({ key, data: r.data, error: null }))
      .catch((e) => setState({ key, data: null, error: e.message }));
  }, [path, key]);
  const current = state?.key === key ? state : null;
  return { data: current?.data ?? null, error: current?.error ?? null };
}

function ProfitLoss({ from, to }: { from: string; to: string }) {
  const { t, locale } = useApp();
  const { data, error } = useStatement<ProfitAndLoss>("/erp/finance/statements/profit-and-loss", { from, to });
  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const sections = ["income", "cost_of_sales", "operating_expenses"] as const;
  const sub: Record<(typeof sections)[number], keyof ProfitAndLoss["totals"]> = { income: "income", cost_of_sales: "cost_of_sales", operating_expenses: "operating_expenses" };

  return (
    <div className="vf-table-wrap">
      <table className="table vf-table fin-statement">
        <thead><tr><th>{t("erpAccount")}</th><th className="num">{formatDate(data.from, locale)} · {formatDate(data.to, locale)}</th><th className="num">{t("finPrior")} {formatDate(data.prior_from, locale)} · {formatDate(data.prior_to, locale)}</th></tr></thead>
        <tbody>
          {sections.map((section) => {
            const rows = data.rows.filter((r) => r.section === section);
            return [
              <tr key={`${section}-h`} className="fin-section"><td colSpan={3}>{t(SECTION_LABEL[section])}</td></tr>,
              ...rows.map((r) => <tr key={r.account_id}><td><span className="tnum erp-muted">{r.code}</span> {r.name}</td><td className="num"><Amount value={r.amount} /></td><td className="num"><Amount value={r.prior} /></td></tr>),
              <tr key={`${section}-t`} className="fin-total"><td>{t("erpTotal")} {t(SECTION_LABEL[section]).toLowerCase()}</td><td className="num"><Amount value={data.totals[sub[section]]} /></td><td className="num"><Amount value={data.prior_totals[sub[section]]} /></td></tr>,
              ...(section === "cost_of_sales" ? [<tr key="gp" className="fin-total"><td>{t("finGrossProfit")}</td><td className="num"><Amount value={data.totals.gross_profit} /></td><td className="num"><Amount value={data.prior_totals.gross_profit} /></td></tr>] : []),
            ];
          })}
          <tr className="fin-grand"><td>{t("finNetProfit")}</td><td className="num"><Amount value={data.totals.net_profit} strong /></td><td className="num"><Amount value={data.prior_totals.net_profit} strong /></td></tr>
        </tbody>
      </table>
    </div>
  );
}

function BalanceSheetView({ asOf }: { asOf: string }) {
  const { t } = useApp();
  const { data, error } = useStatement<BalanceSheet>("/erp/finance/statements/balance-sheet", { as_of: asOf });
  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const block = (sections: string[], totalLabel: MessageKey, total: number, extra?: ReactNode) => (
    <>
      {sections.map((section) => {
        const rows = data.rows.filter((r) => r.section === section);
        if (!rows.length) return null;
        return [
          <tr key={`${section}-h`} className="fin-section"><td colSpan={2}>{t(SECTION_LABEL[section])}</td></tr>,
          ...rows.map((r) => <tr key={r.account_id}><td><span className="tnum erp-muted">{r.code}</span> {r.name}</td><td className="num"><Amount value={r.amount} /></td></tr>),
        ];
      })}
      {extra}
      <tr className="fin-total"><td>{t(totalLabel)}</td><td className="num"><Amount value={total} strong /></td></tr>
    </>
  );

  return (
    <>
      <p><Badge tone={data.balanced ? "ok" : "bad"} dot>{t(data.balanced ? "finBalancedSheet" : "finUnbalancedSheet")}</Badge></p>
      <div className="vf-table-wrap">
        <table className="table vf-table fin-statement">
          <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("finAsOf")} {asOf}</th></tr></thead>
          <tbody>
            {block(["current_assets", "non_current_assets"], "finTotalAssets", data.totals.assets)}
            {block(["current_liabilities", "non_current_liabilities"], "finTotalLiabilities", data.totals.liabilities)}
            {block(["equity"], "finTotalEquity", data.totals.equity,
              <tr><td>{t("finUnclosedProfit")}</td><td className="num"><Amount value={data.current_earnings} /></td></tr>)}
            <tr className="fin-grand"><td>{t("finTotalLiabilitiesEquity")}</td><td className="num"><Amount value={data.totals.liabilities_and_equity} strong /></td></tr>
          </tbody>
        </table>
      </div>
    </>
  );
}

function CashFlowView({ from, to }: { from: string; to: string }) {
  const { t } = useApp();
  const { data, error } = useStatement<CashFlow>("/erp/finance/statements/cash-flow", { from, to });
  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  return (
    <>
      <p className="erp-muted">{t("finCashFlowMethod")}</p>
      <div className="vf-table-wrap">
        <table className="table vf-table fin-statement">
          <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("finCashInOut")}</th></tr></thead>
          <tbody>
            <tr className="fin-total"><td>{t("finOpeningCash")}</td><td className="num"><Amount value={data.totals.opening_cash} /></td></tr>
            {(["operating", "investing", "financing"] as const).map((activity) => [
              <tr key={`${activity}-h`} className="fin-section"><td colSpan={2}>{t(SECTION_LABEL[activity])}</td></tr>,
              ...data.rows.filter((r) => r.activity === activity).map((r) => <tr key={r.account_id}><td><span className="tnum erp-muted">{r.code}</span> {r.name}</td><td className="num"><Amount value={r.amount} /></td></tr>),
              <tr key={`${activity}-t`} className="fin-total"><td>{t("finNetCashFrom")} {t(SECTION_LABEL[activity]).toLowerCase()}</td><td className="num"><Amount value={data.totals[activity]} /></td></tr>,
            ])}
            <tr className="fin-total"><td>{t("finNetChange")}</td><td className="num"><Amount value={data.totals.net_change} /></td></tr>
            <tr className="fin-grand"><td>{t("finClosingCash")}</td><td className="num"><Amount value={data.totals.closing_cash} strong /></td></tr>
          </tbody>
        </table>
      </div>
      {!data.reconciles && <p className="field-error">{t("finCashFlowMismatch")}</p>}
    </>
  );
}

function BudgetView({ year, through }: { year: number; through: number }) {
  const { t } = useApp();
  const { data, error } = useStatement<BudgetVsActual>("/erp/finance/statements/budget-vs-actual", { year, through_month: through });
  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;
  if (!data.rows.length) return <EmptyState icon="ph-target" title={t("finNoBudget")} />;

  return (
    <>
      {!data.has_budget && <p className="erp-muted">{t("finNoBudget")}</p>}
      <div className="vf-table-wrap">
        <table className="table vf-table fin-statement">
          <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("finBudget")}</th><th className="num">{t("finActual")}</th><th className="num">{t("finVariance")}</th><th className="num">{t("finUsed")}</th></tr></thead>
          <tbody>
            {(["income", "expense"] as const).map((type) => [
              <tr key={`${type}-h`} className="fin-section"><td colSpan={5}>{t(type === "income" ? "finIncome" : "finExpenses")}</td></tr>,
              ...data.rows.filter((r) => r.type === type).map((r) => (
                <tr key={r.account_id}>
                  <td><span className="tnum erp-muted">{r.code}</span> {r.name}</td>
                  <td className="num"><Amount value={r.budget} /></td><td className="num"><Amount value={r.actual} /></td>
                  <td className="num"><Badge tone={r.variance < 0 ? "bad" : "ok"}><Amount value={r.variance} /></Badge></td>
                  <td className="num tnum">{r.used_percent == null ? "-" : `${r.used_percent}%`}</td>
                </tr>
              )),
            ])}
            <tr className="fin-grand"><td>{t("finNetProfit")}</td><td className="num"><Amount value={data.totals.net_budget} /></td><td className="num"><Amount value={data.totals.net_actual} /></td><td className="num"><Amount value={data.totals.net_actual - data.totals.net_budget} /></td><td /></tr>
          </tbody>
        </table>
      </div>
      <p className="erp-muted">{t("finVarianceHint")}</p>
    </>
  );
}
