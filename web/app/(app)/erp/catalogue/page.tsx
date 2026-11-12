"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Category, type Unit, useErp } from "@/lib/erp";
import { Badge, Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";

type Editing =
  | { kind: "unit"; row: Unit | null; code: string; name: string; allows_decimals: boolean }
  | { kind: "category"; row: Category | null; name: string; parent_id: string };

export default function CataloguePage() {
  return <ErpGate module="inventory" permission="inventory.view"><Catalogue /></ErpGate>;
}

function Catalogue() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const [units, setUnits] = useState<Unit[] | null>(null);
  const [categories, setCategories] = useState<Category[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const manage = can("inventory.manage");

  const load = useCallback(() => {
    api.get<{ data: Unit[] }>("/erp/units").then((r) => setUnits(r.data)).catch((e) => setError(e.message));
    api.get<{ data: Category[] }>("/erp/categories").then((r) => setCategories(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  async function save() {
    if (!editing) return;
    setBusy(true); setFormError(null);
    try {
      if (editing.kind === "unit") {
        const body = { code: editing.code, name: editing.name, allows_decimals: editing.allows_decimals };
        if (editing.row) await api.put(`/erp/units/${editing.row.id}`, body); else await api.post("/erp/units", body);
      } else {
        const body = { name: editing.name, parent_id: editing.parent_id ? Number(editing.parent_id) : null };
        if (editing.row) await api.put(`/erp/categories/${editing.row.id}`, body); else await api.post("/erp/categories", body);
      }
      toast(t("erpSaved"), editing.name, "ok");
      setEditing(null); load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally { setBusy(false); }
  }

  async function remove() {
    if (!editing?.row) return;
    setBusy(true); setFormError(null);
    try {
      await api.delete(`/erp/${editing.kind === "unit" ? "units" : "categories"}/${editing.row.id}`);
      setEditing(null); load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!units || !categories) return <LoadingBlock />;

  return (
    <div className="erp-page">
      <PageHeader title={t("erpCatalogue")} subtitle={t("erpCatalogueSub")} />
      <div className="erp-grid">
        <GlassCard title={t("erpUnits")} subtitle={String(units.length)} pad={false}
          action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setEditing({ kind: "unit", row: null, code: "", name: "", allows_decimals: false }); }}><Icon name="ph-plus" size={15} /> {t("erpNewUnit")}</button> : undefined}>
          <ul className="erp-list">
            {units.map((u) => (
              <li key={u.id}>
                <button type="button" className="erp-list-row" disabled={!manage}
                  onClick={() => { setFormError(null); setEditing({ kind: "unit", row: u, code: u.code, name: u.name, allows_decimals: u.allows_decimals }); }}>
                  <span className="erp-list-icon tnum">{u.code}</span>
                  <span className="erp-list-main"><span className="erp-list-title">{u.name}</span></span>
                  <Badge tone={u.allows_decimals ? "info" : "neutral"}>{u.allows_decimals ? t("erpAllowsDecimals") : t("erpWholeOnly")}</Badge>
                </button>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard title={t("erpCategories")} subtitle={String(categories.length)} pad={false}
          action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setEditing({ kind: "category", row: null, name: "", parent_id: "" }); }}><Icon name="ph-plus" size={15} /> {t("erpNewCategory")}</button> : undefined}>
          <ul className="erp-list">
            {categories.map((c) => (
              <li key={c.id}>
                <button type="button" className="erp-list-row" disabled={!manage}
                  onClick={() => { setFormError(null); setEditing({ kind: "category", row: c, name: c.name, parent_id: c.parent_id ? String(c.parent_id) : "" }); }}>
                  <span className="erp-list-icon"><Icon name="ph-folder" size={18} /></span>
                  <span className="erp-list-main">
                    <span className="erp-list-title">{c.name}</span>
                    {c.parent_id && <span className="erp-list-sub">{categories.find((p) => p.id === c.parent_id)?.name}</span>}
                  </span>
                  <span className="tnum erp-muted">{c.products_count ?? 0}</span>
                </button>
              </li>
            ))}
          </ul>
        </GlassCard>
      </div>

      {editing && (
        <Dialog open title={editing.row ? editing.name || "-" : editing.kind === "unit" ? t("erpNewUnit") : t("erpNewCategory")}
          onClose={() => setEditing(null)} busy={busy}
          actions={<>
            {editing.row && <button className="btn btn-danger" onClick={remove} disabled={busy} style={{ marginRight: "auto" }}>{t("erpDelete")}</button>}
            <button className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !editing.name}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          {editing.kind === "unit" ? (
            <>
              <div className="erp-form-grid">
                <Field label={t("erpCode")} htmlFor="u-code" required error={formError?.field("code")}>
                  <input id="u-code" className="input" value={editing.code} onChange={(e) => setEditing({ ...editing, code: e.target.value.toUpperCase() })} />
                </Field>
                <Field label={t("erpName")} htmlFor="u-name" required error={formError?.field("name")}>
                  <input id="u-name" className="input" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
                </Field>
              </div>
              <Check label={t("erpAllowsDecimals")} checked={editing.allows_decimals} onChange={(v) => setEditing({ ...editing, allows_decimals: v })} />
            </>
          ) : (
            <div className="erp-form-grid">
              <Field label={t("erpName")} htmlFor="c-name" required error={formError?.field("name")}>
                <input id="c-name" className="input" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
              </Field>
              <Field label={t("erpCategory")} htmlFor="c-parent" hint={t("erpOptional")}>
                <select id="c-parent" className="input" value={editing.parent_id} onChange={(e) => setEditing({ ...editing, parent_id: e.target.value })}>
                  <option value="">-</option>
                  {categories.filter((c) => c.id !== editing.row?.id).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </Field>
            </div>
          )}
        </Dialog>
      )}
    </div>
  );
}
