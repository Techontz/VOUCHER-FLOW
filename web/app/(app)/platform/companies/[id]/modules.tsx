"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { fill } from "@/lib/platform";
import { AppPicker, planApps } from "@/components/app-picker";
import { Banner, GlassCard, Icon, Spinner } from "@/components/ui";
import { UsageMeter } from "@/components/charts";
import type { Plan, Usage } from "@/lib/types";

/*
 * The apps in the company's subscription, set by the platform operator, and
 * its use of the plan's limits. Payment vouchers are the product itself and
 * cannot be removed. Saving sends the whole set; the API switches newly added
 * apps on, switches removed ones off, and records both in the audit trail.
 */

export interface ModuleInfo { key: string; label: string; phase: number; live: boolean }

export function ModulesTab({ companyId, licensed, enabled, plan, usage, onSaved }: {
  companyId: number;
  /** The apps the subscription allows. */
  licensed: string[];
  /** The apps the company has switched on, always among the licensed ones. */
  enabled: string[];
  plan: Plan | null | undefined;
  usage: Usage;
  onSaved: () => void;
}) {
  const { t, toast, reportError } = useApp();
  const [chosen, setChosen] = useState<string[]>(licensed);
  const [busy, setBusy] = useState(false);
  const norm = (list: string[]) => [...new Set(["vouchflow", ...list])].sort().join();
  const dirty = norm(chosen) !== norm(licensed);
  const offered = planApps(plan);

  async function save() {
    setBusy(true);
    try {
      await api.put(`/platform/companies/${companyId}/modules`, { modules: chosen.filter((m) => m !== "vouchflow") });
      toast(t("pfAppsSaved"), undefined, "ok");
      onSaved();
    } catch (err) {
      reportError(err, t("pfActionFailed"));
    } finally { setBusy(false); }
  }

  const unlimited = t("pfUnlimited");

  return (
    <div className="app-stack app-co-stack">
      <GlassCard title={t("pfAppsTitle")} subtitle={t("pfAppsSub")}
        action={plan ? (
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => setChosen(offered)} disabled={busy}>
            <Icon name="ph-magic-wand" size={15} /> {fill(t("pfUsePlanModules"), { plan: plan.name })}
          </button>
        ) : undefined}>
        <p className="field-hint" style={{ margin: "0 0 12px" }}>{fill(t("pfAppsInUse"), { n: enabled.length })}</p>
        <AppPicker operator plan={plan ?? null} value={chosen} onChange={setChosen} disabled={busy} />
        {dirty && (
          <div style={{ marginTop: 16 }}>
            <Banner tone="accent" icon="ph-info" title={t("pfUnsaved")}
              action={<div style={{ display: "flex", gap: 8 }}>
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => setChosen(licensed)} disabled={busy}>{t("pfDiscard")}</button>
                <button type="button" className="btn btn-primary btn-sm" onClick={() => void save()} disabled={busy}>{busy ? <Spinner /> : t("saveChanges")}</button>
              </div>}>
              {t("pfModulesNote")}
            </Banner>
          </div>
        )}
      </GlassCard>

      <GlassCard title={t("pfUsage")} subtitle={plan ? fill(t("pfUsageSub"), { plan: plan.name }) : t("pfNoPlan")}>
        <div className="pf-meters">
          <UsageMeter label={t("users")} used={usage.users.used} limit={usage.users.limit} unlimitedLabel={unlimited} />
          <UsageMeter label={t("pfVouchersThisMonth")} used={usage.vouchers_this_month.used} limit={usage.vouchers_this_month.limit} unlimitedLabel={unlimited} />
          <UsageMeter label={t("pfDepartments")} used={usage.departments.used} limit={usage.departments.limit} unlimitedLabel={unlimited} />
          <UsageMeter label={t("pfStorage")} used={usage.storage.used} limit={usage.storage.limit} unlimitedLabel={unlimited} unit="MB" />
        </div>
      </GlassCard>
    </div>
  );
}
