"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import type { MessageKey } from "@/lib/i18n";
import { compactMoney, formatDate } from "@/lib/format";
import { type Overview, type SalesStatus, STATUS_LABEL } from "@/lib/sales-api";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Money, SalesBadge, useCurrency } from "@/components/sales-ui";

const PIPELINE: SalesStatus[] = ["draft", "submitted", "awaiting_payment", "ready", "loading", "dispatched", "delivered"];

export default function SalesOverviewPage() {
  return <ErpGate module="sales" permission="sales.view"><SalesOverview /></ErpGate>;
}

function SalesOverview() {
  const { t, locale } = useApp();
  const { can, has } = useErp();
  const currency = useCurrency();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Overview }>("/erp/sales/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const maxCount = Math.max(1, ...PIPELINE.map((s) => data.pipeline[s]?.count ?? 0));

  return (
    <div className="erp-page">
      <PageHeader title={t("salSales")} subtitle={t("salOverviewSub")}
        actions={<>
          {can("sales.quote") && <Link className="btn btn-secondary" href="/erp/sales/quotations/new"><Icon name="ph-note-pencil" size={18} /> {t("salNewQuotation")}</Link>}
          {can("sales.order") && <Link className="btn btn-primary" href="/erp/sales/orders/new"><Icon name="ph-plus" size={18} /> {t("salNewOrder")}</Link>}
        </>} />

      <StatPills label={t("salSales")} items={[
        { label: t("salSalesThisMonth"), value: compactMoney(data.sales_this_month, currency), hint: t("salExVat"), icon: "ph-chart-line-up" },
        { label: t("salReceivedThisMonth"), value: compactMoney(data.received_this_month, currency), icon: "ph-hand-coins", tone: "ok" },
        { label: t("salReceivables"), value: compactMoney(data.receivables, currency), href: "/erp/sales/aged", icon: "ph-scales" },
        { label: t("salOverdue"), value: compactMoney(data.overdue, currency), tone: data.overdue > 0 ? "bad" : "neutral", href: "/erp/sales/aged", icon: "ph-warning" },
      ]} />

      <StatPills label={t("salNeedsAction")} items={[
        { label: t("salOpenQuotations"), value: data.open_quotations, href: "/erp/sales/quotations", icon: "ph-note-pencil" },
        { label: t("salAwaitingApproval"), value: data.pipeline.submitted?.count ?? 0, tone: (data.pipeline.submitted?.count ?? 0) > 0 ? "warn" : "neutral", href: "/erp/sales/orders?status=submitted", icon: "ph-seal-check" },
        { label: t("salAwaitingVerification"), value: data.awaiting_verification, tone: data.awaiting_verification > 0 ? "warn" : "neutral", href: has("dispatch") ? "/erp/dispatch" : "/erp/sales/receipts", icon: "ph-shield-check" },
        { label: t("salOpenDiscrepancies"), value: data.open_discrepancies, tone: data.open_discrepancies > 0 ? "bad" : "neutral", href: "/erp/dispatch/loading?stage=discrepancies", icon: "ph-warning-diamond" },
      ]} />

      <div className="erp-grid">
        <GlassCard title={t("salPipeline")} subtitle={t("salPipelineSub")}>
          <ul className="erp-hbars">
            {PIPELINE.map((s) => {
              const cell = data.pipeline[s];
              return (
                <li key={s}>
                  <Link href={`/erp/sales/orders?status=${s}`} className="erp-hbar-label">{t(STATUS_LABEL[s])}</Link>
                  <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${((cell?.count ?? 0) / maxCount) * 100}%` }} /></span>
                  <span className="erp-hbar-value tnum">{cell?.count ?? 0}</span>
                </li>
              );
            })}
          </ul>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("salRecentOrders")} pad={false}
          action={<Link className="vf-card-link" href="/erp/sales/orders">{t("salViewAll")}</Link>}>
          {data.recent_orders.length === 0 ? <EmptyState icon="ph-shopping-cart" title={t("salNoOrders")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("salOrder")}</th><th>{t("salCustomer")}</th><th>{t("erpDate")}</th><th className="num">{t("salTotal")}</th><th>{t("erpStatus")}</th></tr></thead>
                <tbody>
                  {data.recent_orders.map((o) => (
                    <tr key={o.id}>
                      <td><Link className="erp-cell-link" href={`/erp/sales/orders/${o.id}`}><span className="erp-cell-title tnum">{o.number}</span></Link></td>
                      <td>{o.customer?.name}</td>
                      <td className="tnum">{formatDate(o.order_date, locale)}</td>
                      <td className="num"><Money value={o.total} /></td>
                      <td><SalesBadge status={o.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("salShortcuts")}>
          <div className="erp-actions sal-shortcuts">
            {([
              ["/erp/sales/invoices", "ph-receipt", "salInvoices"], ["/erp/sales/receipts", "ph-hand-coins", "salReceipts"],
              ["/erp/sales/returns", "ph-arrow-u-up-left", "salReturns"], ["/erp/sales/price-lists", "ph-tag", "salPriceLists"],
              ["/erp/sales/statement", "ph-file-text", "salStatements"], ["/erp/sales/aged", "ph-hourglass-medium", "salAgedReceivables"],
              ["/erp/sales/reports", "ph-chart-bar", "salReports"],
            ] as [string, string, MessageKey][]).map(([href, icon, label]) => (
              <Link key={href} href={href} className="erp-action">
                <span className="erp-action-icon"><Icon name={icon} size={20} /></span>
                <span className="erp-action-text"><span>{t(label)}</span></span>
                <Icon name="ph-caret-right" size={16} style={{ marginLeft: "auto", opacity: .5 }} />
              </Link>
            ))}
          </div>
        </GlassCard>
      </div>
    </div>
  );
}
