"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Order, type Requisition, useLookups } from "@/lib/procurement-api";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { BackLink, blankLine, type EditLine, LineEditor, linePayload } from "@/components/procurement-ui";

/**
 * Raises or edits a draft purchase order, from scratch or prefilled from an
 * approved requisition. (An order from a selected quotation is raised from
 * the quotation's screen, with the quoted prices.)
 */
export function OrderForm({ existing, requisition }: { existing?: Order; requisition?: Requisition | null }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const { lookups, error } = useLookups();
  const vat = lookups ? String(Number(lookups.settings.default_vat_rate)) : "18";
  const [supplierId, setSupplierId] = useState(existing ? String(existing.supplier_id) : "");
  const [warehouseId, setWarehouseId] = useState(existing?.warehouse_id ? String(existing.warehouse_id) : "");
  const [orderDate, setOrderDate] = useState(existing?.order_date?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [expected, setExpected] = useState(existing?.expected_date?.slice(0, 10) ?? requisition?.needed_by?.slice(0, 10) ?? "");
  const [terms, setTerms] = useState(existing?.payment_terms ?? "");
  const [notes, setNotes] = useState(existing?.notes ?? "");
  const [lines, setLines] = useState<EditLine[] | null>(
    existing?.lines?.map((l) => ({
      line_type: l.line_type, product_id: l.product_id ? String(l.product_id) : "", description: l.description,
      quantity: String(Number(l.quantity)), price: String(Number(l.unit_price)), vat_rate: String(Number(l.vat_rate)),
      expense_account_id: l.expense_account_id ? String(l.expense_account_id) : "", purchase_requisition_line_id: l.purchase_requisition_line_id,
    }))
    ?? requisition?.lines?.map((l) => ({
      line_type: l.line_type, product_id: l.product_id ? String(l.product_id) : "", description: l.description,
      quantity: String(Number(l.quantity)), price: String(Number(l.estimated_unit_price)), vat_rate: "",
      expense_account_id: l.expense_account_id ? String(l.expense_account_id) : "", purchase_requisition_line_id: l.id,
    }))
    ?? null,
  );
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  if (error) return <ErrorState message={error} />;
  if (!lookups) return <LoadingBlock rows={5} />;

  const current = (lines ?? [blankLine(vat)]).map((l) => (l.vat_rate === "" ? { ...l, vat_rate: vat } : l));

  async function save() {
    setBusy(true); setFormError(null);
    const payload = {
      supplier_id: supplierId ? Number(supplierId) : null, warehouse_id: warehouseId ? Number(warehouseId) : null,
      purchase_requisition_id: requisition?.id ?? null,
      order_date: orderDate, expected_date: expected || null, payment_terms: terms || null, notes: notes || null,
      lines: current.map((l) => linePayload(l, "unit_price", true)),
    };
    try {
      const r = existing
        ? await api.put<{ data: Order }>(`/erp/procurement/orders/${existing.id}`, payload)
        : await api.post<{ data: Order }>("/erp/procurement/orders", payload);
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/procurement/orders/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="erp-page">
      <PageHeader back={<BackLink href={existing ? `/erp/procurement/orders/${existing.id}` : "/erp/procurement/orders"} label={t("prcOrders")} />}
        kicker={existing?.number ?? requisition?.number} title={existing ? t("prcEditOrder") : t("prcNewOrder")} subtitle={t("prcOrderFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("erpSupplier")} htmlFor="po-sup" required error={formError?.field("supplier_id")}>
            <select id="po-sup" className="input" value={supplierId} disabled={!!existing} onChange={(e) => {
              setSupplierId(e.target.value);
              const s = lookups.suppliers.find((x) => String(x.id) === e.target.value);
              if (s?.payment_terms_days && !terms) setTerms(`${s.payment_terms_days} days`);
            }}>
              <option value="">{t("prcPickSupplier")}</option>
              {lookups.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </Field>
          <Field label={t("prcDeliverTo")} htmlFor="po-wh" error={formError?.field("warehouse_id")}>
            <select id="po-wh" className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{t("erpPickWarehouse")}</option>
              {lookups.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </Field>
          <Field label={t("erpDate")} htmlFor="po-date" error={formError?.field("order_date")}>
            <input id="po-date" className="input" type="date" value={orderDate} onChange={(e) => setOrderDate(e.target.value)} />
          </Field>
          <Field label={t("prcExpected")} htmlFor="po-exp" error={formError?.field("expected_date")}>
            <input id="po-exp" className="input" type="date" value={expected} onChange={(e) => setExpected(e.target.value)} />
          </Field>
          <Field label={t("prcPaymentTerms")} htmlFor="po-terms">
            <input id="po-terms" className="input" value={terms} onChange={(e) => setTerms(e.target.value)} />
          </Field>
        </div>
        <Field label={t("erpNotes")} htmlFor="po-notes" hint={t("erpOptional")}>
          <textarea id="po-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      <GlassCard title={t("erpLines")} subtitle={t("prcServiceLineHint")} pad={false}>
        <LineEditor lines={current} onChange={setLines} lookups={lookups} withVat priceLabel={t("prcUnitPrice")} error={formError} />
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>{t("erpCancel")}</button>
        <button type="button" className="btn btn-primary" disabled={busy || !supplierId} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
      </div>
    </div>
  );
}
