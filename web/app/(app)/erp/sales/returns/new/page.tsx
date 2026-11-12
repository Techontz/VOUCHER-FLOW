"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, qty, useQueryValue } from "@/lib/erp";
import { type Invoice, lineAmounts, num, useSalesLookups } from "@/lib/sales-api";
import { EmptyState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { useCurrency } from "@/components/sales-ui";

export default function NewReturnPage() {
  return <ErpGate module="sales" permission="sales.return"><NewReturnGate /></ErpGate>;
}

function NewReturnGate() {
  const invoice = useQueryValue("invoice");
  if (invoice === undefined) return <LoadingBlock rows={4} />;
  return <NewReturn initialInvoice={invoice} />;
}

interface Row { quantity: string; batch_number: string; expiry_date: string }

/** A credit note against a posted invoice, at its own prices and VAT; optionally a return of the goods to stock. */
function NewReturn({ initialInvoice }: { initialInvoice: string | null }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const currency = useCurrency();
  const { lookups } = useSalesLookups();
  const [invoiceId, setInvoiceId] = useState(initialInvoice ?? "");
  const [choices, setChoices] = useState<Invoice[]>([]);
  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [rows, setRows] = useState<Record<number, Row>>({});
  const [reason, setReason] = useState("");
  const [returnStock, setReturnStock] = useState(false);
  const [warehouseId, setWarehouseId] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => {
    api.get<Paginated<Invoice>>("/erp/sales/invoices", { status: "posted", per_page: 200 }).then((r) => setChoices(r.data)).catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!invoiceId) return;
    api.get<{ data: Invoice }>(`/erp/sales/invoices/${invoiceId}`).then((r) => { setInvoice(r.data); setRows({}); }).catch((e) => setFormError(new ApiError(0, e.message)));
  }, [invoiceId]);

  const lines = invoiceId ? invoice?.lines ?? [] : [];
  const products = new Map((lookups?.products ?? []).map((p) => [p.id, p]));
  const total = lines.reduce((s, l) => s + lineAmounts(num(rows[l.id]?.quantity), num(l.unit_price), num(l.discount_percent), num(l.tax_rate)).total, 0);
  const setRow = (id: number, patch: Partial<Row>) => setRows((r) => ({ ...r, [id]: { ...(r[id] ?? { quantity: "", batch_number: "", expiry_date: "" }), ...patch } }));

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: { id: number } }>("/erp/sales/credit-notes", {
        sales_invoice_id: Number(invoiceId), reason, return_to_stock: returnStock, warehouse_id: returnStock && warehouseId ? Number(warehouseId) : null,
        lines: lines.filter((l) => num(rows[l.id]?.quantity) > 0).map((l) => ({
          sales_invoice_line_id: l.id, quantity: Number(rows[l.id].quantity),
          batch_number: rows[l.id].batch_number || null, expiry_date: rows[l.id].expiry_date || null,
        })),
      });
      toast(t("erpSaved"), undefined, "ok");
      router.push(`/erp/sales/returns/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="erp-page">
      <PageHeader back={<Link href="/erp/sales/returns" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salReturns")}</Link>}
        title={t("salNewCreditNote")} subtitle={t("salNewCreditNoteSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("salInvoice")} htmlFor="cn-inv" required error={formError?.field("sales_invoice_id")}>
            <select id="cn-inv" className="input" value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)}>
              <option value="">{t("salPickInvoice")}</option>
              {invoice && !choices.some((c) => c.id === invoice.id) && <option value={invoice.id}>{invoice.number} · {invoice.customer?.name}</option>}
              {choices.map((c) => <option key={c.id} value={c.id}>{c.number} · {c.customer?.name}</option>)}
            </select>
          </Field>
          <Field label={t("erpReason")} htmlFor="cn-reason" required error={formError?.field("reason")}>
            <input id="cn-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          {returnStock && (
            <Field label={t("salReturnTo")} htmlFor="cn-wh" required error={formError?.field("warehouse_id")}>
              <select id="cn-wh" className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
                <option value="">{t("erpPickWarehouse")}</option>
                {lookups?.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </Field>
          )}
        </div>
        <Check label={t("salReturnToStock")} hint={t("salReturnToStockHint")} checked={returnStock} onChange={setReturnStock} />
      </GlassCard>

      <GlassCard title={t("erpLines")} pad={false}>
        {!invoiceId || !invoice ? <EmptyState icon="ph-receipt" title={t("salPickInvoiceFirst")} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("salInvoiced")}</th><th className="num">{t("salCreditable")}</th><th className="num" style={{ width: 120 }}>{t("salCreditQty")}</th>{returnStock && <><th>{t("erpBatch")}</th><th>{t("erpExpiry")}</th></>}</tr></thead>
              <tbody>
                {lines.map((l) => {
                  const left = num(l.quantity) - num(l.quantity_credited);
                  const p = products.get(l.product_id);
                  return (
                    <tr key={l.id}>
                      <td>{l.product?.name}<span className="erp-cell-sub">{currency} {amount(l.unit_price)} · {t("salVat")} {num(l.tax_rate)}%</span></td>
                      <td className="num">{qty(l.quantity)}</td>
                      <td className="num">{qty(left)}</td>
                      <td className="num"><input className="input tnum" type="number" min={0} max={left} step="any" disabled={left <= 0} aria-label={t("salCreditQty")} value={rows[l.id]?.quantity ?? ""} onChange={(e) => setRow(l.id, { quantity: e.target.value })} /></td>
                      {returnStock && <>
                        <td>{p?.track_batches ? <input className="input" aria-label={t("erpBatch")} value={rows[l.id]?.batch_number ?? ""} onChange={(e) => setRow(l.id, { batch_number: e.target.value })} /> : "-"}</td>
                        <td>{p?.track_expiry ? <input className="input" type="date" aria-label={t("erpExpiry")} value={rows[l.id]?.expiry_date ?? ""} onChange={(e) => setRow(l.id, { expiry_date: e.target.value })} /> : "-"}</td>
                      </>}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <div className="erp-lines-foot"><span /><span className="tnum"><span className="erp-muted">{t("salCreditTotal")}</span> <strong>{currency} {amount(total)}</strong></span></div>
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href="/erp/sales/returns">{t("erpCancel")}</Link>
        <button className="btn btn-primary" disabled={busy || !invoiceId || reason.trim().length < 3 || total <= 0 || (returnStock && !warehouseId)} onClick={save}><Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}</button>
      </div>
    </div>
  );
}
