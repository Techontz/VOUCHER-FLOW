"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, money, relativeTime } from "@/lib/format";
import {
  COMPANY_STATUS, MODULE_LOOK, change, fill, initialsOf, monthLabel, type PlatformAnalytics,
} from "@/lib/platform";
import { Badge, Dialog, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { AreaChart, BarChart, DonutChart, HBarList, type SeriesTone } from "@/components/charts";
import type { MessageKey } from "@/lib/i18n";

/*
 * The platform operator's landing: how the business is doing (revenue,
 * growth, churn), where every company stands, what the platform is used for,
 * and the queue of things that need the operator: approvals and renewals.
 * Every figure comes from GET /platform/analytics.
 */

const STATUS_TONE: Record<string, SeriesTone> = {
  active: "ok", trial: "info", pending: "warn", past_due: "s4", suspended: "bad", expired: "s5", cancelled: "muted",
};

const ROLE_KEY: Record<string, MessageKey> = {
  company_admin: "pfRoleCompanyAdmin", employee: "pfRoleEmployee", hod: "pfRoleHod", manager: "pfRoleManager",
  ceo: "pfRoleCeo", cashier: "pfRoleCashier", finance: "pfRoleFinance", director: "pfRoleDirector",
};

export function PlatformOverview() {
  const { t, locale, user, toast, reportError } = useApp();
  const [data, setData] = useState<PlatformAnalytics | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [measure, setMeasure] = useState<"revenue" | "mrr">("revenue");
  const [approving, setApproving] = useState<PlatformAnalytics["pending"][number] | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    api.get<{ data: PlatformAnalytics }>("/platform/analytics")
      .then((r) => { setError(null); setData(r.data); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  async function approve() {
    if (!approving) return;
    setBusy(true);
    try {
      await api.post(`/platform/companies/${approving.id}/approve`);
      toast(t("companyApproved"), approving.name, "ok");
      setApproving(null);
      load();
    } catch (err) {
      reportError(err, t("approveCompanyFailed"));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!data) return <LoadingBlock rows={8} />;

  const k = data.kpis;
  const cur = data.currency;
  const cash = (v: number) => money(Math.round(v), cur);
  const short = (v: number) => compactMoney(v, "").trim();
  const revTrend = change(k.revenue_this_month, k.revenue_last_month);
  const series = measure === "revenue" ? data.revenue_by_month : data.mrr_by_month;
  const hour = new Date().getHours();
  const greeting = t(hour < 12 ? "erpGreetingMorning" : hour < 17 ? "erpGreetingAfternoon" : "erpGreetingEvening");
  const firstName = user?.name.split(" ")[0] ?? "";
  const statusSlices = Object.entries(data.companies_by_status)
    .filter(([, n]) => n > 0)
    .map(([key, value]) => ({ key, label: t(COMPANY_STATUS[key]?.label ?? "status"), value, tone: STATUS_TONE[key] ?? "muted" }));
  const roleRows = Object.entries(data.users_by_role).slice(0, 7);

  return (
    <div className="app-page pf-page pf-rise">
      <PageHeader
        kicker={t("pfPlatform")}
        title={`${greeting}${firstName ? `, ${firstName}` : ""}`}
        subtitle={fill(t("pfOverviewSub"), { companies: k.companies, users: k.users.toLocaleString("en-US") })}
        actions={<>
          <Link className="btn btn-secondary" href="/platform/subscriptions"><Icon name="ph-arrows-clockwise" size={16} /> {t("pfSubscriptions")}</Link>
          <Link className="btn btn-primary" href="/platform/companies"><Icon name="ph-buildings" size={16} /> {t("companies")}</Link>
        </>}
      />

      <StatPills label={t("pfKeyFigures")} items={[
        { label: t("pfMrr"), value: compactMoney(k.mrr, cur), hint: fill(t("pfArrHint"), { arr: compactMoney(k.arr, cur) }), icon: "ph-currency-circle-dollar", tone: "ok" },
        {
          label: t("pfRevenueThisMonth"), value: compactMoney(k.revenue_this_month, cur), icon: "ph-chart-line-up",
          trend: revTrend === null ? null : `${revTrend > 0 ? "+" : ""}${revTrend}%`, up: revTrend !== null && revTrend >= 0, hint: t("pfVsLastMonth"),
        },
        { label: t("companies"), value: k.companies, hint: fill(t("pfCompaniesHint"), { paying: k.paying_companies, trial: k.trial_companies }), icon: "ph-buildings", href: "/platform/companies" },
        { label: t("pfActiveUsers"), value: k.active_users, hint: fill(t("pfActive30Hint"), { n: k.active_users_30d.toLocaleString("en-US") }), icon: "ph-users-three", href: "/platform/users" },
        { label: t("pfVouchersThisMonth"), value: k.vouchers_this_month, hint: fill(t("pfVouchersHint"), { n: k.vouchers.toLocaleString("en-US") }), icon: "ph-receipt", tone: "info" },
        {
          label: t("pfApprovals"), value: k.pending_approvals, hint: k.pending_approvals ? t("pfWaitingForYou") : t("pfAllClear"),
          icon: "ph-hourglass-medium", tone: k.pending_approvals ? "warn" : "neutral", href: k.pending_approvals ? "#approvals" : undefined,
        },
      ]} />

      <div className="pf-grid-wide">
        <GlassCard title={t("pfRevenue")} subtitle={t("pfLast12Months")}
          action={
            <div className="pf-seg" role="group" aria-label={t("pfMeasure")}>
              <button type="button" aria-pressed={measure === "revenue"} onClick={() => setMeasure("revenue")}>{t("pfCollected")}</button>
              <button type="button" aria-pressed={measure === "mrr"} onClick={() => setMeasure("mrr")}>{t("pfMrrShort")}</button>
            </div>
          }>
          <div className="pf-hero">
            <div className="pf-hero-figure">
              <span>{measure === "revenue" ? t("pfCollected12") : t("pfMrrNow")}</span>
              <strong className="tnum">{measure === "revenue" ? cash(k.revenue_12m) : cash(k.mrr)}</strong>
            </div>
            <div className="pf-hero-figure">
              <span>{t("pfArr")}</span>
              <strong className="tnum">{compactMoney(k.arr, cur)}</strong>
            </div>
            <div className="pf-hero-figure">
              <span>{fill(t("pfChurn"), { days: data.churn.period_days })}</span>
              <strong className="tnum">{data.churn.rate}%<small>{fill(t("pfChurnCount"), { n: data.churn.count })}</small></strong>
            </div>
          </div>
          <AreaChart key={measure} label={measure === "revenue" ? t("pfRevenueByMonth") : t("pfMrrByMonth")}
            valueLabel={measure === "revenue" ? t("pfCollected") : t("pfMrrShort")}
            data={series.map((p) => ({ label: monthLabel(p.month, locale, true), value: p.value }))}
            format={short} tone={measure === "revenue" ? "s1" : "s3"} />
        </GlassCard>

        <GlassCard title={t("pfCompaniesByStatus")} subtitle={fill(t("pfOfTotal"), { n: k.companies })}
          action={<Link className="vf-card-link" href="/platform/companies">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link>}>
          {statusSlices.length === 0
            ? <EmptyState icon="ph-buildings" title={t("pfNoCompanies")} />
            : <DonutChart slices={statusSlices} label={t("pfCompaniesByStatus")} centerLabel={t("companies")} otherLabel={t("pfOther")} />}
        </GlassCard>
      </div>

      <div className="pf-grid-3">
        <GlassCard title={t("pfSignups")} subtitle={t("pfSignupsSub")}>
          <BarChart label={t("pfSignups")}
            labels={data.signups_by_month.map((p) => monthLabel(p.month, locale))}
            series={[{ name: t("pfNewCompanies"), values: data.signups_by_month.map((p) => p.value), tone: "s7" }]}
            format={(v) => String(Math.round(v))} height={180} />
        </GlassCard>

        <GlassCard title={t("pfCompaniesByPlan")} subtitle={t("pfCompaniesByPlanSub")}
          action={<Link className="vf-card-link" href="/platform/plans">{t("pfPlans")} <Icon name="ph-arrow-right" size={13} /></Link>}>
          {data.companies_by_plan.length === 0
            ? <EmptyState icon="ph-crown-simple" title={t("pfNoCompanies")} />
            : <DonutChart label={t("pfCompaniesByPlan")} centerLabel={t("companies")} otherLabel={t("pfOther")}
                slices={data.companies_by_plan.map((p) => ({
                  key: String(p.plan_id ?? "none"), label: p.plan_id === null ? t("pfNoPlan") : p.name, value: p.count,
                }))} />}
        </GlassCard>

        <GlassCard title={t("pfModuleAdoption")} subtitle={t("pfModuleAdoptionSub")}>
          <HBarList label={t("pfModuleAdoption")} tone="s3"
            rows={data.module_adoption.map((m) => ({
              key: m.key,
              label: MODULE_LOOK[m.key] ? t(MODULE_LOOK[m.key].label) : m.label,
              value: m.count,
              max: Math.max(1, k.companies),
              display: `${m.count} · ${m.percent}%`,
              note: m.live ? undefined : t("pfComingSoon"),
            }))} />
        </GlassCard>
      </div>

      <div className="pf-grid-wide">
        <GlassCard title={t("pfVoucherVolume")} subtitle={fill(t("pfVoucherVolumeSub"), { value: compactMoney(k.vouchers_value, cur) })}>
          <BarChart label={t("pfVoucherVolume")}
            labels={data.vouchers_by_month.map((p) => monthLabel(p.month, locale))}
            series={[
              { name: t("pfCreated"), values: data.vouchers_by_month.map((p) => p.created), tone: "s1" },
              { name: t("pfPaid"), values: data.vouchers_by_month.map((p) => p.paid), tone: "s3" },
            ]}
            format={(v) => String(Math.round(v))} height={200} />
        </GlassCard>

        <GlassCard title={t("pfUsersByRole")} subtitle={fill(t("pfUsersByRoleSub"), { n: k.users.toLocaleString("en-US") })}
          action={<Link className="vf-card-link" href="/platform/users">{t("users")} <Icon name="ph-arrow-right" size={13} /></Link>}>
          {roleRows.length === 0 ? <EmptyState icon="ph-users-three" title={t("noResults")} /> : (
            <HBarList label={t("pfUsersByRole")} tone="s7"
              rows={roleRows.map(([role, n]) => ({
                key: role, label: ROLE_KEY[role] ? t(ROLE_KEY[role]) : role.replace(/_/g, " "), value: n,
              }))} />
          )}
        </GlassCard>
      </div>

      <GlassCard id="approvals" title={t("pfPendingApprovals")} subtitle={t("pfPendingApprovalsSub")} pad={false}
        action={k.pending_approvals > 0 ? <Link className="vf-card-link" href="/platform/companies?status=pending">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link> : undefined}>
        {data.pending.length === 0 ? (
          <EmptyState icon="ph-check-circle" tone="ok" title={t("pfNoPending")} body={t("pfNoPendingBody")} />
        ) : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("companyName")}</th><th>{t("plan")}</th><th className="num">{t("users")}</th><th>{t("pfRegistered")}</th><th><span className="sr-only">{t("actions")}</span></th></tr></thead>
              <tbody>
                {data.pending.map((c) => (
                  <tr key={c.id}>
                    <td><Link className="pf-link" href={`/platform/companies/${c.id}`}>{c.name}</Link><span className="pf-cell-sub">{c.email}</span></td>
                    <td>{c.plan ?? "-"}</td>
                    <td className="num">{c.users_count}</td>
                    <td className="pf-nowrap">{relativeTime(c.created_at, locale)}</td>
                    <td className="app-row-actions">
                      <button type="button" className="btn btn-primary btn-sm" onClick={() => setApproving(c)}>
                        <Icon name="ph-check-circle" size={15} /> {t("approve")}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      <GlassCard title={t("pfExpiring")} subtitle={t("pfExpiringSub")} pad={false}
        action={<Link className="vf-card-link" href="/platform/subscriptions?expiring=30">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link>}>
        {data.expiring.length === 0 ? (
          <EmptyState icon="ph-calendar-check" tone="ok" title={t("pfNoExpiring")} />
        ) : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("companyName")}</th><th>{t("plan")}</th><th>{t("status")}</th><th className="num">{t("pfAmount")}</th><th>{t("pfEnds")}</th><th className="num">{t("pfDaysLeft")}</th></tr></thead>
              <tbody>
                {data.expiring.map((s) => (
                  <tr key={s.id}>
                    <td><Link className="pf-link" href={`/platform/companies/${s.company_id}#subscription`}>{s.company ?? "-"}</Link></td>
                    <td>{s.plan ?? "-"}</td>
                    <td>
                      <Badge tone={s.status === "trialing" ? "info" : "ok"} dot>{t(s.status === "trialing" ? "pfStatusTrial" : "pfStatusActive")}</Badge>
                      {s.cancel_at_period_end && <> <Badge tone="warn">{t("pfEndsAtPeriodEnd")}</Badge></>}
                    </td>
                    <td className="num pf-nowrap">{money(s.amount, s.currency)}</td>
                    <td className="pf-nowrap">{formatDate(s.ends_at, locale)}</td>
                    <td className="num"><span className="pf-days" data-tone={s.days_left <= 3 ? "bad" : s.days_left <= 7 ? "warn" : undefined}>{s.days_left}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      <div className="pf-grid-2">
        <GlassCard title={t("pfRecentSignups")} pad={false}
          action={<Link className="vf-card-link" href="/platform/companies?sort=newest">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link>}>
          {data.recent_signups.length === 0 ? <EmptyState icon="ph-buildings" title={t("pfNoCompanies")} /> : (
            <ul className="pf-rows">
              {data.recent_signups.map((c) => {
                const st = COMPANY_STATUS[c.status];
                return (
                  <li key={c.id}>
                    <span className="pf-mark" aria-hidden="true">{initialsOf(c.name)}</span>
                    <span className="pf-row-main">
                      <Link href={`/platform/companies/${c.id}`}>{c.name}</Link>
                      <span>{[c.plan, fill(t("pfUsersCount"), { n: c.users_count }), relativeTime(c.created_at, locale)].filter(Boolean).join(" · ")}</span>
                    </span>
                    <span className="pf-row-end"><Badge tone={st?.tone ?? "neutral"} dot>{st ? t(st.label) : c.status}</Badge></span>
                  </li>
                );
              })}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("pfTopCompanies")} subtitle={t("pfTopCompaniesSub")} pad={false}>
          {data.top_companies.length === 0 ? <EmptyState icon="ph-receipt" title={t("pfNoVouchers")} /> : (
            <ul className="pf-rows">
              {data.top_companies.map((c, i) => (
                <li key={c.id}>
                  <span className="pf-rank">{i + 1}</span>
                  <span className="pf-row-main">
                    <Link href={`/platform/companies/${c.id}`}>{c.name}</Link>
                    <span>{c.plan ?? t("pfNoPlan")}</span>
                  </span>
                  <span className="pf-row-end">
                    <span className="pf-row-main">
                      <strong className="tnum">{fill(t("pfVouchersCount"), { n: c.vouchers.toLocaleString("en-US") })}</strong>
                      <span className="tnum">{compactMoney(c.value, c.currency)}</span>
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      </div>

      <Dialog open={approving !== null} busy={busy} onClose={() => setApproving(null)} icon="ph-check-circle" tone="ok"
        title={approving ? t("approveCompanyQ").replace("{name}", approving.name) : ""}
        sub={t("approveCompanySub")}
        summary={approving ? [
          { label: t("companyName"), value: approving.name },
          { label: t("email"), value: approving.email },
          { label: t("plan"), value: approving.plan ?? "-" },
        ] : undefined}
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setApproving(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className="btn btn-primary" onClick={() => void approve()} disabled={busy}>
            <Icon name="ph-check-circle" size={16} /> {t("approve")}
          </button>
        </>} />
    </div>
  );
}
