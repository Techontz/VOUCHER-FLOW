"use client";

import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type AssetClass, type AssetLookups, type AssetMethod, type FixedAsset, today } from "@/lib/finance-api";
import { Dialog, Field } from "@/components/ui";

export const METHOD_LABEL = { straight_line: "finStraightLine", reducing_balance: "finReducingBalance" } as const;

/** Registers an asset (a draft) or edits one; once capitalised only its description changes. */
export function AssetDialog({ asset, onClose, onSaved }: { asset: FixedAsset | null; onClose: () => void; onSaved: (a: FixedAsset) => void }) {
  const { t, toast } = useApp();
  const [classes, setClasses] = useState<AssetClass[]>([]);
  const [lookups, setLookups] = useState<AssetLookups>({ users: [], suppliers: [], locations: [] });
  const locked = !!asset && asset.status !== "draft";
  const [form, setForm] = useState({
    tag: asset?.tag ?? "", name: asset?.name ?? "", description: asset?.description ?? "", asset_class_id: String(asset?.asset_class_id ?? ""),
    serial_number: asset?.serial_number ?? "", location: asset?.location ?? "", custodian_user_id: String(asset?.custodian_user_id ?? ""),
    supplier_id: String(asset?.supplier_id ?? ""), acquisition_date: asset?.acquisition_date.slice(0, 10) ?? today(),
    cost: asset?.cost ?? "", residual_value: asset && Number(asset.residual_value) ? asset.residual_value : "",
    method: (asset?.method ?? "") as AssetMethod | "", useful_life_months: asset ? String(asset.useful_life_months) : "", rate: asset ? asset.rate : "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));

  useEffect(() => {
    api.get<{ data: AssetClass[] }>("/erp/assets/classes").then((r) => setClasses(r.data.filter((c) => c.is_active))).catch(() => setClasses([]));
    api.get<{ data: AssetLookups }>("/erp/assets/lookups").then((r) => setLookups(r.data)).catch(() => undefined);
  }, []);

  function chooseClass(id: string) {
    const c = classes.find((x) => String(x.id) === id);
    set({ asset_class_id: id, ...(c && !asset ? { method: c.method, useful_life_months: String(c.useful_life_months), rate: c.rate } : {}) });
  }

  async function save() {
    setBusy(true); setError(null);
    try {
      const nullable = (v: string) => (v === "" ? null : v);
      const body = locked
        ? { name: form.name, description: nullable(form.description), serial_number: nullable(form.serial_number) }
        : {
          tag: nullable(form.tag), name: form.name, description: nullable(form.description), asset_class_id: Number(form.asset_class_id),
          serial_number: nullable(form.serial_number), location: nullable(form.location),
          custodian_user_id: form.custodian_user_id ? Number(form.custodian_user_id) : null, supplier_id: form.supplier_id ? Number(form.supplier_id) : null,
          acquisition_date: form.acquisition_date, cost: form.cost, residual_value: form.residual_value || 0,
          method: nullable(form.method), useful_life_months: nullable(form.useful_life_months), rate: nullable(form.rate),
        };
      const r = asset
        ? await api.put<{ data: FixedAsset }>(`/erp/assets/register/${asset.id}`, body)
        : await api.post<{ data: FixedAsset }>("/erp/assets/register", body);
      toast(t("erpSaved"), `${r.data.tag} ${r.data.name}`, "ok");
      onSaved(r.data);
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <Dialog open title={asset ? `${asset.tag} · ${asset.name}` : t("finRegisterAsset")} sub={locked ? t("finAssetLockedHint") : t("finRegisterAssetHint")} onClose={onClose} busy={busy} wide
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || (!locked && (!form.asset_class_id || !form.cost))}>{t("erpSave")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <datalist id="asset-locations">{lookups.locations.map((l) => <option key={l} value={l} />)}</datalist>
      <div className="erp-form-grid">
        <Field label={t("erpName")} htmlFor="a-name" required error={error?.field("name")}>
          <input id="a-name" className="input" value={form.name} onChange={(e) => set({ name: e.target.value })} />
        </Field>
        <Field label={t("finAssetTag")} htmlFor="a-tag" hint={asset ? undefined : t("finAssetTagHint")} error={error?.field("tag")}>
          <input id="a-tag" className="input tnum" value={form.tag} disabled={locked} onChange={(e) => set({ tag: e.target.value })} />
        </Field>
        <Field label={t("finAssetClass")} htmlFor="a-class" required error={error?.field("asset_class_id")}>
          <select id="a-class" className="input" value={form.asset_class_id} disabled={locked} onChange={(e) => chooseClass(e.target.value)}>
            <option value="">{t("finChoose")}</option>
            {classes.map((c) => <option key={c.id} value={c.id}>{c.code} · {c.name}</option>)}
          </select>
        </Field>
        <Field label={t("finSerial")} htmlFor="a-serial" error={error?.field("serial_number")}>
          <input id="a-serial" className="input" value={form.serial_number} onChange={(e) => set({ serial_number: e.target.value })} />
        </Field>
        <Field label={t("finAcquired")} htmlFor="a-date" required error={error?.field("acquisition_date")}>
          <input id="a-date" type="date" className="input" max={today()} value={form.acquisition_date} disabled={locked} onChange={(e) => set({ acquisition_date: e.target.value })} />
        </Field>
        <Field label={t("finCost")} htmlFor="a-cost" required error={error?.field("cost")}>
          <input id="a-cost" className="input tnum" inputMode="decimal" value={form.cost} disabled={locked} onChange={(e) => set({ cost: e.target.value })} />
        </Field>
        <Field label={t("finResidual")} htmlFor="a-res" error={error?.field("residual_value")}>
          <input id="a-res" className="input tnum" inputMode="decimal" value={form.residual_value} disabled={locked} onChange={(e) => set({ residual_value: e.target.value })} />
        </Field>
        <Field label={t("finMethod")} htmlFor="a-method" error={error?.field("method")}>
          <select id="a-method" className="input" value={form.method} disabled={locked} onChange={(e) => set({ method: e.target.value as AssetMethod })}>
            <option value="">{t("finFromClass")}</option>
            <option value="straight_line">{t("finStraightLine")}</option>
            <option value="reducing_balance">{t("finReducingBalance")}</option>
          </select>
        </Field>
        <Field label={t("finLifeMonths")} htmlFor="a-life" error={error?.field("useful_life_months")}>
          <input id="a-life" className="input tnum" inputMode="numeric" value={form.useful_life_months} disabled={locked} onChange={(e) => set({ useful_life_months: e.target.value })} />
        </Field>
        <Field label={t("finRate")} htmlFor="a-rate" hint={t("finRateHint")} error={error?.field("rate")}>
          <input id="a-rate" className="input tnum" inputMode="decimal" value={form.rate} disabled={locked} onChange={(e) => set({ rate: e.target.value })} />
        </Field>
        <Field label={t("finLocation")} htmlFor="a-loc" hint={locked ? t("finUseTransfer") : undefined} error={error?.field("location")}>
          <input id="a-loc" className="input" list="asset-locations" value={form.location} disabled={locked} onChange={(e) => set({ location: e.target.value })} />
        </Field>
        <Field label={t("finCustodian")} htmlFor="a-cust" error={error?.field("custodian_user_id")}>
          <select id="a-cust" className="input" value={form.custodian_user_id} disabled={locked} onChange={(e) => set({ custodian_user_id: e.target.value })}>
            <option value="">{t("finNone")}</option>
            {lookups.users.map((u) => <option key={u.id} value={u.id}>{u.name}{u.job_title ? `, ${u.job_title}` : ""}</option>)}
          </select>
        </Field>
        <Field label={t("erpSuppliers")} htmlFor="a-sup" error={error?.field("supplier_id")}>
          <select id="a-sup" className="input" value={form.supplier_id} disabled={locked} onChange={(e) => set({ supplier_id: e.target.value })}>
            <option value="">{t("finNone")}</option>
            {lookups.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label={t("finDescription")} htmlFor="a-desc" error={error?.field("description")}>
          <input id="a-desc" className="input" value={form.description} onChange={(e) => set({ description: e.target.value })} />
        </Field>
      </div>
    </Dialog>
  );
}
