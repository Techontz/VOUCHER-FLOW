"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { compactMoney } from "@/lib/format";
import { type CrmOverview, LEAD_STATUS_LABEL, type LeadStatus, STAGE_LABEL } from "@/lib/crm-types";
import { ErrorState, GlassCard, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { ActivityList, CrmTabs } from "@/components/crm-ui";

export default function CrmOverviewPage() {
  return <ErpGate module="crm" permission="crm.view"><Overview /></ErpGate>;
}

function Overview() {
  const { t } = useApp();
  const { can, config } = useErp();
  const [data, setData] = useState<CrmOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const currency = config?.settings.base_currency ?? "TZS";

  const load = useCallback(() => {
    api.get<{ data: CrmOverview }>("/erp/crm/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return <LoadingBlock rows={6} />;

  const top = Math.max(1, ...data.stages.map((s) => s.value));
  const leadTotal = Math.max(1, ...Object.values(data.leads));

  return (
    <div className="erp-page">
      <PageHeader title={t("crmTitle")} subtitle={t("crmSub")} />
      <CrmTabs />

      <StatPills label={t("crmTitle")} items={[
        { label: t("crmPipelineValue"), value: compactMoney(data.open_value, currency), hint: `${t("crmWeighted")} ${compactMoney(data.weighted_value, currency)}`, icon: "ph-funnel", href: "/erp/crm/pipeline" },
        { label: t("crmWonThisMonth"), value: compactMoney(data.won_this_month.value, currency), hint: fill(t("crmDealsCount"), { n: data.won_this_month.count }), tone: "ok", icon: "ph-trophy" },
        { label: t("crmDueToday"), value: data.due_today_count, tone: data.due_today_count ? "info" : "neutral", icon: "ph-calendar-check", href: "/erp/crm/activities?status=today" },
        { label: t("crmOverdue"), value: data.overdue_count, tone: data.overdue_count ? "bad" : "neutral", icon: "ph-alarm", href: "/erp/crm/activities?status=overdue" },
      ]} />

      <div className="erp-grid">
        <GlassCard title={t("crmByStage")} action={<Link className="vf-card-link" href="/erp/crm/pipeline">{t("crmNavPipeline")}</Link>}>
          <ul className="erp-hbars">
            {data.stages.map((s) => (
              <li key={s.stage}>
                <span className="erp-hbar-label">{t(STAGE_LABEL[s.stage])} <span className="erp-muted tnum">({s.count})</span></span>
                <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(s.value / top) * 100}%` }} /></span>
                <span className="erp-hbar-value tnum">{compactMoney(s.value, currency)}</span>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard title={t("crmDueToday")} pad={false} action={<Link className="vf-card-link" href="/erp/crm/activities?status=today">{t("crmNavActivities")}</Link>}>
          <ActivityList rows={data.due_today} onChanged={load} manage={can("crm.manage")} empty={t("crmNothingDue")} />
        </GlassCard>

        <GlassCard title={t("crmOverdue")} pad={false} action={<Link className="vf-card-link" href="/erp/crm/activities?status=overdue">{t("crmNavActivities")}</Link>}>
          <ActivityList rows={data.overdue} onChanged={load} manage={can("crm.manage")} empty={t("crmNoOverdue")} />
        </GlassCard>

        <GlassCard title={t("crmLeadsByStatus")} action={<Link className="vf-card-link" href="/erp/crm/leads">{t("crmNavLeads")}</Link>}>
          <ul className="erp-hbars">
            {(Object.keys(LEAD_STATUS_LABEL) as LeadStatus[]).map((s) => (
              <li key={s}>
                <Link className="erp-hbar-label" href={`/erp/crm/leads?status=${s}`}>{t(LEAD_STATUS_LABEL[s])}</Link>
                <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${((data.leads[s] ?? 0) / leadTotal) * 100}%` }} /></span>
                <span className="erp-hbar-value tnum">{data.leads[s] ?? 0}</span>
              </li>
            ))}
          </ul>
        </GlassCard>
      </div>
    </div>
  );
}
