"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { compactMoney } from "@/lib/format";
import { type Forecast, REASON_LABEL, type WinLoss } from "@/lib/crm-types";
import { ErrorState, GlassCard, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { CrmTabs } from "@/components/crm-ui";

export default function ForecastPage() {
  return <ErpGate module="crm" permission="crm.view"><ForecastView /></ErpGate>;
}

function ForecastView() {
  const { t, locale } = useApp();
  const { config } = useErp();
  const currency = config?.settings.base_currency ?? "TZS";
  const [forecast, setForecast] = useState<Forecast | null>(null);
  const [winLoss, setWinLoss] = useState<WinLoss | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    Promise.all([
      api.get<{ data: Forecast }>("/erp/crm/forecast", { months: 6 }),
      api.get<{ data: WinLoss }>("/erp/crm/win-loss"),
    ]).then(([f, w]) => { setForecast(f.data); setWinLoss(w.data); }).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!forecast || !winLoss) return <LoadingBlock rows={6} />;

  const money = (v: number) => compactMoney(v, currency);
  const monthName = (key: string) => new Date(`${key}-01T00:00:00`).toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { month: "short", year: "numeric" });
  const top = Math.max(1, ...forecast.months.map((m) => Math.max(m.value, m.won)));
  const reasonTop = Math.max(1, ...winLoss.won.map((r) => r.count), ...winLoss.lost.map((r) => r.count));

  return (
    <div className="erp-page">
      <PageHeader title={t("crmNavForecast")} subtitle={t("crmForecastSub")} />
      <CrmTabs />

      <StatPills label={t("crmNavForecast")} items={[
        { label: t("crmTotal"), value: money(forecast.total.value), hint: `${t("crmWeighted")} ${money(forecast.total.weighted)}`, icon: "ph-funnel" },
        { label: t("crmPastDue"), value: money(forecast.past_due.value), hint: `${forecast.past_due.count} ${t("crmDeals").toLowerCase()}`, tone: forecast.past_due.count ? "warn" : "neutral", icon: "ph-alarm" },
        { label: t("crmWinRate"), value: winLoss.win_rate === null ? "-" : `${winLoss.win_rate}%`, hint: t("crmLast12"), tone: "ok", icon: "ph-trophy" },
      ]} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("crmNavForecast")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("crmMonth")}</th><th className="num">{t("crmDeals")}</th><th className="num">{t("crmValue")}</th><th className="num">{t("crmWeighted")}</th><th className="num">{t("crmWonInMonth")}</th><th style={{ width: "30%" }} /></tr></thead>
              <tbody>
                {forecast.months.map((m) => (
                  <tr key={m.month}>
                    <td>{monthName(m.month)}</td>
                    <td className="num">{m.count}</td>
                    <td className="num">{money(m.value)}</td>
                    <td className="num"><strong>{money(m.weighted)}</strong></td>
                    <td className="num">{money(m.won)}</td>
                    <td><span className="erp-hbar-track" style={{ display: "block" }}><span className="erp-hbar-fill" style={{ display: "block", height: "100%", width: `${(m.weighted / top) * 100}%` }} /></span></td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                {([["crmPastDue", forecast.past_due], ["crmLater", forecast.later], ["crmUndated", forecast.undated]] as const).map(([label, b]) => (
                  <tr key={label}><td>{t(label)}</td><td className="num">{b.count}</td><td className="num">{money(b.value)}</td><td className="num">{money(b.weighted)}</td><td /><td /></tr>
                ))}
                <tr><td><strong>{t("crmTotal")}</strong></td><td className="num">{forecast.total.count}</td><td className="num">{money(forecast.total.value)}</td><td className="num"><strong>{money(forecast.total.weighted)}</strong></td><td /><td /></tr>
              </tfoot>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("crmWinLoss")} subtitle={t("crmLast12")}>
          {winLoss.won.length + winLoss.lost.length === 0 ? <p className="erp-muted">{t("crmNoClosed")}</p> : (
            <>
              {([["crmWonReasons", winLoss.won], ["crmLostReasons", winLoss.lost]] as const).map(([label, list]) => list.length > 0 && (
                <div key={label}>
                  <h3 className="erp-subhead">{t(label)}</h3>
                  <ul className="erp-hbars">
                    {list.map((r) => (
                      <li key={r.reason}>
                        <span className="erp-hbar-label">{t(REASON_LABEL[r.reason] ?? "crmReasonOther")}</span>
                        <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(r.count / reasonTop) * 100}%` }} /></span>
                        <span className="erp-hbar-value tnum">{r.count} · {money(r.value)}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </>
          )}
        </GlassCard>
      </div>
    </div>
  );
}
