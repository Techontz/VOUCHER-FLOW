"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, DOCUMENT_ICON, type DocumentType, type Paginated, type Party, type Product, type StockDocument, useErp, type Warehouse } from "@/lib/erp";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { DOC_HINT, DOC_LABEL } from "@/components/erp-ui";

interface Line {
  product_id: string; quantity: string; unit_cost: string;
  batch_number: string; expiry_date: string; serial_number: string; note: string;
}

const blankLine: Line = { product_id: "", quantity: "", unit_cost: "", batch_number: "", expiry_date: "", serial_number: "", note: "" };

/**
 * Prepares or edits a draft stock document. The columns follow the document
 * type and the product: a GRN asks for cost, a batch-tracked product asks for
 * its batch, a perishable one for its expiry, nothing is asked that the
 * posting will not use. Saving leaves a draft; nothing moves until it is posted.
 */
export function DocumentForm({ type, existing }: { type: DocumentType; existing?: StockDocument }) {
  const { t, toast } = useApp();
  const { config, has } = useErp();
  const router = useRouter();
  const [warehouses, setWarehouses] = useState<Warehouse[] | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  const [suppliers, setSuppliers] = useState<Party[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const [warehouseId, setWarehouseId] = useState(existing ? String(existing.warehouse_id) : "");
  const [toId, setToId] = useState(existing?.to_warehouse_id ? String(existing.to_warehouse_id) : "");
  const [supplierId, setSupplierId] = useState(existing?.supplier_id ? String(existing.supplier_id) : "");
  const [date, setDate] = useState(existing?.document_date?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [reference, setReference] = useState(existing?.reference ?? "");
  const [reason, setReason] = useState(existing?.reason ?? "");
  const [lines, setLines] = useState<Line[]>(existing?.lines?.map((l) => ({
    product_id: String(l.product_id), quantity: String(Number(l.quantity)), unit_cost: l.unit_cost ? String(Number(l.unit_cost)) : "",
    batch_number: l.batch_number ?? "", expiry_date: l.expiry_date?.slice(0, 10) ?? "", serial_number: l.serial_number ?? "", note: l.note ?? "",
  })) ?? [{ ...blankLine }]);

  useEffect(() => {
    api.get<{ data: Warehouse[] }>("/erp/warehouses").then((r) => {
      const active = r.data.filter((w) => w.is_active);
      setWarehouses(active);
      if (!existing && active[0]) setWarehouseId((v) => v || String(active[0].id));
    }).catch((e) => setError(e.message));
    api.get<Paginated<Product>>("/erp/products", { active_only: 1, per_page: 200 })
      .then((r) => setProducts(r.data.filter((p) => p.type !== "service"))).catch(() => undefined);
    if (type === "grn" && has("procurement")) {
      api.get<Paginated<Party>>("/erp/suppliers", { active_only: 1, per_page: 200 }).then((r) => setSuppliers(r.data)).catch(() => undefined);
    }
  }, [type, existing, has]);

  const byId = useMemo(() => new Map(products.map((p) => [String(p.id), p])), [products]);
  const needsCost = type === "grn" || type === "opening" || type === "adjustment";
  const anyBatch = lines.some((l) => byId.get(l.product_id)?.track_batches);
  const anyExpiry = lines.some((l) => byId.get(l.product_id)?.track_expiry) && (type === "grn" || type === "opening" || type === "adjustment");
  const anySerial = lines.some((l) => byId.get(l.product_id)?.track_serials);
  const total = needsCost ? lines.reduce((s, l) => s + Number(l.quantity || 0) * Number(l.unit_cost || 0), 0) : 0;

  const setLine = (i: number, patch: Partial<Line>) => setLines((all) => all.map((l, j) => (j === i ? { ...l, ...patch } : l)));

  async function save() {
    setBusy(true); setFormError(null);
    const payload = {
      type,
      warehouse_id: Number(warehouseId),
      to_warehouse_id: type === "transfer" && toId ? Number(toId) : null,
      supplier_id: type === "grn" && supplierId ? Number(supplierId) : null,
      document_date: date, reference: reference || null, reason: reason || null,
      lines: lines.filter((l) => l.product_id).map((l) => ({
        product_id: Number(l.product_id), quantity: Number(l.quantity),
        unit_cost: l.unit_cost === "" ? null : Number(l.unit_cost),
        batch_number: l.batch_number || null, expiry_date: l.expiry_date || null,
        serial_number: l.serial_number || null, note: l.note || null,
      })),
    };
    try {
      const r = existing
        ? await api.put<{ data: StockDocument }>(`/erp/stock-documents/${existing.id}`, payload)
        : await api.post<{ data: StockDocument }>("/erp/stock-documents", payload);
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/documents/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!warehouses) return <LoadingBlock rows={5} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const qtyLabel = type === "count" ? t("erpCountedQty") : t("erpQuantity");

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={existing ? `/erp/documents/${existing.id}` : "/erp/documents"} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("erpDocuments")}</Link>}
        kicker={existing?.number}
        title={<span className="erp-inline-icon"><Icon name={DOCUMENT_ICON[type]} size={34} /> {t(DOC_LABEL[type])}</span>}
        subtitle={t(DOC_HINT[type])}
      />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={type === "transfer" ? t("erpFrom") : t("erpWarehouse")} htmlFor="d-wh" required error={formError?.field("warehouse_id")}>
            <select id="d-wh" className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </Field>
          {type === "transfer" && (
            <Field label={t("erpTo")} htmlFor="d-to" required error={formError?.field("to_warehouse_id")}>
              <select id="d-to" className="input" value={toId} onChange={(e) => setToId(e.target.value)}>
                <option value="">{t("erpPickWarehouse")}</option>
                {warehouses.filter((w) => String(w.id) !== warehouseId).map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </Field>
          )}
          {type === "grn" && suppliers.length > 0 && (
            <Field label={t("erpSupplier")} htmlFor="d-sup">
              <select id="d-sup" className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
                <option value="">-</option>
                {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </Field>
          )}
          <Field label={t("erpDate")} htmlFor="d-date" error={formError?.field("document_date")}>
            <input id="d-date" className="input" type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label={t("erpReference")} htmlFor="d-ref" hint={t("erpOptional")}>
            <input id="d-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)} />
          </Field>
          <Field label={t("erpReason")} htmlFor="d-reason" hint={t("erpOptional")}>
            <input id="d-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </div>
      </GlassCard>

      <GlassCard title={t("erpLines")} subtitle={type === "adjustment" ? t("erpSignedQtyHint") : undefined} pad={false}>
        <div className="vf-table-wrap">
          <table className="table vf-table erp-lines">
            <thead>
              <tr>
                <th style={{ minWidth: 220 }}>{t("erpProduct")}</th>
                <th className="num" style={{ width: 120 }}>{qtyLabel}</th>
                {needsCost && <th className="num" style={{ width: 140 }}>{t("erpUnitCost")}</th>}
                {anyBatch && <th style={{ width: 140 }}>{t("erpBatch")}</th>}
                {anyExpiry && <th style={{ width: 160 }}>{t("erpExpiry")}</th>}
                {anySerial && <th style={{ width: 160 }}>{t("erpSerial")}</th>}
                <th style={{ width: 48 }} aria-label={t("erpRemove")} />
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => {
                const p = byId.get(l.product_id);
                return (
                  <tr key={i}>
                    <td>
                      <select className="input" aria-label={t("erpProduct")} value={l.product_id}
                        onChange={(e) => setLine(i, { product_id: e.target.value, unit_cost: l.unit_cost || (needsCost && byId.get(e.target.value) ? String(Number(byId.get(e.target.value)!.cost_price)) : "") })}>
                        <option value="">{t("erpPickProduct")}</option>
                        {products.map((x) => <option key={x.id} value={x.id}>{x.name} · {x.sku}</option>)}
                      </select>
                      {formError?.field(`lines.${i}.product_id`) && <div className="field-error">{formError.field(`lines.${i}.product_id`)}</div>}
                    </td>
                    <td className="num">
                      <input className="input tnum" type="number" step="any" aria-label={qtyLabel} value={l.quantity}
                        min={type === "adjustment" ? undefined : 0} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                      {p?.unit && <span className="erp-cell-sub">{p.unit.code}</span>}
                    </td>
                    {needsCost && (
                      <td className="num">
                        <input className="input tnum" type="number" step="any" min={0} aria-label={t("erpUnitCost")} value={l.unit_cost}
                          disabled={type === "adjustment" && Number(l.quantity) < 0} onChange={(e) => setLine(i, { unit_cost: e.target.value })} />
                      </td>
                    )}
                    {anyBatch && <td>{p?.track_batches ? <input className="input" aria-label={t("erpBatch")} value={l.batch_number} onChange={(e) => setLine(i, { batch_number: e.target.value })} /> : "-"}</td>}
                    {anyExpiry && <td>{p?.track_expiry ? <input className="input" type="date" aria-label={t("erpExpiry")} value={l.expiry_date} onChange={(e) => setLine(i, { expiry_date: e.target.value })} /> : "-"}</td>}
                    {anySerial && <td>{p?.track_serials ? <input className="input" aria-label={t("erpSerial")} value={l.serial_number} onChange={(e) => setLine(i, { serial_number: e.target.value })} /> : "-"}</td>}
                    <td>
                      <button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={lines.length === 1}
                        onClick={() => setLines((all) => all.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="erp-lines-foot">
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setLines((all) => [...all, { ...blankLine }])}>
            <Icon name="ph-plus" size={16} /> {t("erpAddLine")}
          </button>
          {needsCost && total > 0 && <span className="tnum"><span className="erp-muted">{t("erpTotal")}</span> <strong>{currency} {amount(total)}</strong></span>}
        </div>
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href={existing ? `/erp/documents/${existing.id}` : "/erp/documents"}>{t("erpCancel")}</Link>
        <button type="button" className="btn btn-primary" disabled={busy || !warehouseId || !lines.some((l) => l.product_id && l.quantity !== "")} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
      </div>
    </div>
  );
}
