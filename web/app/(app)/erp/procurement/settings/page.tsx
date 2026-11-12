"use client";

import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { forgetLookups, type ProcurementSettings } from "@/lib/procurement-api";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { BackLink } from "@/components/procurement-ui";

const SENIOR_ROLES = ["finance", "director", "ceo", "manager", "hod", "accountant"] as const;

export default function ProcurementSettingsPage() {
  return <ErpGate module="procurement" permission="erp.configure"><SettingsForm /></ErpGate>;
}

function SettingsForm() {
  const { t, toast } = useApp();
  const [form, setForm] = useState<Record<string, string> | null>(null);
  const [senior, setSenior] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => {
    api.get<{ data: ProcurementSettings }>("/erp/procurement/settings").then((r) => {
      setForm({
        approval_threshold: String(Number(r.data.approval_threshold)), receipt_tolerance_percent: String(Number(r.data.receipt_tolerance_percent)),
        price_tolerance_percent: String(Number(r.data.price_tolerance_percent)), quantity_tolerance_percent: String(Number(r.data.quantity_tolerance_percent)),
        default_vat_rate: String(Number(r.data.default_vat_rate)),
      });
      setSenior(r.data.senior_roles ?? ["finance", "director", "ceo"]);
    }).catch((e) => setError(e.message));
  }, []);

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    try {
      await api.put("/erp/procurement/settings", { ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, Number(v)])), senior_roles: senior });
      forgetLookups();
      toast(t("erpSaved"), undefined, "ok");
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!form) return <LoadingBlock rows={4} />;

  const input = (key: string, label: string, hint: string) => (
    <Field label={label} htmlFor={`ps-${key}`} hint={hint} error={formError?.field(key)}>
      <input id={`ps-${key}`} className="input tnum" type="number" min={0} step="any" value={form[key]} onChange={(e) => setForm({ ...form, [key]: e.target.value })} />
    </Field>
  );

  return (
    <div className="erp-page">
      <PageHeader back={<BackLink href="/erp/procurement" label={t("prcOverview")} />} title={t("prcSettings")} subtitle={t("prcSettingsSub")} />
      <GlassCard title={t("prcApprovals")}>
        <div className="erp-form-grid">{input("approval_threshold", t("prcThreshold"), t("prcThresholdHint"))}</div>
        <p className="erp-muted">{t("prcSeniorRolesHint")}</p>
        <div className="erp-checks">
          {SENIOR_ROLES.map((r) => <Check key={r} label={r.replace("_", " ")} checked={senior.includes(r)} onChange={(v) => setSenior((s) => (v ? [...s, r] : s.filter((x) => x !== r)))} />)}
        </div>
      </GlassCard>
      <GlassCard title={t("prcTolerances")}>
        <div className="erp-form-grid">
          {input("receipt_tolerance_percent", t("prcReceiptTolerance"), t("prcReceiptToleranceHint"))}
          {input("price_tolerance_percent", t("prcPriceTolerance"), t("prcPriceToleranceHint"))}
          {input("quantity_tolerance_percent", t("prcQuantityTolerance"), t("prcQuantityToleranceHint"))}
          {input("default_vat_rate", t("prcDefaultVat"), t("prcDefaultVatHint"))}
        </div>
      </GlassCard>
      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}
      <div className="erp-stepnav">
        <button type="button" className="btn btn-primary" disabled={busy} onClick={save}><Icon name="ph-floppy-disk" size={18} /> {t("prcSaveSettings")}</button>
      </div>
    </div>
  );
}
