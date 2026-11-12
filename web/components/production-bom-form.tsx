"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type Bom, useProductionOptions } from "@/lib/production-api";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";

interface Line { product_id: string; quantity: string; scrap_percent: string; note: string }

const blank: Line = { product_id: "", quantity: "", scrap_percent: "0", note: "" };

/**
 * Creates a bill of materials, or edits a version no order has used yet.
 * Quantities are per batch of the output quantity; the scrap allowance is a
 * percentage on top that the requirement check and the variance both use.
 */
export function BomForm({ existing, presetProduct }: { existing?: Bom; presetProduct?: string | null }) {
  const { t, toast } = useApp();
  const { config } = useErp();
  const router = useRouter();
  const { options, error } = useProductionOptions();
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const [productId, setProductId] = useState(existing ? String(existing.product_id) : presetProduct ?? "");
  const [name, setName] = useState(existing?.name ?? "");
  const [output, setOutput] = useState(existing ? String(Number(existing.output_quantity)) : "100");
  const [centreId, setCentreId] = useState(existing?.work_centre_id ? String(existing.work_centre_id) : "");
  const [labour, setLabour] = useState(existing ? String(Number(existing.labour_cost)) : "0");
  const [overhead, setOverhead] = useState(existing ? String(Number(existing.overhead_cost)) : "0");
  const [notes, setNotes] = useState(existing?.notes ?? "");
  const [lines, setLines] = useState<Line[]>(existing?.lines?.map((l) => ({
    product_id: String(l.product_id), quantity: String(Number(l.quantity)), scrap_percent: String(Number(l.scrap_percent)), note: l.note ?? "",
  })) ?? [{ ...blank }]);

  const byId = useMemo(() => new Map((options?.materials ?? []).map((p) => [String(p.id), p])), [options]);
  const setLine = (i: number, patch: Partial<Line>) => setLines((all) => all.map((l, j) => (j === i ? { ...l, ...patch } : l)));

  // An estimate at list cost; the saved version shows the standard at average cost.
  const perUnit = lines.reduce((sum, l) => {
    const p = byId.get(l.product_id);
    return sum + (p ? Number(l.quantity || 0) * (1 + Number(l.scrap_percent || 0) / 100) * Number(p.cost_price) : 0);
  }, 0) / Math.max(Number(output || 0), 0.0001) + (Number(labour || 0) + Number(overhead || 0)) / Math.max(Number(output || 0), 0.0001);

  async function save() {
    setBusy(true); setFormError(null);
    const payload = {
      product_id: Number(productId), name: name || null, output_quantity: Number(output),
      work_centre_id: centreId ? Number(centreId) : null, labour_cost: Number(labour || 0), overhead_cost: Number(overhead || 0),
      notes: notes || null,
      lines: lines.filter((l) => l.product_id).map((l) => ({
        product_id: Number(l.product_id), quantity: Number(l.quantity), scrap_percent: Number(l.scrap_percent || 0), note: l.note || null,
      })),
    };
    try {
      const r = existing
        ? await api.put<{ data: Bom }>(`/erp/production/boms/${existing.id}`, payload)
        : await api.post<{ data: Bom }>("/erp/production/boms", payload);
      toast(t("erpSaved"), r.data.name, "ok");
      router.push(`/erp/production/boms/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!options) return <LoadingBlock rows={5} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const back = existing ? `/erp/production/boms/${existing.id}` : "/erp/production/boms";
  const finishedUnit = options.finished.find((p) => String(p.id) === productId)?.unit?.code;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={back} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("prdNavBoms")}</Link>}
        kicker={existing ? `${t("prdVersion")} ${existing.version}` : undefined}
        title={existing ? existing.name : t("prdNewBom")} subtitle={t("prdBomFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("prdFinishedProduct")} htmlFor="b-product" required error={formError?.field("product_id")}>
            <select id="b-product" className="input" value={productId} disabled={!!existing} onChange={(e) => setProductId(e.target.value)}>
              <option value="">{t("erpPickProduct")}</option>
              {options.finished.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}
            </select>
          </Field>
          <Field label={t("prdBomName")} htmlFor="b-name" hint={t("prdBomNameHint")} error={formError?.field("name")}>
            <input id="b-name" className="input" value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <Field label={t("prdOutputQty")} htmlFor="b-out" required hint={finishedUnit} error={formError?.field("output_quantity")}>
            <input id="b-out" className="input tnum" type="number" min={0} step="any" value={output} onChange={(e) => setOutput(e.target.value)} />
          </Field>
          <Field label={t("prdWorkCentre")} htmlFor="b-wc" hint={t("erpOptional")} error={formError?.field("work_centre_id")}>
            <select id="b-wc" className="input" value={centreId} onChange={(e) => setCentreId(e.target.value)}>
              <option value="">-</option>
              {options.work_centres.map((w) => <option key={w.id} value={w.id}>{w.code} · {w.name}</option>)}
            </select>
          </Field>
          <Field label={t("prdLabourPerBatch")} htmlFor="b-lab" hint={currency} error={formError?.field("labour_cost")}>
            <input id="b-lab" className="input tnum" type="number" min={0} step="any" value={labour} onChange={(e) => setLabour(e.target.value)} />
          </Field>
          <Field label={t("prdOverheadPerBatch")} htmlFor="b-ovh" hint={currency} error={formError?.field("overhead_cost")}>
            <input id="b-ovh" className="input tnum" type="number" min={0} step="any" value={overhead} onChange={(e) => setOverhead(e.target.value)} />
          </Field>
        </div>
        <Field label={t("prdNotes")} htmlFor="b-notes" hint={t("erpOptional")}>
          <textarea id="b-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      <GlassCard title={t("prdComponents")} subtitle={t("prdComponentsSub")} pad={false}>
        <div className="vf-table-wrap">
          <table className="table vf-table erp-lines">
            <thead>
              <tr>
                <th style={{ minWidth: 220 }}>{t("prdComponent")}</th>
                <th className="num" style={{ width: 140 }}>{t("prdQtyPerBatch")}</th>
                <th className="num" style={{ width: 120 }}>{t("prdScrapPercent")}</th>
                <th style={{ minWidth: 140 }}>{t("prdNotes")}</th>
                <th style={{ width: 48 }} aria-label={t("erpRemove")} />
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={i}>
                  <td>
                    <select className="input" aria-label={t("prdComponent")} value={l.product_id} onChange={(e) => setLine(i, { product_id: e.target.value })}>
                      <option value="">{t("erpPickProduct")}</option>
                      {options.materials.filter((p) => String(p.id) !== productId).map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}
                    </select>
                    {formError?.field(`lines.${i}.product_id`) && <div className="field-error">{formError.field(`lines.${i}.product_id`)}</div>}
                  </td>
                  <td className="num">
                    <input className="input tnum" type="number" min={0} step="any" aria-label={t("prdQtyPerBatch")} value={l.quantity} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                    {byId.get(l.product_id)?.unit && <span className="erp-cell-sub">{byId.get(l.product_id)?.unit?.code}</span>}
                    {formError?.field(`lines.${i}.quantity`) && <div className="field-error">{formError.field(`lines.${i}.quantity`)}</div>}
                  </td>
                  <td className="num">
                    <input className="input tnum" type="number" min={0} max={100} step="any" aria-label={t("prdScrapPercent")} value={l.scrap_percent} onChange={(e) => setLine(i, { scrap_percent: e.target.value })} />
                  </td>
                  <td><input className="input" aria-label={t("prdNotes")} value={l.note} onChange={(e) => setLine(i, { note: e.target.value })} /></td>
                  <td>
                    <button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={lines.length === 1}
                      onClick={() => setLines((all) => all.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="erp-lines-foot">
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setLines((all) => [...all, { ...blank }])}>
            <Icon name="ph-plus" size={16} /> {t("prdAddComponent")}
          </button>
          <span className="tnum"><span className="erp-muted">{t("prdEstimatedUnitCost")}</span> <strong>{currency} {amount(Math.round(perUnit * 100) / 100)}</strong></span>
        </div>
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href={back}>{t("erpCancel")}</Link>
        <button type="button" className="btn btn-primary" onClick={save}
          disabled={busy || !productId || !(Number(output) > 0) || !lines.some((l) => l.product_id && Number(l.quantity) > 0)}>
          <Icon name="ph-floppy-disk" size={18} /> {t("prdSaveBom")}
        </button>
      </div>
    </div>
  );
}
