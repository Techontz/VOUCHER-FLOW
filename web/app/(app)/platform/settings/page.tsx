"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";

/*
 * Platform-wide defaults: the trial a new company gets when its plan names
 * none, the support address, and the currency new companies and plans start
 * in. Stored by PUT /platform/settings and read by billing and provisioning.
 */

interface Settings { trial_days: number; support_email: string | null; default_currency: string }

const CURRENCIES = ["TZS", "KES", "UGX", "RWF", "USD", "EUR"];

export default function PlatformSettingsPage() {
  const { t, toast, reportError } = useApp();
  const [saved, setSaved] = useState<Settings | null>(null);
  const [form, setForm] = useState({ trial_days: "", support_email: "", default_currency: "TZS" });
  const [error, setError] = useState<string | null>(null);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  const fillForm = (s: Settings) => {
    setSaved(s);
    setForm({ trial_days: String(s.trial_days), support_email: s.support_email ?? "", default_currency: s.default_currency });
  };

  const load = useCallback(() => {
    api.get<{ data: Settings }>("/platform/settings")
      .then((r) => { setError(null); fillForm(r.data); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setFormError(null);
    try {
      const res = await api.put<{ data: Settings }>("/platform/settings", {
        trial_days: Number(form.trial_days), support_email: form.support_email.trim() || null, default_currency: form.default_currency,
      });
      fillForm(res.data);
      toast(t("pfSettingsSaved"), undefined, "ok");
    } catch (err) {
      if (err instanceof ApiError && Object.keys(err.errors).length) setFormError(err);
      else reportError(err, t("pfActionFailed"));
    } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!saved) return <LoadingBlock rows={4} />;

  const dirty = form.trial_days !== String(saved.trial_days) || form.support_email !== (saved.support_email ?? "") || form.default_currency !== saved.default_currency;

  return (
    <div className="app-page pf-page">
      <PageHeader kicker={t("pfPlatform")} title={t("pfPlatformSettings")} subtitle={t("pfPlatformSettingsSub")} />

      <form className="pf-settings" onSubmit={(e) => void save(e)}>
        <GlassCard title={t("pfBillingDefaults")} subtitle={t("pfBillingDefaultsSub")}>
          <div className="pf-form-row">
            <Field label={t("pfDefaultTrial")} htmlFor="ps-trial" hint={t("pfDefaultTrialHint")} error={formError?.field("trial_days")} required>
              <input id="ps-trial" className="input tnum" type="number" min={0} max={365} value={form.trial_days}
                onChange={(e) => setForm((f) => ({ ...f, trial_days: e.target.value }))} />
            </Field>
            <Field label={t("pfDefaultCurrency")} htmlFor="ps-currency" hint={t("pfDefaultCurrencyHint")} error={formError?.field("default_currency")}>
              <select id="ps-currency" className="input" value={form.default_currency} onChange={(e) => setForm((f) => ({ ...f, default_currency: e.target.value }))}>
                {[...new Set([form.default_currency, ...CURRENCIES])].map((c) => <option key={c}>{c}</option>)}
              </select>
            </Field>
          </div>
        </GlassCard>

        <GlassCard title={t("pfSupport")} subtitle={t("pfSupportSub")}>
          <Field label={t("pfSupportEmail")} htmlFor="ps-email" error={formError?.field("support_email")}>
            <input id="ps-email" className="input" type="email" value={form.support_email} placeholder="support@vouchflow.co.tz"
              onChange={(e) => setForm((f) => ({ ...f, support_email: e.target.value }))} />
          </Field>
        </GlassCard>

        <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
          <button type="button" className="btn btn-secondary" disabled={busy || !dirty} onClick={() => fillForm(saved)}>{t("pfDiscard")}</button>
          <button type="submit" className="btn btn-primary" disabled={busy || !dirty || form.trial_days === ""}>
            {busy ? <Spinner /> : <><Icon name="ph-check" size={16} /> {t("saveChanges")}</>}
          </button>
        </div>
      </form>
    </div>
  );
}
