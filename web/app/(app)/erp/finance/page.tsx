"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type FinanceOverview, periodLabel } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { DocStatus, ErpGate } from "@/components/erp-ui";
import { Amount, BANK_TYPE_ICON, BANK_TYPE_LABEL, FinanceTabs } from "@/components/finance-ui";

export default function FinancePage() {
  return <ErpGate module="accounting" permission="finance.view"><Overview /></ErpGate>;
}

function Overview() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [data, setData] = useState<FinanceOverview | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: FinanceOverview }>("/erp/finance/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return <LoadingBlock rows={6} />;

  const m = data.month.totals;
  const p = data.month.prior_totals;

  return (
    <div className="erp-page">
      <PageHeader title={t("finTitle")} subtitle={t("finSub")}
        actions={<>
          {can("finance.cashbook") && <Link className="btn btn-secondary" href="/erp/finance/cashbook?new=payment"><Icon name="ph-arrow-up-right" size={17} /> {t("finNewPayment")}</Link>}
          {can("finance.cashbook") && <Link className="btn btn-primary" href="/erp/finance/cashbook?new=receipt"><Icon name="ph-arrow-down-left" size={17} /> {t("finNewReceipt")}</Link>}
        </>} />
      <FinanceTabs />

      <StatPills label={t("finTitle")} items={[
        { label: t("finCashPosition"), value: amount(data.cash_total), icon: "ph-wallet", tone: data.cash_total < 0 ? "bad" : "neutral" },
        { label: t("finReceivables"), value: amount(data.receivables), icon: "ph-hand-coins" },
        { label: t("finPayables"), value: amount(data.payables), icon: "ph-receipt" },
        { label: t("finNetThisMonth"), value: amount(m.net_profit), icon: "ph-chart-line-up", tone: m.net_profit < 0 ? "bad" : "ok",
          hint: `${t("finPrior")}: ${amount(p.net_profit)}` },
      ]} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("finCashAccounts")} subtitle={t("finCashAccountsSub")} pad={false}
          action={<Link className="vf-card-link" href="/erp/finance/banks">{t("finViewAll")}</Link>}>
          {data.cash.length === 0 ? <EmptyState icon="ph-bank" title={t("finNoBanks")}
            action={can("finance.bank") ? <Link className="btn btn-primary" href="/erp/finance/banks?new=1">{t("finAddBank")}</Link> : undefined} /> : (
            <ul className="erp-list">
              {data.cash.map((c) => (
                <li key={c.account_id}>
                  <Link className="erp-list-row" href={c.bank_account_id ? `/erp/finance/banks/${c.bank_account_id}` : "/erp/accounts"}>
                    <span className="erp-list-icon"><Icon name={BANK_TYPE_ICON[c.type]} size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title">{c.name}</span>
                      <span className="erp-list-sub tnum">{c.code} · {t(BANK_TYPE_LABEL[c.type])}</span>
                    </span>
                    {!c.is_active && <Badge>{t("erpInactive")}</Badge>}
                    <Amount value={c.balance} strong />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("finThisMonth")} subtitle={`${formatDate(data.month.from, locale)} · ${formatDate(data.month.to, locale)}`}
          action={can("finance.statements") ? <Link className="vf-card-link" href="/erp/finance/statements">{t("finStatements")}</Link> : undefined}>
          <table className="table vf-table fin-statement">
            <thead><tr><th /><th className="num">{t("finThisMonth")}</th><th className="num">{t("finPrior")}</th></tr></thead>
            <tbody>
              <tr><td>{t("finIncome")}</td><td className="num"><Amount value={m.income} /></td><td className="num"><Amount value={p.income} /></td></tr>
              <tr><td>{t("finExpenses")}</td><td className="num"><Amount value={m.expenses} /></td><td className="num"><Amount value={p.expenses} /></td></tr>
              <tr className="fin-total"><td>{t("finNetProfit")}</td><td className="num"><Amount value={m.net_profit} /></td><td className="num"><Amount value={p.net_profit} /></td></tr>
            </tbody>
          </table>
        </GlassCard>

        <GlassCard title={t("finPeriodStatus")}
          action={<Link className="vf-card-link" href="/erp/finance/periods">{t("finTabPeriods")}</Link>}>
          <ul className="erp-list">
            <li className="erp-list-row">
              <span className="erp-list-main"><span className="erp-list-title">{periodLabel(data.periods.current, locale)}</span><span className="erp-list-sub">{t("finCurrentMonth")}</span></span>
              <Badge tone={data.periods.current_closed ? "warn" : "ok"} dot>{t(data.periods.current_closed ? "finClosed" : "finOpen")}</Badge>
            </li>
            <li className="erp-list-row">
              <span className="erp-list-main"><span className="erp-list-title">{data.periods.last_closed ? periodLabel(data.periods.last_closed, locale) : t("finNone")}</span><span className="erp-list-sub">{t("finLastClosed")}</span></span>
            </li>
            <li className="erp-list-row">
              <span className="erp-list-main"><span className="erp-list-title tnum">{data.drafts.cashbook + data.drafts.transfers}</span><span className="erp-list-sub">{t("finDraftsWaiting")}</span></span>
            </li>
          </ul>
        </GlassCard>

        <GlassCard title={t("finReconciliationsOpen")} pad={false}
          action={<Link className="vf-card-link" href="/erp/finance/reconciliations">{t("finViewAll")}</Link>}>
          {data.open_reconciliations.length === 0 ? <EmptyState icon="ph-checks" title={t("finNoOpenReconciliations")} /> : (
            <ul className="erp-list">
              {data.open_reconciliations.map((r) => (
                <li key={r.id}>
                  <Link className="erp-list-row" href={`/erp/finance/reconciliations/${r.id}`}>
                    <span className="erp-list-main"><span className="erp-list-title">{r.bank_account?.name}</span><span className="erp-list-sub tnum">{r.number} · {formatDate(r.statement_date, locale)}</span></span>
                    <Icon name="ph-caret-right" size={16} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("finRecentCashbook")} pad={false}
          action={<Link className="vf-card-link" href="/erp/finance/cashbook">{t("finTabCashbook")}</Link>}>
          {data.recent.length === 0 ? <EmptyState icon="ph-book-open-text" title={t("finNoEntries")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpReference")}</th><th>{t("finDescription")}</th><th>{t("erpDate")}</th><th className="num">{t("finAmount")}</th><th>{t("erpStatus")}</th></tr></thead>
                <tbody>
                  {data.recent.map((e) => (
                    <tr key={e.id}>
                      <td><Link className="erp-cell-link" href={`/erp/finance/cashbook/${e.id}`}><span className="erp-cell-title tnum">{e.number}</span><span className="erp-cell-sub">{e.bank_account?.name}</span></Link></td>
                      <td>{e.description}<span className="erp-cell-sub">{e.account?.code} {e.account?.name}</span></td>
                      <td className="tnum">{formatDate(e.entry_date, locale)}</td>
                      <td className="num"><Amount value={e.type === "payment" ? -Number(e.amount) : e.amount} /></td>
                      <td><DocStatus status={e.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      </div>
    </div>
  );
}
