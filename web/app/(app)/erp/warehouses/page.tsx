"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp, type Warehouse } from "@/lib/erp";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate, WAREHOUSE_TYPE_LABEL } from "@/components/erp-ui";

const TYPES = ["warehouse", "depot", "shop", "branch", "production"];
const blank = { code: "", name: "", type: "warehouse", branch: "", location: "", manager_user_id: "", is_active: true };

export default function WarehousesPage() {
  return <ErpGate module="inventory" permission="inventory.view"><Warehouses /></ErpGate>;
}

function Warehouses() {
  const { t, toast } = useApp();
  const { can, config } = useErp();
  const [rows, setRows] = useState<Warehouse[] | null>(null);
  const [people, setPeople] = useState<{ id: number; name: string }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Warehouse | null>(null);
  const [form, setForm] = useState<typeof blank | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Warehouse[] }>("/erp/warehouses").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(() => {
    load();
    api.get<{ data: { id: number; name: string }[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
  }, [load]);

  function open(w: Warehouse | null) {
    setEditing(w); setFormError(null);
    setForm(w ? {
      code: w.code, name: w.name, type: w.type, branch: w.branch ?? "", location: w.location ?? "",
      manager_user_id: w.manager_user_id ? String(w.manager_user_id) : "", is_active: w.is_active,
    } : { ...blank });
  }

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    const payload = { ...form, manager_user_id: form.manager_user_id ? Number(form.manager_user_id) : null };
    try {
      if (editing) await api.put(`/erp/warehouses/${editing.id}`, payload);
      else await api.post("/erp/warehouses", payload);
      toast(t("erpSaved"), form.name, "ok");
      setForm(null); load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally { setBusy(false); }
  }

  const currency = config?.settings.base_currency ?? "TZS";
  const set = (k: keyof typeof blank, v: string | boolean) => setForm((f) => (f ? { ...f, [k]: v } : f));

  return (
    <div className="erp-page">
      <PageHeader title={t("erpWarehouses")} subtitle={t("erpWarehousesSub")}
        actions={can("inventory.manage") && <button className="btn btn-primary" onClick={() => open(null)}><Icon name="ph-plus" size={18} /> {t("erpNewWarehouse")}</button>} />

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-warehouse" title={t("erpWarehouses")} /> : (
        <div className="erp-cards">
          {rows.map((w) => (
            <GlassCard key={w.id} title={<span className="erp-inline-icon"><Icon name="ph-warehouse" size={20} /> {w.name}</span>}
              subtitle={<span className="tnum">{w.code} · {t(WAREHOUSE_TYPE_LABEL[w.type] ?? "erpWhTypeWarehouse")}{w.branch ? ` · ${w.branch}` : ""}</span>}
              action={can("inventory.manage") ? <button className="btn btn-icon" aria-label={t("erpEdit")} onClick={() => open(w)}><Icon name="ph-pencil-simple" size={17} /></button> : undefined}>
              <div className="erp-figures">
                <div><span className="erp-muted">{t("erpStockValue")}</span><strong className="tnum">{currency} {amount(w.stock_value)}</strong></div>
                <div><span className="erp-muted">{t("erpProductsHeld")}</span><strong className="tnum">{w.products_held ?? 0}</strong></div>
              </div>
              <div className="erp-card-foot">
                {w.manager?.name ? <span className="erp-muted"><Icon name="ph-user" size={14} /> {w.manager.name}</span> : <span />}
                {!w.is_active && <Badge>{t("erpInactive")}</Badge>}
              </div>
            </GlassCard>
          ))}
        </div>
      )}

      {form && (
        <Dialog open title={editing ? editing.name : t("erpNewWarehouse")} onClose={() => setForm(null)} busy={busy}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.code || !form.name}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("erpCode")} htmlFor="w-code" required error={formError?.field("code")}>
              <input id="w-code" className="input" value={form.code} onChange={(e) => set("code", e.target.value.toUpperCase())} />
            </Field>
            <Field label={t("erpName")} htmlFor="w-name" required error={formError?.field("name")}>
              <input id="w-name" className="input" value={form.name} onChange={(e) => set("name", e.target.value)} />
            </Field>
            <Field label={t("erpType")} htmlFor="w-type">
              <select id="w-type" className="input" value={form.type} onChange={(e) => set("type", e.target.value)}>
                {TYPES.map((x) => <option key={x} value={x}>{t(WAREHOUSE_TYPE_LABEL[x])}</option>)}
              </select>
            </Field>
            <Field label={t("erpBranch")} htmlFor="w-branch">
              <input id="w-branch" className="input" value={form.branch} onChange={(e) => set("branch", e.target.value)} />
            </Field>
            <Field label={t("erpLocation")} htmlFor="w-loc">
              <input id="w-loc" className="input" value={form.location} onChange={(e) => set("location", e.target.value)} />
            </Field>
            <Field label={t("erpManager")} htmlFor="w-mgr">
              <select id="w-mgr" className="input" value={form.manager_user_id} onChange={(e) => set("manager_user_id", e.target.value)}>
                <option value="">-</option>
                {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </Field>
          </div>
          {editing && <Check label={t("erpActive")} checked={form.is_active} onChange={(v) => set("is_active", v)} />}
        </Dialog>
      )}
    </div>
  );
}
