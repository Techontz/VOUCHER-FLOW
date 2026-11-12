"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Receipt, SalesOrder } from "@/lib/sales-api";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { type Act, ActionDialog, Money, useCurrency } from "@/components/sales-ui";
import { ReceiptRows } from "@/components/sales-receipts";

interface Queue { receipts: Receipt[]; awaiting_payment: (SalesOrder & { verified_payments: number })[]; ready: SalesOrder[] }

export default function VerificationPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><DispatchHome /></ErpGate>;
}

function DispatchHome() {
  const { can } = useErp();
  return can("dispatch.verify") ? <VerificationQueue /> : <DispatchShortcuts />;
}

/**
 * Finance verification: payments recorded by someone else wait here to be
 * verified; prepayment orders wait here until verified money covers them.
 */
function VerificationQueue() {
  const { t, locale } = useApp();
  const currency = useCurrency();
  const [data, setData] = useState<Queue | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Queue }>("/erp/dispatch/verification").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={5} />;

  return (
    <div className="erp-page">
      <PageHeader title={t("salVerification")} subtitle={t("salVerificationSub")} />
      <StatPills label={t("salVerification")} items={[
        { label: t("salPaymentsToVerify"), value: data.receipts.length, tone: data.receipts.length ? "warn" : "ok", icon: "ph-shield-check" },
        { label: t("salAwaitingPayment"), value: data.awaiting_payment.length, tone: data.awaiting_payment.length ? "warn" : "neutral", icon: "ph-hourglass-medium" },
        { label: t("salReadyToLoad"), value: data.ready.length, icon: "ph-truck" },
      ]} />

      <GlassCard title={t("salPaymentsToVerify")} subtitle={t("salPaymentsToVerifySub")} pad={false}>
        {data.receipts.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("salNothingToVerify")} /> : <ReceiptRows rows={data.receipts} onAct={setAct} />}
      </GlassCard>

      <GlassCard title={t("salAwaitingPayment")} subtitle={t("salAwaitingPaymentSub")} pad={false}>
        {data.awaiting_payment.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("salNoneWaiting")} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salOrder")}</th><th>{t("salCustomer")}</th><th>{t("salInvoices")}</th><th className="num">{t("salVerified")}</th><th className="num">{t("salTotal")}</th></tr></thead>
              <tbody>
                {data.awaiting_payment.map((o) => (
                  <tr key={o.id}>
                    <td><Link className="erp-cell-link" href={`/erp/sales/orders/${o.id}`}><span className="erp-cell-title tnum">{o.number}</span><span className="erp-cell-sub">{formatDate(o.approved_at, locale)}</span></Link></td>
                    <td>{o.customer?.name}</td>
                    <td>{o.invoices?.length ? o.invoices.map((i) => <Link key={i.id} className="erp-cell-sub tnum" href={`/erp/sales/invoices/${i.id}`}>{i.number}</Link>) : <span className="erp-muted">{t("salNoInvoiceYet")}</span>}</td>
                    <td className="num">{currency} {amount(o.verified_payments)}</td>
                    <td className="num"><Money value={o.total} strong /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      <ReadyToLoad orders={data.ready} />
      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} />
    </div>
  );
}

function ReadyToLoad({ orders }: { orders: SalesOrder[] }) {
  const { t, locale } = useApp();
  return (
    <GlassCard title={t("salReadyToLoad")} subtitle={t("salReadyToLoadSub")} pad={false} action={<Link className="vf-card-link" href="/erp/dispatch/loading">{t("salLoadingOrders")}</Link>}>
      {orders.length === 0 ? <EmptyState icon="ph-truck" title={t("salNothingReady")} /> : (
        <ul className="erp-list">
          {orders.map((o) => (
            <li key={o.id}>
              <Link className="erp-list-row" href={`/erp/sales/orders/${o.id}`}>
                <span className="erp-list-icon"><Icon name="ph-package" size={18} /></span>
                <span className="erp-list-main"><span className="erp-list-title tnum">{o.number} · {o.customer?.name}</span><span className="erp-list-sub">{t(o.payment_mode === "prepayment" ? "salModePrepayment" : "salModeCredit")} · {formatDate(o.approved_at, locale)}</span></span>
                <Money value={o.total} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </GlassCard>
  );
}

function DispatchShortcuts() {
  const { t } = useApp();
  const [ready, setReady] = useState<SalesOrder[] | null>(null);
  useEffect(() => {
    api.get<{ data: { ready_orders: SalesOrder[] } }>("/erp/dispatch/lookups").then((r) => setReady(r.data.ready_orders.filter((o) => o.status === "ready"))).catch(() => setReady([]));
  }, []);
  return (
    <div className="erp-page">
      <PageHeader title={t("salDispatch")} subtitle={t("salDispatchSub")} />
      <div className="erp-actions">
        {([["/erp/dispatch/loading", "ph-truck", "salLoadingOrders"], ["/erp/dispatch/delivery-notes", "ph-file-text", "salDeliveryNotes"], ["/erp/dispatch/gate-passes", "ph-door-open", "salGatePasses"], ["/erp/dispatch/deliveries", "ph-hand-arrow-down", "salProofOfDelivery"]] as const).map(([href, icon, label]) => (
          <Link key={href} href={href} className="erp-action">
            <span className="erp-action-icon"><Icon name={icon} size={20} /></span>
            <span className="erp-action-text"><span>{t(label)}</span></span>
            <Icon name="ph-caret-right" size={16} style={{ marginLeft: "auto", opacity: .5 }} />
          </Link>
        ))}
      </div>
      {ready === null ? <LoadingBlock rows={2} /> : <ReadyToLoad orders={ready} />}
    </div>
  );
}
