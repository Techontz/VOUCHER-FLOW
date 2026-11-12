"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { num, type SalesOrder } from "@/lib/sales-api";
import { Banner, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type Act, ActionDialog, Facts, Money, SalesBadge, Timeline, TotalsBlock, useCurrency } from "@/components/sales-ui";

export default function OrderPage() {
  return <ErpGate module="sales" permission="sales.view"><OrderDetail /></ErpGate>;
}

function OrderDetail() {
  const { t, locale } = useApp();
  const { can, has } = useErp();
  const currency = useCurrency();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [order, setOrder] = useState<SalesOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);
  const [approved, setApproved] = useState<Record<number, string>>({});
  const [loadForm, setLoadForm] = useState({ warehouse_id: "", vehicle_number: "", driver_name: "", planned_date: "" });
  const [loadQty, setLoadQty] = useState<Record<number, string>>({});
  const [invoiceFrom, setInvoiceFrom] = useState(0);

  const load = useCallback(() => {
    api.get<{ data: SalesOrder }>(`/erp/sales/orders/${id}`).then((r) => setOrder(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!order) return <LoadingBlock rows={6} />;

  const path = `/erp/sales/orders/${order.id}`;
  const lines = order.lines ?? [];
  const policy = order.policy_preview ?? order.policy_check;
  const remaining = order.remaining_to_load ?? {};
  const leftToLoad = Object.values(remaining).reduce((s, n) => s + num(n), 0);
  const invoicedAll = lines.every((l) => num(l.quantity_invoiced) >= num(l.quantity_approved ?? l.quantity_ordered));
  const invoicedLoadings = new Set((order.invoices ?? []).filter((i) => i.status !== "cancelled" && i.loading_order_id).map((i) => i.loading_order_id));
  const deliveredUninvoiced = (order.loading_orders ?? []).filter((lo) => lo.status === "delivered" && !invoicedLoadings.has(lo.id));
  const invoiceable = ["awaiting_payment", "ready", "loading", "dispatched", "delivered"].includes(order.status);
  const warehouses = order.warehouses ?? [];

  function openApprove() {
    setApproved(Object.fromEntries(lines.map((l) => [l.id, String(num(l.quantity_ordered))])));
    setAct({
      key: "approve", path: `${path}/approve`, label: t("salApprove"), icon: "ph-seal-check", title: fill(t("salApproveQ"), { number: order!.number }),
      sub: order!.customer?.requires_prepayment ? t("salApprovePrepaySub") : t("salApproveCreditSub"),
      reason: policy && !policy.passed ? { label: t("salOverrideReason"), required: true, min: 5 } : undefined,
    });
  }

  function openLoading() {
    setLoadForm({ warehouse_id: String(order!.warehouse_id ?? warehouses[0]?.id ?? ""), vehicle_number: "", driver_name: "", planned_date: new Date().toISOString().slice(0, 10) });
    setLoadQty(Object.fromEntries(Object.entries(remaining).map(([k, v]) => [Number(k), String(num(v))])));
    setAct({
      key: "loading", path: "/erp/dispatch/loading-orders", label: t("salCreateLoading"), icon: "ph-truck", title: t("salCreateLoading"), sub: t("salCreateLoadingSub"),
      then: (r) => router.push(`/erp/dispatch/loading/${r.data.id}`),
    });
  }

  // The request is built from the dialog's inputs at the moment of sending.
  const body = act?.key === "approve"
    ? (reason: string) => ({ quantities: Object.fromEntries(Object.entries(approved).map(([k, v]) => [k, Number(v)])), override_reason: reason || null })
    : act?.key === "loading"
      ? () => ({
        sales_order_id: order.id, planned_date: loadForm.planned_date || null, warehouse_id: Number(loadForm.warehouse_id),
        vehicle_number: loadForm.vehicle_number || null, driver_name: loadForm.driver_name || null,
        quantities: Object.fromEntries(Object.entries(loadQty).map(([k, v]) => [k, Number(v || 0)])),
      })
      : act?.key === "invoice" ? () => ({ loading_order_id: invoiceFrom || null }) : undefined;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/sales/orders" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salOrders")}</Link>}
        kicker={t("salOrder")} title={<span className="tnum">{order.number}</span>}
        subtitle={<>{order.customer?.name} · {formatDate(order.order_date, locale)}{order.quotation ? ` · ${order.quotation.number}` : ""}</>}
        actions={<>
          <SalesBadge status={order.status} />
          {order.status === "draft" && can("sales.order") && <Link className="btn btn-secondary" href={`${path}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {order.status === "draft" && can("sales.order") && <button className="btn btn-primary" onClick={() => setAct({ key: "submit", path: `${path}/submit`, label: t("salSubmit"), icon: "ph-paper-plane-tilt", title: fill(t("salSubmitQ"), { number: order.number }) })}>{t("salSubmit")}</button>}
          {order.status === "submitted" && can("sales.approve") && <button className="btn btn-secondary" onClick={() => setAct({ key: "reject", path: `${path}/reject`, label: t("salReject"), icon: "ph-thumbs-down", tone: "warn", title: t("salReject"), reason: { label: t("erpReason"), required: true } })}>{t("salReject")}</button>}
          {order.status === "submitted" && can("sales.approve") && <button className="btn btn-primary" onClick={openApprove}><Icon name="ph-seal-check" size={18} /> {t("salApprove")}</button>}
          {["draft", "submitted", "awaiting_payment", "ready"].includes(order.status) && can("sales.approve") && (order.loading_orders ?? []).every((l) => l.status === "cancelled") && (
            <button className="btn btn-secondary" onClick={() => setAct({ key: "cancel", path: `${path}/cancel`, label: t("salCancelDoc"), icon: "ph-x-circle", tone: "warn", title: fill(t("salCancelOrderQ"), { number: order.number }) })}>{t("salCancelDoc")}</button>
          )}
          {invoiceable && can("sales.invoice") && (!invoicedAll || deliveredUninvoiced.length > 0) && (
            <button className="btn btn-secondary" onClick={() => { setInvoiceFrom(invoicedAll ? deliveredUninvoiced[0]?.id ?? 0 : 0); setAct({ key: "invoice", path: `${path}/invoice`, label: t("salRaiseInvoice"), icon: "ph-receipt", title: t("salRaiseInvoice"), sub: t("salRaiseInvoiceSub"), then: (r) => router.push(`/erp/sales/invoices/${r.data.id}`) }); }}>
              <Icon name="ph-receipt" size={17} /> {t("salRaiseInvoice")}
            </button>
          )}
          {has("dispatch") && can("dispatch.load") && ["ready", "loading", "dispatched"].includes(order.status) && leftToLoad > 0 && (
            <button className="btn btn-primary" onClick={openLoading}><Icon name="ph-truck" size={18} /> {t("salCreateLoading")}</button>
          )}
        </>} />

      {order.status === "awaiting_payment" && (
        <Banner tone="warn" icon="ph-hourglass-medium" title={t("salAwaitingPaymentTitle")}>
          {fill(t("salAwaitingPaymentBody"), { paid: `${currency} ${amount(order.verified_payments ?? 0)}`, total: `${currency} ${amount(order.total)}` })}
        </Banner>
      )}
      {order.status === "rejected" && order.rejection_reason && <Banner tone="danger" icon="ph-thumbs-down" title={t("salStRejected")}>{order.rejection_reason}</Banner>}
      {order.override_reason && <Banner tone="warn" icon="ph-warning" title={fill(t("salOverrodeBy"), { name: order.overrider?.name ?? "-" })}>{order.override_reason}</Banner>}

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} subtitle={t("salFourQuantities")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr>
                <th>{t("erpProduct")}</th><th className="num">{t("salQtyOrdered")}</th><th className="num">{t("salQtyApproved")}</th>
                <th className="num">{t("salQtyLoaded")}</th><th className="num">{t("salQtyReceived")}</th><th className="num">{t("salQtyInvoiced")}</th>
                <th className="num">{t("salUnitPrice")}</th><th className="num">{t("salLineTotal")}</th>
              </tr></thead>
              <tbody>
                {lines.map((l) => (
                  <tr key={l.id}>
                    <td><span className="erp-cell-title">{l.product?.name}</span><span className="erp-cell-sub tnum">{l.product?.sku}{num(l.discount_percent) ? ` · -${num(l.discount_percent)}%` : ""} · {t("salVat")} {num(l.tax_rate)}%</span></td>
                    <td className="num">{qty(l.quantity_ordered)}</td>
                    <td className="num">{l.quantity_approved === null ? "-" : qty(l.quantity_approved)}</td>
                    <td className="num">{qty(l.quantity_loaded)}</td>
                    <td className="num">{qty(l.quantity_received)}</td>
                    <td className="num">{qty(l.quantity_invoiced)}</td>
                    <td className="num"><Money value={l.unit_price} /></td>
                    <td className="num"><Money value={l.line_total} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("salSummary")}>
          <TotalsBlock totals={order} extra={order.verified_payments ? [{ label: t("salVerifiedPayments"), value: <Money value={order.verified_payments} /> }] : undefined} />
          <Facts rows={[
            [t("salPaymentMode"), order.payment_mode ? t(order.payment_mode === "prepayment" ? "salModePrepayment" : "salModeCredit") : (order.customer?.requires_prepayment ? t("salModePrepayment") : t("salModeCredit"))],
            [t("salDeliveryAddress"), order.delivery_address],
            [t("salRequiredDate"), order.required_date ? formatDate(order.required_date, locale) : null],
            [t("salNotes"), order.notes],
          ]} />
        </GlassCard>

        {policy && (
          <GlassCard title={t("salCreditPolicy")} subtitle={order.policy_preview ? t("salPolicyPreview") : t("salPolicyAtApproval")}>
            {policy.mode === "prepayment" ? <p className="erp-muted">{t("salPolicyPrepayment")}</p> : (
              <>
                <Facts rows={[
                  [t("salCreditLimit"), <Money key="l" value={policy.credit_limit} />],
                  [t("salOutstanding"), <Money key="o" value={policy.outstanding} />],
                  [t("salUninvoicedOrders"), <Money key="u" value={policy.uninvoiced_orders} />],
                  [t("salThisOrder"), <Money key="t" value={policy.this_order} />],
                  [t("salExposure"), <Money key="e" value={policy.exposure} strong />],
                  [t("salOverdueInvoices"), String(policy.overdue_invoices)],
                ]} />
                {policy.passed
                  ? <p className="sal-ok"><Icon name="ph-check-circle" size={16} /> {t("salPolicyPassed")}</p>
                  : <ul className="sal-reasons">{policy.reasons.map((r) => <li key={r}><Icon name="ph-warning-circle" size={15} /> {r}</li>)}</ul>}
              </>
            )}
          </GlassCard>
        )}

        <GlassCard title={t("salStockCheck")} subtitle={t("salStockCheckSub")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th>{warehouses.map((w) => <th key={w.id} className="num">{w.code}</th>)}</tr></thead>
              <tbody>
                {lines.map((l) => (
                  <tr key={l.id}>
                    <td>{l.product?.name}</td>
                    {warehouses.map((w) => {
                      const cell = order.availability?.[l.product_id]?.[w.id];
                      const need = num(remaining[l.id] ?? l.quantity_approved ?? l.quantity_ordered);
                      const avail = cell?.available ?? 0;
                      return <td key={w.id} className="num" style={{ color: avail >= need && need > 0 ? "var(--st-ok-fg)" : avail <= 0 ? "var(--text-muted)" : "var(--st-warn-fg)" }} title={cell ? `${t("salOnHand")} ${qty(cell.on_hand)} · ${t("salReserved")} ${qty(cell.reserved)}` : undefined}>{qty(avail)}</td>;
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("salTimeline")}>
          <Timeline steps={[
            { label: t("salStepCreated"), at: order.created_at, who: order.creator?.name },
            { label: t("salStepSubmitted"), at: order.submitted_at },
            { label: t("salStepApproved"), at: order.approved_at, who: order.approver?.name },
            ...(order.payment_mode === "prepayment" ? [{ label: t("salStepPaymentVerified"), at: order.payment_verified_at }] : []),
            ...(order.loading_orders ?? []).filter((lo) => lo.loaded_at).map((lo) => ({ label: `${t("salStepLoaded")} ${lo.number}`, at: lo.loaded_at })),
          ]} />
        </GlassCard>

        {((order.invoices?.length ?? 0) > 0 || (order.loading_orders?.length ?? 0) > 0) && (
          <GlassCard className="erp-span-3" title={t("salRelated")} pad={false}>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("salDocument")}</th><th>{t("erpDate")}</th><th>{t("salDetail")}</th><th>{t("erpStatus")}</th></tr></thead>
                <tbody>
                  {order.invoices?.map((i) => (
                    <tr key={`i${i.id}`}>
                      <td><Link className="erp-cell-link" href={`/erp/sales/invoices/${i.id}`}><span className="erp-cell-title tnum">{i.number}</span><span className="erp-cell-sub">{t("salInvoice")}</span></Link></td>
                      <td className="tnum">{formatDate(i.invoice_date, locale)}</td>
                      <td><Money value={i.total} /> · {t("salBalance")} <Money value={i.balance} /></td>
                      <td><SalesBadge status={i.status} /></td>
                    </tr>
                  ))}
                  {order.loading_orders?.map((lo) => (
                    <tr key={`l${lo.id}`}>
                      <td><Link className="erp-cell-link" href={`/erp/dispatch/loading/${lo.id}`}><span className="erp-cell-title tnum">{lo.number}</span><span className="erp-cell-sub">{t("salLoadingOrder")}</span></Link></td>
                      <td className="tnum">{formatDate(lo.planned_date, locale)}</td>
                      <td>{lo.warehouse?.name}{lo.vehicle_number ? ` · ${lo.vehicle_number}` : ""}{lo.delivery_note_number ? ` · ${lo.delivery_note_number}` : ""}</td>
                      <td><SalesBadge status={lo.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </GlassCard>
        )}
      </div>

      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} body={body}>
        {act?.key === "approve" && (
          <div className="sal-dialog-lines">
            {policy && !policy.passed && <div className="vf-alert tone-warn"><Icon name="ph-warning" size={18} /><span className="vf-alert-text">{policy.reasons.join(" ")}</span></div>}
            {lines.map((l) => (
              <Field key={l.id} label={`${l.product?.name} (${t("salQtyOrdered")} ${qty(l.quantity_ordered)})`} htmlFor={`ap-${l.id}`}>
                <input id={`ap-${l.id}`} className="input tnum" type="number" min={0} max={num(l.quantity_ordered)} step="any" value={approved[l.id] ?? ""} onChange={(e) => setApproved((a) => ({ ...a, [l.id]: e.target.value }))} />
              </Field>
            ))}
          </div>
        )}
        {act?.key === "invoice" && (
          <Field label={t("salInvoiceBasis")} htmlFor="inv-basis">
            <select id="inv-basis" className="input" value={invoiceFrom || ""} onChange={(e) => setInvoiceFrom(e.target.value ? Number(e.target.value) : 0)}>
              {!invoicedAll && <option value="">{t("salInvoiceApproved")}</option>}
              {deliveredUninvoiced.map((lo) => <option key={lo.id} value={lo.id}>{fill(t("salInvoiceDelivery"), { number: lo.number })}</option>)}
            </select>
          </Field>
        )}
        {act?.key === "loading" && (
          <div className="sal-dialog-lines">
            <div className="erp-form-grid">
              <Field label={t("erpWarehouse")} htmlFor="lo-wh" required>
                <select id="lo-wh" className="input" value={loadForm.warehouse_id} onChange={(e) => setLoadForm((f) => ({ ...f, warehouse_id: e.target.value }))}>
                  {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select>
              </Field>
              <Field label={t("salPlannedDate")} htmlFor="lo-date">
                <input id="lo-date" className="input" type="date" value={loadForm.planned_date} onChange={(e) => setLoadForm((f) => ({ ...f, planned_date: e.target.value }))} />
              </Field>
              <Field label={t("salVehicle")} htmlFor="lo-veh">
                <input id="lo-veh" className="input" value={loadForm.vehicle_number} onChange={(e) => setLoadForm((f) => ({ ...f, vehicle_number: e.target.value }))} placeholder="T 123 ABC" />
              </Field>
              <Field label={t("salDriver")} htmlFor="lo-drv">
                <input id="lo-drv" className="input" value={loadForm.driver_name} onChange={(e) => setLoadForm((f) => ({ ...f, driver_name: e.target.value }))} />
              </Field>
            </div>
            {lines.filter((l) => num(remaining[l.id]) > 0).map((l) => {
              const avail = order.availability?.[l.product_id]?.[loadForm.warehouse_id]?.available ?? 0;
              return (
                <Field key={l.id} label={`${l.product?.name} (${t("salLeftToLoad")} ${qty(remaining[l.id])})`} htmlFor={`lq-${l.id}`} hint={`${t("salAvailableHere")}: ${qty(avail)}`}>
                  <input id={`lq-${l.id}`} className="input tnum" type="number" min={0} max={num(remaining[l.id])} step="any" value={loadQty[l.id] ?? ""} onChange={(e) => setLoadQty((q) => ({ ...q, [l.id]: e.target.value }))} />
                </Field>
              );
            })}
          </div>
        )}
      </ActionDialog>
    </div>
  );
}
