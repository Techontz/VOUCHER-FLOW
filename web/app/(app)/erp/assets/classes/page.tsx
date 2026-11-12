"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import type { AccountRef, AssetClass, AssetMethod } from "@/lib/finance-api";
import { Badge, Dialog, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { AssetTabs } from "@/components/finance-ui";
import { METHOD_LABEL } from "@/components/finance-asset-form";

export default function ClassesPage() {
  return <ErpGate module="assets" permission="assets.view"><Classes /></ErpGate>;
}

type Form = { row: AssetClass | null; code: string; name: string; method: AssetMethod; useful_life_months: string; rate: string; asset_account_id: string; depreciation_account_id: string; expense_account_id: string; is_active: boolean };

function Classes() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const [rows, setRows] = useState<AssetClass[] | null>(null);
  const [accounts, setAccounts] = useState<AccountRef[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const may = can("assets.manage");

  const load = useCallback(() => { api.get<{ data: AssetClass[] }>("/erp/assets/classes").then((r) => setRows(r.data)).catch((e) => setError(e.message)); }, []);
  useEffect(load, [load]);
  useEffect(() => { if (may) api.get<{ data: AccountRef[] }>("/erp/assets/class-accounts").then((r) => setAccounts(r.data)).catch(() => setAccounts([])); }, [may]);

  function edit(c: AssetClass | null) {
    setFormError(null);
    setForm({
      row: c, code: c?.code ?? "", name: c?.name ?? "", method: c?.method ?? "reducing_balance", useful_life_months: String(c?.useful_life_months ?? 60),
      rate: c?.rate ?? "", asset_account_id: String(c?.asset_account_id ?? ""), depreciation_account_id: String(c?.depreciation_account_id ?? ""),
      expense_account_id: String(c?.expense_account_id ?? ""), is_active: c?.is_active ?? true,
    });
  }

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    try {
      const body = { ...form, row: undefined, rate: form.rate || 0 };
      if (form.row) await api.put(`/erp/assets/classes/${form.row.id}`, body); else await api.post("/erp/assets/classes", body);
      toast(t("erpSaved"), form.name, "ok");
      setForm(null); load();
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!rows) return <LoadingBlock rows={5} />;

  const assetAccounts = accounts.filter((a) => a.type === "asset");
  const expenseAccounts = accounts.filter((a) => a.type === "expense");

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabClasses")} subtitle={t("finClassesSub")}
        actions={may && <button className="btn btn-primary" onClick={() => edit(null)}><Icon name="ph-plus" size={18} /> {t("finNewClass")}</button>} />
      <AssetTabs />

      <div className="vf-table-wrap">
        <table className="table vf-table">
          <thead><tr><th>{t("erpCode")}</th><th>{t("erpName")}</th><th>{t("finMethod")}</th><th className="num">{t("finRate")}</th><th className="num">{t("finLifeMonths")}</th><th>{t("finAccounts")}</th><th className="num">{t("finAssetsCount")}</th></tr></thead>
          <tbody>
            {rows.map((c) => (
              <tr key={c.id} className={may ? "is-clickable" : undefined} onClick={may ? () => edit(c) : undefined}>
                <td className="tnum">{c.code}</td>
                <td>{c.name} {!c.is_active && <Badge>{t("erpInactive")}</Badge>}</td>
                <td>{t(METHOD_LABEL[c.method])}</td>
                <td className="num">{c.method === "reducing_balance" ? `${Number(c.rate)}%` : "-"}</td>
                <td className="num">{c.useful_life_months}</td>
                <td className="tnum">{c.asset_account?.code} / {c.depreciation_account?.code} / {c.expense_account?.code}</td>
                <td className="num">{c.assets_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="erp-muted">{t("finClassesNote")}</p>

      {form && (
        <Dialog open title={form.row ? form.row.name : t("finNewClass")} onClose={() => setForm(null)} busy={busy} wide sub={t("finClassHint")}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.code || !form.name}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("erpCode")} htmlFor="k-code" required error={formError?.field("code")}><input id="k-code" className="input" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} /></Field>
            <Field label={t("erpName")} htmlFor="k-name" required error={formError?.field("name")}><input id="k-name" className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label={t("finMethod")} htmlFor="k-method" error={formError?.field("method")}>
              <select id="k-method" className="input" value={form.method} onChange={(e) => setForm({ ...form, method: e.target.value as AssetMethod })}>
                <option value="straight_line">{t("finStraightLine")}</option><option value="reducing_balance">{t("finReducingBalance")}</option>
              </select>
            </Field>
            <Field label={t("finRate")} htmlFor="k-rate" hint={t("finRateHint")} error={formError?.field("rate")}><input id="k-rate" className="input tnum" inputMode="decimal" value={form.rate} onChange={(e) => setForm({ ...form, rate: e.target.value })} /></Field>
            <Field label={t("finLifeMonths")} htmlFor="k-life" error={formError?.field("useful_life_months")}><input id="k-life" className="input tnum" inputMode="numeric" value={form.useful_life_months} onChange={(e) => setForm({ ...form, useful_life_months: e.target.value })} /></Field>
            <Field label={t("finAssetAccount")} htmlFor="k-asset" error={formError?.field("asset_account_id")}>
              <select id="k-asset" className="input" value={form.asset_account_id} onChange={(e) => setForm({ ...form, asset_account_id: e.target.value })}>
                <option value="">{t("finChoose")}</option>{assetAccounts.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
              </select>
            </Field>
            <Field label={t("finDepreciationAccount")} htmlFor="k-dep" error={formError?.field("depreciation_account_id")}>
              <select id="k-dep" className="input" value={form.depreciation_account_id} onChange={(e) => setForm({ ...form, depreciation_account_id: e.target.value })}>
                <option value="">{t("finChoose")}</option>{assetAccounts.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
              </select>
            </Field>
            <Field label={t("finExpenseAccount")} htmlFor="k-exp" error={formError?.field("expense_account_id")}>
              <select id="k-exp" className="input" value={form.expense_account_id} onChange={(e) => setForm({ ...form, expense_account_id: e.target.value })}>
                <option value="">{t("finChoose")}</option>{expenseAccounts.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
              </select>
            </Field>
          </div>
          <Check label={t("erpActive")} checked={form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} />
        </Dialog>
      )}
    </div>
  );
}
