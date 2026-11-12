"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { compactMoney, formatDate } from "@/lib/format";
import type { OrderStatus } from "@/lib/procurement-api";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills, type StatPill } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { ProcStatus, useMoney } from "@/components/procurement-ui";

interface Overview {
  open_requisitions: number; requisitions_awaiting_approval: number; orders_awaiting_approval: number;
  orders_to_receive: number; invoices_to_match: number; invoices_with_variance: number;
  payables_outstanding: number; payables_overdue: number; payables_due_7_days: number; ordered_this_month: number;
  recent_orders: { id: number; number: string; status: OrderStatus; total: string; order_date: string; supplier?: { name: string } }[];
}

export default function ProcurementOverviewPage() {
  return <ErpGate module="procurement" permission="procurement.view"><ProcurementOverview /></ErpGate>;
}

function ProcurementOverview() {
  const { t, locale } = useApp();
  const { can, config } = useErp();
  const money = useMoney();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Overview }>("/erp/procurement/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const pills: StatPill[] = [
    { label: t("prcOpenRequisitions"), value: data.open_requisitions, icon: "ph-clipboard-text", hint: `${data.requisitions_awaiting_approval} ${t("prcAwaitingApprovalShort")}`, tone: data.requisitions_awaiting_approval ? "warn" : "neutral", href: "/erp/procurement/requisitions" },
    { label: t("prcOrdersAwaitingApproval"), value: data.orders_awaiting_approval, icon: "ph-seal-check", tone: data.orders_awaiting_approval ? "warn" : "ok", href: "/erp/procurement/orders?status=submitted" },
    { label: t("prcToReceive"), value: data.orders_to_receive, icon: "ph-tray-arrow-down", tone: data.orders_to_receive ? "info" : "neutral", href: "/erp/procurement/orders?status=to_receive" },
    { label: t("prcInvoicesToMatch"), value: data.invoices_to_match, icon: "ph-scales", hint: `${data.invoices_with_variance} ${t("prcWithVariance")}`, tone: data.invoices_with_variance ? "bad" : "neutral", href: "/erp/procurement/invoices?status=to_match" },
    { label: t("prcPayablesDue"), value: compactMoney(data.payables_outstanding, currency), icon: "ph-wallet", hint: `${t("prcOverdue")}: ${compactMoney(data.payables_overdue, currency)}`, tone: data.payables_overdue ? "bad" : "ok", href: "/erp/procurement/ageing" },
  ];

  const actions = [
    can("procurement.request") && { href: "/erp/procurement/requisitions/new", icon: "ph-note-pencil", label: t("prcNewRequisition") },
    can("procurement.quote") && { href: "/erp/procurement/rfqs/new", icon: "ph-paper-plane-tilt", label: t("prcNewRfq") },
    can("procurement.order") && { href: "/erp/procurement/orders/new", icon: "ph-shopping-cart", label: t("prcNewOrder") },
    can("procurement.invoice") && { href: "/erp/procurement/invoices/new", icon: "ph-receipt", label: t("prcNewInvoice") },
    can("procurement.pay") && { href: "/erp/procurement/payments/new", icon: "ph-hand-coins", label: t("prcNewPayment") },
    { href: "/erp/procurement/statement", icon: "ph-file-text", label: t("prcStatement") },
    can("erp.configure") && { href: "/erp/procurement/settings", icon: "ph-sliders", label: t("prcSettings") },
  ].filter(Boolean) as { href: string; icon: string; label: string }[];

  return (
    <div className="erp-page">
      <PageHeader title={t("prcOverview")} subtitle={t("prcOverviewSub")} />
      <StatPills items={pills} label={t("prcOverview")} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prcRecentOrders")} pad={false}
          action={<Link className="vf-card-link" href="/erp/procurement/orders">{t("prcViewAll")}</Link>}>
          {data.recent_orders.length === 0 ? <EmptyState icon="ph-shopping-cart" title={t("prcNoOrders")} /> : (
            <ul className="erp-list">
              {data.recent_orders.map((o) => (
                <li key={o.id}>
                  <Link className="erp-list-row" href={`/erp/procurement/orders/${o.id}`}>
                    <span className="erp-list-icon"><Icon name="ph-shopping-cart" size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title tnum">{o.number} · {o.supplier?.name}</span>
                      <span className="erp-list-sub">{formatDate(o.order_date, locale)} · {money(o.total)}</span>
                    </span>
                    <ProcStatus status={o.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("prcQuickActions")} pad={false}>
          <div className="erp-actions">
            {actions.map((a) => (
              <Link key={a.href} href={a.href} className="erp-action">
                <span className="erp-action-icon"><Icon name={a.icon} size={20} /></span>
                <span className="erp-action-text"><span>{a.label}</span></span>
                <Icon name="ph-caret-right" size={16} style={{ marginLeft: "auto", opacity: .5 }} />
              </Link>
            ))}
          </div>
          <p className="erp-muted" style={{ padding: "0 16px 16px" }}>
            {t("prcDueThisWeek")}: <strong className="tnum">{money(data.payables_due_7_days)}</strong> · {t("prcOrderedThisMonth")}: <strong className="tnum">{money(data.ordered_this_month)}</strong>
          </p>
        </GlassCard>
      </div>
    </div>
  );
}
