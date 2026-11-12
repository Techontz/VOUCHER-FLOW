"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Category, type Paginated, type Product, type ProductType, qty, type Unit, useErp, useQueryValue } from "@/lib/erp";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { Check, ErpGate, PRODUCT_TYPE_LABEL } from "@/components/erp-ui";

const TYPES: ProductType[] = ["stock", "finished_good", "raw_material", "packaging", "service"];

type Form = {
  sku: string; barcode: string; name: string; brand: string; type: ProductType;
  category_id: string; unit_id: string; cost_price: string; sale_price: string; reorder_level: string;
  track_batches: boolean; track_expiry: boolean; track_serials: boolean; is_active: boolean;
  custom_fields: Record<string, string | boolean>;
};

export default function ProductsPage() {
  return <ErpGate module="inventory" permission="inventory.view"><Products /></ErpGate>;
}

function Products() {
  const { t, toast } = useApp();
  const { config, can } = useErp();
  const wantsNew = useQueryValue("new");
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [lowOnly, setLowOnly] = useState(false);
  const [rows, setRows] = useState<Paginated<Product> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [units, setUnits] = useState<Unit[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [editing, setEditing] = useState<Product | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const fields = config?.settings.product_fields ?? [];
  const currency = config?.settings.base_currency ?? "TZS";

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<Product>>("/erp/products", { q: search || undefined, page, low_stock: lowOnly ? 1 : undefined })
      .then(setRows)
      .catch((e) => setError(e.message));
  }, [search, page, lowOnly]);

  useEffect(() => {
    const timer = window.setTimeout(load, search ? 220 : 0);
    return () => window.clearTimeout(timer);
  }, [load, search]);

  const open = useCallback((product: Product | null, unitList: Unit[] = units) => {
    const d = config?.settings.product_defaults;
    setEditing(product);
    setFormError(null);
    setForm({
      sku: product?.sku ?? "", barcode: product?.barcode ?? "", name: product?.name ?? "", brand: product?.brand ?? "",
      type: product?.type ?? "stock", category_id: product?.category_id ? String(product.category_id) : "",
      unit_id: product ? String(product.unit_id) : String(unitList[0]?.id ?? ""),
      cost_price: product ? String(Number(product.cost_price)) : "", sale_price: product ? String(Number(product.sale_price)) : "",
      reorder_level: product ? String(Number(product.reorder_level)) : "",
      track_batches: product?.track_batches ?? !!d?.track_batches, track_expiry: product?.track_expiry ?? !!d?.track_expiry,
      track_serials: product?.track_serials ?? !!d?.track_serials, is_active: product?.is_active ?? true,
      custom_fields: Object.fromEntries(Object.entries(product?.custom_fields ?? {}).map(([k, v]) => [k, typeof v === "boolean" ? v : String(v)])),
    });
  }, [config, units]);

  // A ?new=1 link opens the form once the units it needs have arrived.
  const mayManage = can("inventory.manage");
  useEffect(() => {
    api.get<{ data: Unit[] }>("/erp/units").then((r) => {
      setUnits(r.data);
      if (wantsNew && mayManage && r.data.length) open(null, r.data);
    }).catch(() => undefined);
    api.get<{ data: Category[] }>("/erp/categories").then((r) => setCategories(r.data)).catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once, when the deep link is known
  }, [wantsNew, mayManage]);

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    const payload = {
      ...form,
      category_id: form.category_id ? Number(form.category_id) : null,
      unit_id: Number(form.unit_id),
      cost_price: Number(form.cost_price || 0), sale_price: Number(form.sale_price || 0), reorder_level: Number(form.reorder_level || 0),
      barcode: form.barcode || null, brand: form.brand || null,
    };
    try {
      if (editing) await api.put(`/erp/products/${editing.id}`, payload);
      else await api.post("/erp/products", payload);
      toast(t("erpSaved"), form.name, "ok");
      setForm(null);
      load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  const set = <K extends keyof Form>(key: K, value: Form[K]) => setForm((f) => (f ? { ...f, [key]: value } : f));

  return (
    <div className="erp-page">
      <PageHeader title={t("erpProducts")} subtitle={t("erpProductsSub")}
        actions={can("inventory.manage") && (
          <button className="btn btn-primary" onClick={() => open(null)} disabled={!units.length}>
            <Icon name="ph-plus" size={18} /> {t("erpNewProduct")}
          </button>
        )} />

      <Toolbar end={<button type="button" className="btn btn-secondary btn-sm" aria-pressed={lowOnly} onClick={() => { setLowOnly((v) => !v); setPage(1); }}>
        <Icon name="ph-warning" size={16} /> {t("erpLowOnly")}
      </button>}>
        <SearchInput value={search} onChange={(v) => { setSearch(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("erpName")}, ${t("erpSku")}, ${t("erpBarcode")}`} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock rows={6} /> : rows.data.length === 0 ? (
        <EmptyState icon="ph-package" title={t("erpNoProducts")} body={search || lowOnly ? undefined : t("erpNoProductsBody")} />
      ) : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead>
                <tr>
                  <th>{t("erpProduct")}</th><th>{t("erpType")}</th><th>{t("erpCategory")}</th>
                  <th className="num">{t("erpOnHand")}</th><th className="num">{t("erpSalePrice")}</th><th>{t("erpTracking")}</th>
                </tr>
              </thead>
              <tbody>
                {rows.data.map((p) => {
                  const onHand = Number(p.on_hand ?? 0);
                  const low = Number(p.reorder_level) > 0 && onHand <= Number(p.reorder_level);
                  return (
                    <tr key={p.id} className="is-clickable">
                      <td>
                        <Link href={`/erp/products/${p.id}`} className="erp-cell-link">
                          <span className="erp-cell-title">{p.name}</span>
                          <span className="erp-cell-sub tnum">{p.sku}{p.barcode ? ` · ${p.barcode}` : ""}</span>
                        </Link>
                      </td>
                      <td>{t(PRODUCT_TYPE_LABEL[p.type])}{!p.is_active && <> <Badge>{t("erpInactive")}</Badge></>}</td>
                      <td>{p.category?.name ?? "-"}</td>
                      <td className="num">
                        {p.type === "service" ? "-" : <>{qty(onHand)} <span className="erp-muted">{p.unit?.code}</span></>}
                        {low && <> <Badge tone="warn" dot>{t("erpLowStock")}</Badge></>}
                      </td>
                      <td className="num">{amount(p.sale_price)}</td>
                      <td className="erp-flags">
                        {p.track_batches && <Badge tone="info">{t("erpBatch")}</Badge>}
                        {p.track_expiry && <Badge tone="info">{t("erpExpiry")}</Badge>}
                        {p.track_serials && <Badge tone="info">{t("erpSerial")}</Badge>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {form && (
        <Dialog open wide title={editing ? t("erpEditProduct") : t("erpNewProduct")} onClose={() => setForm(null)} busy={busy}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || !form.sku || !form.unit_id}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("erpName")} htmlFor="p-name" required error={formError?.field("name")}>
              <input id="p-name" className="input" value={form.name} onChange={(e) => set("name", e.target.value)} />
            </Field>
            <Field label={t("erpSku")} htmlFor="p-sku" required error={formError?.field("sku")}>
              <input id="p-sku" className="input" value={form.sku} onChange={(e) => set("sku", e.target.value.toUpperCase())} />
            </Field>
            <Field label={t("erpBarcode")} htmlFor="p-barcode">
              <input id="p-barcode" className="input" value={form.barcode} onChange={(e) => set("barcode", e.target.value)} />
            </Field>
            <Field label={t("erpBrand")} htmlFor="p-brand">
              <input id="p-brand" className="input" value={form.brand} onChange={(e) => set("brand", e.target.value)} />
            </Field>
            <Field label={t("erpType")} htmlFor="p-type">
              <select id="p-type" className="input" value={form.type} onChange={(e) => set("type", e.target.value as ProductType)}>
                {TYPES.map((x) => <option key={x} value={x}>{t(PRODUCT_TYPE_LABEL[x])}</option>)}
              </select>
            </Field>
            <Field label={t("erpCategory")} htmlFor="p-cat">
              <select id="p-cat" className="input" value={form.category_id} onChange={(e) => set("category_id", e.target.value)}>
                <option value="">-</option>
                {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </Field>
            <Field label={t("erpUnit")} htmlFor="p-unit" required error={formError?.field("unit_id")}>
              <select id="p-unit" className="input" value={form.unit_id} onChange={(e) => set("unit_id", e.target.value)}>
                {units.map((u) => <option key={u.id} value={u.id}>{u.name} ({u.code})</option>)}
              </select>
            </Field>
            <Field label={`${t("erpCostPrice")} (${currency})`} htmlFor="p-cost">
              <input id="p-cost" className="input tnum" type="number" min={0} step="0.01" value={form.cost_price} onChange={(e) => set("cost_price", e.target.value)} />
            </Field>
            <Field label={`${t("erpSalePrice")} (${currency})`} htmlFor="p-sale">
              <input id="p-sale" className="input tnum" type="number" min={0} step="0.01" value={form.sale_price} onChange={(e) => set("sale_price", e.target.value)} />
            </Field>
            <Field label={t("erpReorderLevel")} htmlFor="p-reorder">
              <input id="p-reorder" className="input tnum" type="number" min={0} value={form.reorder_level} onChange={(e) => set("reorder_level", e.target.value)} />
            </Field>
            {fields.map((f) => (
              <Field key={f.key} label={f.label} htmlFor={`p-cf-${f.key}`} error={formError?.field(`custom_fields.${f.key}`)}>
                {f.type === "boolean" ? (
                  <Check label={f.label} checked={!!form.custom_fields[f.key]} onChange={(v) => set("custom_fields", { ...form.custom_fields, [f.key]: v })} />
                ) : (
                  <input id={`p-cf-${f.key}`} className="input" type={f.type === "number" ? "number" : f.type === "date" ? "date" : "text"}
                    value={String(form.custom_fields[f.key] ?? "")}
                    onChange={(e) => set("custom_fields", { ...form.custom_fields, [f.key]: e.target.value })} />
                )}
              </Field>
            ))}
          </div>
          {form.type !== "service" && (
            <div className="erp-checks">
              <Check label={t("erpTrackBatches")} checked={form.track_batches} onChange={(v) => set("track_batches", v)} />
              <Check label={t("erpTrackExpiry")} checked={form.track_expiry} onChange={(v) => set("track_expiry", v)} />
              <Check label={t("erpTrackSerials")} checked={form.track_serials} onChange={(v) => set("track_serials", v)} />
              {editing && <Check label={t("erpActive")} checked={form.is_active} onChange={(v) => set("is_active", v)} />}
            </div>
          )}
          {(formError?.field("track_batches") || formError?.field("track_expiry") || formError?.field("track_serials")) && (
            <div className="field-error" role="alert">{formError?.field("track_batches") ?? formError?.field("track_expiry") ?? formError?.field("track_serials")}</div>
          )}
        </Dialog>
      )}
    </div>
  );
}
