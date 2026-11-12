"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type AssetsOverview, periodLabel } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, AssetTabs } from "@/components/finance-ui";

export default function AssetsPage() {
  return <ErpGate module="assets" permission="assets.view"><Overview /></ErpGate>;
}

function Overview() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [data, setData] = useState<AssetsOverview | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: AssetsOverview }>("/erp/assets/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return <LoadingBlock rows={6} />;

  const max = Math.max(1, ...data.by_class.map((c) => c.book_value));

  return (
    <div className="erp-page">
      <PageHeader title={t("finAssetsTitle")} subtitle={t("finAssetsSub")}
        actions={<>
          {can("assets.depreciate") && data.next_period && <Link className="btn btn-secondary" href="/erp/assets/depreciation"><Icon name="ph-trend-down" size={17} /> {t("finRunDepreciation")}</Link>}
          {can("assets.manage") && <Link className="btn btn-primary" href="/erp/assets/register?new=1"><Icon name="ph-plus" size={18} /> {t("finRegisterAsset")}</Link>}
        </>} />
      <AssetTabs />

      <StatPills items={[
        { label: t("finCost"), value: amount(data.cost), icon: "ph-coins" },
        { label: t("finAccumulated"), value: amount(data.accumulated), icon: "ph-trend-down" },
        { label: t("finBookValue"), value: amount(data.book_value), icon: "ph-scales" },
        { label: t("finAssetActive"), value: data.counts.active, icon: "ph-cube", hint: `${data.counts.draft} ${t("finAssetDraft").toLowerCase()} · ${data.counts.disposed} ${t("finAssetDisposed").toLowerCase()}` },
      ]} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("finByClass")} subtitle={t("finBookValue")}>
          {data.by_class.length === 0 ? <EmptyState icon="ph-squares-four" title={t("finNoAssets")} /> : (
            <ul className="erp-hbars">
              {data.by_class.map((c) => (
                <li key={c.id}>
                  <span className="erp-hbar-label">{c.name} <span className="erp-muted">({c.count})</span></span>
                  <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(c.book_value / max) * 100}%` }} /></span>
                  <span className="erp-hbar-value tnum">{amount(c.book_value)}</span>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("finDepreciation")} action={<Link className="vf-card-link" href="/erp/assets/depreciation">{t("finViewAll")}</Link>}>
          <ul className="erp-list">
            <li className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{data.latest_run ? periodLabel(data.latest_run.period, locale) : t("finNone")}</span><span className="erp-list-sub">{t("finLastRun")}{data.latest_run ? ` · ${amount(data.latest_run.total)}` : ""}</span></span></li>
            <li className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{data.next_period ? periodLabel(data.next_period, locale) : t("finUpToDate")}</span><span className="erp-list-sub">{t("finNextRun")}{data.next_period ? ` · ${amount(data.next_due)}` : ""}</span></span></li>
          </ul>
        </GlassCard>

        <GlassCard title={t("finDisposedThisYear")} pad={false} action={<Link className="vf-card-link" href="/erp/assets/disposals">{t("finViewAll")}</Link>}>
          {data.disposed_this_year.length === 0 ? <EmptyState icon="ph-recycle" title={t("finNoDisposals")} /> : (
            <ul className="erp-list">
              {data.disposed_this_year.map((d) => (
                <li key={d.id}>
                  <Link className="erp-list-row" href={`/erp/assets/register/${d.id}`}>
                    <span className="erp-list-main"><span className="erp-list-title">{d.name}</span><span className="erp-list-sub tnum">{d.tag} · {formatDate(d.disposal_date, locale)}</span></span>
                    <Amount value={d.disposal_gain_loss} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      </div>
    </div>
  );
}
