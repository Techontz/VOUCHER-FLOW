"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { forgetProductionOptions, type WorkCentre } from "@/lib/production-api";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";

export default function WorkCentresPage() {
  return <ErpGate module="production" permission="production.view"><WorkCentres /></ErpGate>;
}

interface Form { code: string; name: string; description: string; capacity_per_hour: string; hourly_cost: string; is_active: boolean }

const blank: Form = { code: "", name: "", description: "", capacity_per_hour: "", hourly_cost: "0", is_active: true };

function WorkCentres() {
  const { t, toast } = useApp();
  const { can, config } = useErp();
  const [rows, setRows] = useState<WorkCentre[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<WorkCentre | "new" | null>(null);
  const [form, setForm] = useState<Form>(blank);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: WorkCentre[] }>("/erp/production/work-centres").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  function open(centre: WorkCentre | "new") {
    setFormError(null);
    setForm(centre === "new" ? blank : {
      code: centre.code, name: centre.name, description: centre.description ?? "",
      capacity_per_hour: centre.capacity_per_hour ? String(Number(centre.capacity_per_hour)) : "",
      hourly_cost: String(Number(centre.hourly_cost)), is_active: centre.is_active,
    });
    setEditing(centre);
  }

  async function save() {
    setBusy(true); setFormError(null);
    const payload = {
      ...form, description: form.description || null,
      capacity_per_hour: form.capacity_per_hour === "" ? null : Number(form.capacity_per_hour), hourly_cost: Number(form.hourly_cost || 0),
    };
    try {
      if (editing === "new") await api.post("/erp/production/work-centres", payload);
      else if (editing) await api.put(`/erp/production/work-centres/${editing.id}`, payload);
      toast(t("erpSaved"), form.name, "ok");
      forgetProductionOptions();
      setEditing(null);
      load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  const manage = can("production.manage");
  const currency = config?.settings.base_currency ?? "TZS";

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/production/boms" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("prdNavBoms")}</Link>}
        title={t("prdNavCentres")} subtitle={t("prdCentresSub")}
        actions={manage && <button className="btn btn-primary" onClick={() => open("new")}><Icon name="ph-plus" size={18} /> {t("prdNewCentre")}</button>} />

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.length === 0 ? (
        <EmptyState icon="ph-gear-six" title={t("prdNoCentres")} />
      ) : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("prdCode")}</th><th>{t("prdName")}</th><th className="num">{t("prdCapacity")}</th><th className="num">{t("prdHourlyCost")}</th><th className="num">{t("prdNavBoms")}</th><th>{t("erpStatus")}</th>{manage && <th aria-label={t("erpEdit")} />}</tr></thead>
            <tbody>
              {rows.map((w) => (
                <tr key={w.id}>
                  <td className="tnum">{w.code}</td>
                  <td><span className="erp-cell-title">{w.name}</span>{w.description && <span className="erp-cell-sub">{w.description}</span>}</td>
                  <td className="num">{w.capacity_per_hour ? qty(w.capacity_per_hour) : "-"}</td>
                  <td className="num">{currency} {amount(w.hourly_cost)}</td>
                  <td className="num">{w.boms_count ?? 0}</td>
                  <td>{w.is_active ? <Badge tone="ok" dot>{t("prdActive")}</Badge> : <Badge tone="neutral" dot>{t("prdInactive")}</Badge>}</td>
                  {manage && <td><button className="btn btn-icon" aria-label={t("erpEdit")} onClick={() => open(w)}><Icon name="ph-pencil-simple" size={17} /></button></td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Dialog open={editing !== null} onClose={() => setEditing(null)} busy={busy} icon="ph-gear-six"
        title={editing === "new" ? t("prdNewCentre") : t("prdEditCentre")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy || !form.code || !form.name}>{t("erpSave")}</button>
        </>}>
        <div className="erp-form-grid">
          <Field label={t("prdCode")} htmlFor="wc-code" required error={formError?.field("code")}>
            <input id="wc-code" className="input" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} />
          </Field>
          <Field label={t("prdName")} htmlFor="wc-name" required error={formError?.field("name")}>
            <input id="wc-name" className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field label={t("prdCapacity")} htmlFor="wc-cap" hint={t("erpOptional")} error={formError?.field("capacity_per_hour")}>
            <input id="wc-cap" className="input tnum" type="number" min={0} step="any" value={form.capacity_per_hour} onChange={(e) => setForm({ ...form, capacity_per_hour: e.target.value })} />
          </Field>
          <Field label={t("prdHourlyCost")} htmlFor="wc-cost" hint={currency} error={formError?.field("hourly_cost")}>
            <input id="wc-cost" className="input tnum" type="number" min={0} step="any" value={form.hourly_cost} onChange={(e) => setForm({ ...form, hourly_cost: e.target.value })} />
          </Field>
        </div>
        <Field label={t("prdDescription")} htmlFor="wc-desc" hint={t("erpOptional")} error={formError?.field("description")}>
          <textarea id="wc-desc" className="input" rows={2} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
        </Field>
        <Check label={t("prdActive")} checked={form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} />
        {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {formError.message}</div>}
      </Dialog>
    </div>
  );
}
