"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Order, type OrderLine, useLookups } from "@/lib/procurement-api";
import { Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type ActionSpec, ActionDialog, ApprovalTrail, BackLink, Facts, ProcStatus, Progress, useMoney } from "@/components/procurement-ui";

export default function OrderPage() {
  return <ErpGate module="procurement" permission="procurement.view"><OrderDetail /></ErpGate>;
}

const RECEIVABLE = ["approved", "sent", "partially_received"];

function OrderDetail() {
  const { t, locale, toast, user } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const { id } = useParams<{ id: string }>();
  const [order, setOrder] = useState<Order | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionSpec | null>(null);
  const [receiving, setReceiving] = useState<"goods" | "service" | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Order }>(`/erp/procurement/orders/${id}`).then((r) => setOrder(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!order) return <LoadingBlock rows={6} />;

  const base = `/erp/procurement/orders/${order.id}`;
  const lines = order.lines ?? [];
  const outstanding = (l: OrderLine) => Number(l.quantity) - Number(l.received_quantity);
  const goodsOpen = lines.some((l) => l.line_type === "stock" && outstanding(l) > 0);
  const servicesOpen = lines.some((l) => l.line_type === "service" && outstanding(l) > 0);
  const receivable = RECEIVABLE.includes(order.status);
  const mine = order.created_by === user?.id;
  const actions: ActionSpec[] = [];

  if (order.status === "draft" && can("procurement.order")) {
    actions.push({ key: "submit", label: t("prcSubmit"), title: fill(t("prcSubmitQ"), { number: order.number }), sub: t("prcSubmitSub"), icon: "ph-paper-plane-right", path: `${base}/submit` });
  }
  if (order.status === "submitted" && can("procurement.approve") && !mine) {
    actions.push({ key: "approve", label: t("prcApprove"), title: fill(t("prcApproveQ"), { number: order.number }), icon: "ph-check-circle", tone: "ok", path: `${base}/approve`, comment: "optional" });
    actions.push({ key: "reject", label: t("prcReturnToDraft"), title: fill(t("prcRejectQ"), { number: order.number }), icon: "ph-arrow-u-up-left", tone: "bad", path: `${base}/reject`, comment: "required", danger: true });
  }
  if (order.status === "approved" && can("procurement.order")) {
    actions.push({ key: "send", label: t("prcMarkSent"), title: fill(t("prcMarkSentQ"), { number: order.number }), icon: "ph-envelope-simple", path: `${base}/send` });
  }
  if (["partially_received", "received"].includes(order.status) && can("procurement.order")) {
    actions.push({ key: "close", label: t("prcClose"), title: fill(t("prcCloseQ"), { number: order.number }), sub: t("prcCloseSub"), icon: "ph-lock-simple", tone: "warn", path: `${base}/close` });
  }
  if (["draft", "submitted", "approved", "sent"].includes(order.status) && !(order.receipts?.length) && can("procurement.order")) {
    actions.push({ key: "cancel", label: t("prcCancelDoc"), title: fill(t("prcCancelQ"), { number: order.number }), icon: "ph-x-circle", tone: "warn", path: `${base}/cancel`, comment: "required", commentKey: "reason", danger: true });
  }

  return (
    <div className="erp-page">
      <PageHeader
        back={<BackLink href="/erp/procurement/orders" label={t("prcOrders")} />}
        kicker={t("prcOrder")}
        title={<span className="tnum">{order.number}</span>}
        subtitle={<>{order.supplier?.name} · {formatDate(order.order_date, locale)}{order.warehouse ? ` · ${order.warehouse.name}` : ""}</>}
        actions={<>
          <ProcStatus status={order.status} />
          {order.status === "draft" && can("procurement.order") && <Link className="btn btn-secondary" href={`${base}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {receivable && goodsOpen && can("procurement.receive") && <button className="btn btn-primary" onClick={() => setReceiving("goods")}><Icon name="ph-tray-arrow-down" size={17} /> {t("prcReceiveGoods")}</button>}
          {receivable && servicesOpen && can("procurement.receive") && <button className="btn btn-primary" onClick={() => setReceiving("service")}><Icon name="ph-check-square" size={17} /> {t("prcConfirmService")}</button>}
          {!["draft", "submitted", "cancelled"].includes(order.status) && can("procurement.invoice") && <Link className="btn btn-secondary" href={`/erp/procurement/invoices/new?order=${order.id}`}><Icon name="ph-receipt" size={17} /> {t("prcRecordInvoice")}</Link>}
          {actions.map((a) => (
            <button key={a.key} className={["approve", "submit", "send"].includes(a.key) ? "btn btn-primary" : "btn btn-secondary"} onClick={() => setAction(a)}>
              <Icon name={a.icon} size={17} /> {a.label}
            </button>
          ))}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prcReceivingProgress")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prcItem")}</th><th className="num">{t("prcOrdered")}</th><th>{t("prcReceived")}</th><th className="num">{t("prcInvoiced")}</th><th className="num">{t("prcUnitPrice")}</th><th className="num">{t("prcAmount")}</th></tr></thead>
              <tbody>
                {lines.map((l) => (
                  <tr key={l.id}>
                    <td><span className="erp-cell-title">{l.description}</span><span className="erp-cell-sub">{l.line_type === "service" ? `${t("prcServiceLine")}${l.expense_account ? ` · ${l.expense_account.code} ${l.expense_account.name}` : ""}` : l.product?.sku}</span></td>
                    <td className="num">{qty(l.quantity)} <span className="erp-muted">{l.product?.unit?.code}</span></td>
                    <td><Progress done={Number(l.received_quantity)} of={Number(l.quantity)} /></td>
                    <td className="num">{qty(l.invoiced_quantity)}</td>
                    <td className="num">{money(l.unit_price)}</td>
                    <td className="num">{money(l.amount)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr><th colSpan={5}>{t("prcSubtotal")}</th><th className="num">{money(order.subtotal)}</th></tr>
                <tr><th colSpan={5}>{t("prcVat")}</th><th className="num">{money(order.vat_amount)}</th></tr>
                <tr><th colSpan={5}>{t("erpTotal")}</th><th className="num">{money(order.total)}</th></tr>
              </tfoot>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("erpStatus")}>
          <Facts rows={[
            [t("erpPrepared"), order.creator?.name],
            [t("prcRequisition"), order.requisition ? <Link className="tnum" href={`/erp/procurement/requisitions/${order.requisition.id}`}>{order.requisition.number}</Link> : null],
            [t("prcQuotation"), order.quotation ? <Link className="tnum" href={`/erp/procurement/rfqs/${order.quotation.purchase_rfq_id}`}>{order.quotation.reference ?? t("prcRfq")}</Link> : null],
            [t("prcExpected"), order.expected_date ? formatDate(order.expected_date, locale) : null],
            [t("prcPaymentTerms"), order.payment_terms],
            [t("prcApprovalsRequired"), String(order.approvals_required)],
            [t("erpNotes"), order.notes],
            [t("prcCancelReason"), order.cancel_reason],
          ]} />
        </GlassCard>

        <GlassCard title={t("prcReceipts")} pad={false}>
          {!order.receipts?.length ? <EmptyState icon="ph-tray" title={t("prcNoReceipts")} /> : (
            <ul className="erp-list">
              {order.receipts.map((r) => (
                <li key={r.id} className="erp-list-row" style={{ cursor: "default" }}>
                  <span className="erp-list-icon"><Icon name={r.kind === "goods" ? "ph-tray-arrow-down" : "ph-check-square"} size={18} /></span>
                  <span className="erp-list-main">
                    <span className="erp-list-title tnum">
                      {r.stock_document && can("inventory.view") ? <Link href={`/erp/documents/${r.stock_document.id}`}>{r.number}</Link> : r.number}
                    </span>
                    <span className="erp-list-sub">{formatDate(r.received_date, locale)} · {r.receiver?.name}{r.delivery_note ? ` · ${r.delivery_note}` : ""} · {money(r.value)}</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("prcInvoices")} pad={false}>
          {!order.invoices?.length ? <EmptyState icon="ph-receipt" title={t("prcNoInvoices")} /> : (
            <ul className="erp-list">
              {order.invoices.map((i) => (
                <li key={i.id}>
                  <Link className="erp-list-row" href={`/erp/procurement/invoices/${i.id}`}>
                    <span className="erp-list-icon"><Icon name="ph-receipt" size={18} /></span>
                    <span className="erp-list-main"><span className="erp-list-title tnum">{i.supplier_invoice_number}</span><span className="erp-list-sub tnum">{i.number} · {money(i.total)}</span></span>
                    <ProcStatus status={i.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("prcApprovals")}>
          <ApprovalTrail approvals={order.approvals} required={order.approvals_required} />
        </GlassCard>
      </div>

      {receiving && <ReceiveDialog order={order} kind={receiving} onClose={() => setReceiving(null)} onDone={(m) => { setReceiving(null); toast(m, undefined, "ok"); load(); }} />}
      <ActionDialog action={action} onClose={() => setAction(null)} onDone={(m) => { toast(m, undefined, "ok"); setAction(null); load(); }}
        summary={[{ label: t("erpSupplier"), value: order.supplier?.name ?? "-" }, { label: t("erpTotal"), value: money(order.total) }]} />
    </div>
  );
}

/**
 * Receives goods (a posted GRN into the chosen store) or confirms services.
 * Each line offers what is still outstanding; the API refuses more than was
 * ordered beyond the company's tolerance.
 */
function ReceiveDialog({ order, kind, onClose, onDone }: { order: Order; kind: "goods" | "service"; onClose: () => void; onDone: (message: string) => void }) {
  const { t } = useApp();
  const { lookups } = useLookups();
  const lines = (order.lines ?? []).filter((l) => (kind === "goods" ? l.line_type === "stock" : l.line_type === "service") && Number(l.quantity) - Number(l.received_quantity) > 0);
  const [warehouseId, setWarehouseId] = useState(order.warehouse_id ? String(order.warehouse_id) : "");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [note, setNote] = useState("");
  const [rows, setRows] = useState<Record<number, { quantity: string; batch: string; expiry: string; serial: string }>>(
    () => Object.fromEntries(lines.map((l) => [l.id, { quantity: String(Number(l.quantity) - Number(l.received_quantity)), batch: "", expiry: "", serial: "" }])),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const anyBatch = lines.some((l) => l.product?.track_batches);
  const anyExpiry = lines.some((l) => l.product?.track_expiry);
  const anySerial = lines.some((l) => l.product?.track_serials);

  async function save() {
    setBusy(true); setError(null);
    try {
      const payload = {
        received_date: date, delivery_note: note || null,
        ...(kind === "goods" ? { warehouse_id: warehouseId ? Number(warehouseId) : null } : {}),
        lines: lines.map((l) => ({
          purchase_order_line_id: l.id, quantity: Number(rows[l.id]?.quantity || 0),
          ...(kind === "goods" ? { batch_number: rows[l.id]?.batch || null, expiry_date: rows[l.id]?.expiry || null, serial_number: rows[l.id]?.serial || null } : {}),
        })),
      };
      const r = await api.post<{ message: string }>(`/erp/procurement/orders/${order.id}/${kind === "goods" ? "receive" : "confirm-service"}`, payload);
      onDone(r.message);
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  const set = (id: number, patch: Partial<{ quantity: string; batch: string; expiry: string; serial: string }>) => setRows((r) => ({ ...r, [id]: { ...r[id], ...patch } }));

  return (
    <Dialog open wide onClose={onClose} busy={busy} icon={kind === "goods" ? "ph-tray-arrow-down" : "ph-check-square"}
      title={kind === "goods" ? t("prcReceiveGoods") : t("prcConfirmService")} sub={kind === "goods" ? t("prcReceiveSub") : t("prcConfirmServiceSub")}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpBack")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || (kind === "goods" && !warehouseId)}>{kind === "goods" ? t("prcReceiveAndPost") : t("prcConfirmService")}</button>
      </>}>
      <div className="erp-form-grid">
        {kind === "goods" && (
          <Field label={t("erpWarehouse")} htmlFor="rc-wh" required error={error?.field("warehouse_id")}>
            <select id="rc-wh" className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{t("erpPickWarehouse")}</option>
              {lookups?.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </Field>
        )}
        <Field label={t("erpDate")} htmlFor="rc-date" error={error?.field("received_date")}>
          <input id="rc-date" className="input" type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} />
        </Field>
        <Field label={t("prcDeliveryNote")} htmlFor="rc-note" hint={t("erpOptional")}>
          <input id="rc-note" className="input" value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
      <div className="vf-table-wrap">
        <table className="table vf-table">
          <thead>
            <tr>
              <th>{t("prcItem")}</th><th className="num">{t("prcOutstanding")}</th><th className="num" style={{ width: 120 }}>{kind === "goods" ? t("prcReceivingNow") : t("prcDelivered")}</th>
              {anyBatch && <th>{t("erpBatch")}</th>}{anyExpiry && <th>{t("erpExpiry")}</th>}{anySerial && <th>{t("erpSerial")}</th>}
            </tr>
          </thead>
          <tbody>
            {lines.map((l) => (
              <tr key={l.id}>
                <td>{l.description}</td>
                <td className="num">{qty(Number(l.quantity) - Number(l.received_quantity))}</td>
                <td className="num"><input className="input tnum" type="number" min={0} step="any" aria-label={t("prcReceivingNow")} value={rows[l.id]?.quantity ?? ""} onChange={(e) => set(l.id, { quantity: e.target.value })} /></td>
                {anyBatch && <td>{l.product?.track_batches ? <input className="input" aria-label={t("erpBatch")} value={rows[l.id]?.batch ?? ""} onChange={(e) => set(l.id, { batch: e.target.value })} /> : "-"}</td>}
                {anyExpiry && <td>{l.product?.track_expiry ? <input className="input" type="date" aria-label={t("erpExpiry")} value={rows[l.id]?.expiry ?? ""} onChange={(e) => set(l.id, { expiry: e.target.value })} /> : "-"}</td>}
                {anySerial && <td>{l.product?.track_serials ? <input className="input" aria-label={t("erpSerial")} value={rows[l.id]?.serial ?? ""} onChange={(e) => set(l.id, { serial: e.target.value })} /> : "-"}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error.message}</div>}
    </Dialog>
  );
}
