"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, qty } from "@/lib/erp";
import { type Invoice, type Order, useLookups } from "@/lib/procurement-api";
import { Badge, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { BackLink, useMoney } from "@/components/procurement-ui";

interface Row { include: boolean; quantity: string; price: string; vat: string; account: string }

const INVOICEABLE = ["approved", "sent", "partially_received", "received", "closed"];

/**
 * Records a supplier's invoice against a purchase order. Each line shows the
 * three-way match as it is typed: the order price, what was received and not
 * yet invoiced, and the difference; the API decides and stores the match.
 */
export function InvoiceForm({ existing, orderId }: { existing?: Invoice; orderId?: string | null }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const money = useMoney();
  const { lookups } = useLookups();
  const [orders, setOrders] = useState<Order[] | null>(null);
  const [selected, setSelected] = useState(existing ? String(existing.purchase_order_id) : orderId ?? "");
  const [order, setOrder] = useState<Order | null>(null);
  const [number, setNumber] = useState(existing?.supplier_invoice_number ?? "");
  const [date, setDate] = useState(existing?.invoice_date?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [due, setDue] = useState(existing?.due_date?.slice(0, 10) ?? "");
  const [notes, setNotes] = useState(existing?.notes ?? "");
  const [rows, setRows] = useState<Record<number, Row>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => {
    if (existing) return;
    api.get<Paginated<Order>>("/erp/procurement/orders", { per_page: 100 })
      .then((r) => setOrders(r.data.filter((o) => INVOICEABLE.includes(o.status)))).catch((e) => setError(e.message));
  }, [existing]);

  useEffect(() => {
    if (!selected) return;
    api.get<{ data: Order }>(`/erp/procurement/orders/${selected}`).then((r) => {
      setOrder(r.data);
      setRows(Object.fromEntries((r.data.lines ?? []).map((l) => {
        const prior = existing?.lines?.find((x) => x.purchase_order_line_id === l.id);
        const open = Math.max(0, Number(l.received_quantity) - Number(l.invoiced_quantity));
        return [l.id, {
          include: prior ? true : !existing && open > 0,
          quantity: prior ? String(Number(prior.quantity)) : String(open),
          price: prior ? String(Number(prior.unit_price)) : String(Number(l.unit_price)),
          vat: prior ? String(Number(prior.vat_rate)) : String(Number(l.vat_rate)),
          account: prior?.expense_account_id ? String(prior.expense_account_id) : l.expense_account_id ? String(l.expense_account_id) : "",
        }];
      })));
    }).catch((e) => setError(e.message));
  }, [selected, existing]);

  async function save() {
    if (!order) return;
    setBusy(true); setFormError(null);
    const payload = {
      purchase_order_id: order.id, supplier_invoice_number: number, invoice_date: date, due_date: due || null, notes: notes || null,
      lines: (order.lines ?? []).filter((l) => rows[l.id]?.include).map((l) => ({
        purchase_order_line_id: l.id, quantity: Number(rows[l.id].quantity), unit_price: Number(rows[l.id].price), vat_rate: Number(rows[l.id].vat),
        expense_account_id: l.line_type === "service" && rows[l.id].account ? Number(rows[l.id].account) : null,
      })),
    };
    try {
      const r = existing
        ? await api.put<{ data: Invoice }>(`/erp/procurement/invoices/${existing.id}`, payload)
        : await api.post<{ data: Invoice }>("/erp/procurement/invoices", payload);
      toast(t("erpSaved"), r.data.number, r.data.match_status === "variance" ? "warn" : "ok");
      router.push(`/erp/procurement/invoices/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!existing && !orders) return <LoadingBlock rows={5} />;

  const set = (id: number, patch: Partial<Row>) => setRows((r) => ({ ...r, [id]: { ...r[id], ...patch } }));
  const included = (order?.lines ?? []).filter((l) => rows[l.id]?.include);
  const subtotal = included.reduce((s, l) => s + Number(rows[l.id].quantity || 0) * Number(rows[l.id].price || 0), 0);
  const vat = included.reduce((s, l) => s + Number(rows[l.id].quantity || 0) * Number(rows[l.id].price || 0) * Number(rows[l.id].vat || 0) / 100, 0);
  const tolerance = Number(lookups?.settings.price_tolerance_percent ?? 0);

  return (
    <div className="erp-page">
      <PageHeader back={<BackLink href={existing ? `/erp/procurement/invoices/${existing.id}` : "/erp/procurement/invoices"} label={t("prcInvoices")} />}
        kicker={existing?.number} title={existing ? t("prcEditInvoice") : t("prcNewInvoice")} subtitle={t("prcInvoiceFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("prcOrder")} htmlFor="si-po" required error={formError?.field("purchase_order_id")}>
            {existing ? <input id="si-po" className="input" value={order?.number ?? ""} disabled /> : (
              <select id="si-po" className="input" value={selected} onChange={(e) => { setSelected(e.target.value); setOrder(null); }}>
                <option value="">{t("prcPickOrder")}</option>
                {orders?.map((o) => <option key={o.id} value={o.id}>{o.number} · {o.supplier?.name}</option>)}
              </select>
            )}
          </Field>
          <Field label={t("prcSupplierInvoiceNo")} htmlFor="si-no" required error={formError?.field("supplier_invoice_number")}>
            <input id="si-no" className="input" value={number} onChange={(e) => setNumber(e.target.value)} />
          </Field>
          <Field label={t("prcInvoiceDate")} htmlFor="si-date" error={formError?.field("invoice_date")}>
            <input id="si-date" className="input" type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label={t("prcDueDate")} htmlFor="si-due" hint={t("prcDueDateHint")} error={formError?.field("due_date")}>
            <input id="si-due" className="input" type="date" value={due} onChange={(e) => setDue(e.target.value)} />
          </Field>
        </div>
        <Field label={t("erpNotes")} htmlFor="si-notes" hint={t("erpOptional")}>
          <textarea id="si-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      {selected && !order ? <LoadingBlock rows={3} /> : order && (
        <GlassCard title={t("prcThreeWayMatch")} subtitle={t("prcThreeWayMatchSub")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table erp-lines">
              <thead>
                <tr>
                  <th style={{ width: 40 }} aria-label={t("prcInclude")} />
                  <th style={{ minWidth: 180 }}>{t("prcItem")}</th>
                  <th className="num">{t("prcOrderPrice")}</th>
                  <th className="num">{t("prcReceivedNotInvoiced")}</th>
                  <th className="num" style={{ width: 110 }}>{t("prcInvoicedQty")}</th>
                  <th className="num" style={{ width: 130 }}>{t("prcInvoicePrice")}</th>
                  <th className="num" style={{ width: 80 }}>{t("prcVatRate")}</th>
                  <th>{t("prcMatch")}</th>
                </tr>
              </thead>
              <tbody>
                {(order.lines ?? []).map((l) => {
                  const r = rows[l.id];
                  if (!r) return null;
                  const open = Number(l.received_quantity) - Number(l.invoiced_quantity);
                  const priceOff = Math.abs(Number(r.price) - Number(l.unit_price)) > Math.max(0.005, Number(l.unit_price) * tolerance / 100);
                  const qtyOff = Number(r.quantity) - open > 0.0005;
                  return (
                    <tr key={l.id}>
                      <td><input type="checkbox" aria-label={t("prcInclude")} checked={r.include} onChange={(e) => set(l.id, { include: e.target.checked })} /></td>
                      <td>
                        <span className="erp-cell-title">{l.description}</span>
                        {l.line_type === "service" && (
                          <select className="input" aria-label={t("prcExpenseAccount")} value={r.account} onChange={(e) => set(l.id, { account: e.target.value })} style={{ marginTop: 6 }}>
                            <option value="">{t("prcDefaultExpense")}</option>
                            {lookups?.expense_accounts.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
                          </select>
                        )}
                      </td>
                      <td className="num">{amount(l.unit_price)}</td>
                      <td className="num">{qty(open)}</td>
                      <td className="num"><input className="input tnum" type="number" min={0} step="any" disabled={!r.include} aria-label={t("prcInvoicedQty")} value={r.quantity} onChange={(e) => set(l.id, { quantity: e.target.value })} /></td>
                      <td className="num"><input className="input tnum" type="number" min={0} step="any" disabled={!r.include} aria-label={t("prcInvoicePrice")} value={r.price} onChange={(e) => set(l.id, { price: e.target.value })} /></td>
                      <td className="num"><input className="input tnum" type="number" min={0} max={100} step="any" disabled={!r.include} aria-label={t("prcVatRate")} value={r.vat} onChange={(e) => set(l.id, { vat: e.target.value })} /></td>
                      <td>{!r.include ? "-" : priceOff || qtyOff
                        ? <Badge tone="bad" dot>{priceOff ? t("prcPriceVariance") : t("prcQuantityVariance")}</Badge>
                        : <Badge tone="ok" dot>{t("prcStMatched")}</Badge>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="erp-lines-foot">
            <span className="erp-muted">{t("prcVarianceNeedsApproval")}</span>
            <span className="tnum"><span className="erp-muted">{t("erpTotal")}</span> <strong>{money(subtotal + vat)}</strong></span>
          </div>
        </GlassCard>
      )}

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>{t("erpCancel")}</button>
        <button type="button" className="btn btn-primary" disabled={busy || !order || !number.trim() || included.length === 0} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("prcSaveAndMatch")}
        </button>
      </div>
    </div>
  );
}
