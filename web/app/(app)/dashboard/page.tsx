"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, money } from "@/lib/format";
import {
  Banner, EmptyState, ErrorState, Icon, StatBlock, StatGrid,
  type Kpi, type Tone,
} from "@/components/ui";
import { VoucherList } from "@/components/voucher-bits";
import type { DashboardPayload, Role } from "@/lib/types";

/**
 * The dashboard is an operations desk, not a history page.
 *
 * It answers one question first — what needs me right now — with that work on
 * the left, at full width, and the context that explains it beside it: where
 * the rest of the work is sitting, how volume is moving, where money is going.
 * The moment someone acts, a voucher moves to whoever is next and leaves this
 * screen; everything already dealt with lives in Reports.
 *
 * What each role sees is decided by the backend (queue, figures, breakdowns);
 * this page decides only how it reads.
 */

type Look = [icon: string, tone: Tone];

/*
 * Icons and tones for each role's figures, by position. The backend sends each
 * role's figures as a fixed, ordered set, so position is stable across
 * languages. Only the number that asks for action is coloured.
 */
const LOOKS: Partial<Record<Role, Look[]>> = {
  employee: [["ph-pencil-simple-line", "info"], ["ph-hourglass-medium", "neutral"], ["ph-check-circle", "ok"], ["ph-receipt", "neutral"]],
  hod: [["ph-signature", "info"], ["ph-check-circle", "ok"], ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"]],
  ceo: [["ph-seal-check", "info"], ["ph-check-circle", "ok"], ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"]],
  director: [["ph-seal-check", "info"], ["ph-check-circle", "ok"], ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"]],
  finance: [["ph-seal-check", "info"], ["ph-check-circle", "ok"], ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"]],
  cashier: [["ph-wallet", "info"], ["ph-bank", "neutral"], ["ph-money", "neutral"], ["ph-check-circle", "ok"]],
  company_admin: [["ph-receipt", "neutral"], ["ph-hourglass-medium", "info"], ["ph-check-circle", "ok"], ["ph-x-circle", "bad"], ["ph-chart-line-up", "neutral"], ["ph-timer", "neutral"]],
  super_admin: [["ph-buildings", "neutral"], ["ph-currency-circle-dollar", "ok"], ["ph-chart-line-up", "neutral"], ["ph-users-three", "neutral"], ["ph-receipt", "neutral"], ["ph-stack", "neutral"]],
};

export default function DashboardPage() {
  const { t, user, company, locale } = useApp();
  const [payload, setPayload] = useState<DashboardPayload | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<DashboardPayload>("/dashboard")
      .then(setPayload)
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load, locale]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!payload) return <DashboardSkeleton />;

  const d = payload.data;
  const queue = payload.queue ?? d.queue ?? [];
  const role = user?.role;
  const isCashier = role === "cashier";
  const isEmployee = role === "employee";
  const isAdmin = role === "company_admin";
  const isPlatform = role === "super_admin";
  const sw = locale === "sw";
  const expiring = company && company.status === "trial" && (company.days_remaining ?? 99) <= 7;

  const queueTitle = isCashier ? t("paymentQueue")
    : isEmployee ? t("actionQueue")
    : isAdmin ? t("stalled")
    : t("needsYourAction");

  const looks = (role && LOOKS[role]) || [];
  const stats: Kpi[] = d.stats.map((stat, index) => ({
    ...stat,
    icon: looks[index]?.[0] ?? "ph-chart-bar",
    tone: looks[index]?.[1] ?? "neutral",
    href: index === 0 && queue.length > 0 && !isPlatform && !isAdmin ? "#queue" : undefined,
  }));

  const firstName = user?.name.split(" ")[0] ?? "";
  const hasContext = Boolean(d.by_stage?.length || d.volume?.length || d.by_department?.length);

  return (
    <div className="app-page app-dashboard">
      {company && !company.is_usable && (
        <Banner tone="danger" icon="ph-warning-circle" title={t("expired")}
          action={<Link className="btn btn-primary btn-sm" href="/subscription">{t("payNow")}</Link>}>
          {t("expiredBody")}
        </Banner>
      )}

      {expiring && company.is_usable && (
        <Banner tone="warn" icon="ph-clock" title={`${t("trialEnds")} ${formatDate(company.trial_ends_at, locale)}`}
          action={<Link className="btn btn-secondary btn-sm" href="/subscription">{t("changePlan")}</Link>}>
          {company.days_remaining} days remaining on your {company.plan?.name} trial.
        </Banner>
      )}

      <header className="vf-pagehead app-dash-head">
        <div className="vf-pagehead-main">
          <p className="app-dash-hello">{payload.greeting}, {firstName}</p>
          <h1 className="vf-pagehead-title">{d.headline}</h1>
          {d.sub && <p className="vf-pagehead-sub">{d.sub}</p>}
        </div>
        <div className="vf-pagehead-actions">
          {isPlatform ? (
            <Link className="btn btn-primary" href="/platform/companies"><Icon name="ph-buildings" size={16} /> {t("companies")}</Link>
          ) : (
            <>
              <Link className="btn btn-secondary" href="/reports"><Icon name="ph-chart-line" size={16} /> {t("reports")}</Link>
              {!isCashier && <Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus" size={16} /> {t("createVoucher")}</Link>}
            </>
          )}
        </div>
      </header>

      <section className="app-section" aria-label={sw ? "Takwimu" : "Key figures"}>
        <StatGrid>
          {stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
        </StatGrid>
      </section>

      <div className={`app-dash-grid${hasContext || isPlatform ? "" : " is-single"}`}>
        {/* ── the work ── */}
        <div className="app-dash-main">
          {!isPlatform && (
            <section className="vf-panel" id="queue" aria-labelledby="queue-title">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main app-panel-title">
                  <h2 id="queue-title">{queueTitle}</h2>
                  <span className="vf-count">{queue.length}</span>
                </div>
                {payload.queue_total_text && queue.length > 0 && (
                  <div className="app-queue-total">{t("total")} <strong className="tnum">{payload.queue_total_text}</strong></div>
                )}
              </div>
              {queue.length > 0 ? (
                <>
                  <VoucherList vouchers={queue} bare />
                  <div className="app-panel-foot">
                    <Icon name="ph-info" size={15} />
                    <span>{isAdmin ? t("stalledNote") : t("clearedNote")}</span>
                  </div>
                </>
              ) : (
                <EmptyState
                  tone="ok" icon="ph-check-circle" title={t("nothingOnYou")} body={t("historyInReports")}
                  action={
                    <>
                      <Link className="btn btn-secondary" href="/reports"><Icon name="ph-chart-line" size={16} /> {t("reports")}</Link>
                      {!isCashier && <Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus" size={16} /> {t("createVoucher")}</Link>}
                    </>
                  }
                />
              )}
            </section>
          )}

          {/* The platform's own queue: companies that need a conversation. */}
          {d.attention && (
            <section className="vf-panel" aria-labelledby="attention-title">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main app-panel-title">
                  <h2 id="attention-title">{t("companiesNeedingAttention")}</h2>
                  <span className="vf-count">{d.attention.length}</span>
                </div>
                <Link className="btn btn-ghost btn-sm" href="/platform/companies">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link>
              </div>
              {d.attention.length === 0 ? (
                <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingOnYou")} body={t("historyInReports")} />
              ) : (
                <div className="vf-list">
                  {d.attention.map((row) => (
                    <Link key={row.id} href={`/platform/companies/${row.id}`} className="vf-row">
                      <div className="vf-row-main">
                        <div className="vf-row-top">
                          <span className={`badge ${row.status === "trial" ? "tone-info" : "tone-bad"}`}>{row.status}</span>
                          {row.plan && <span className="vf-kind">{row.plan}</span>}
                        </div>
                        <div className="vf-row-title">{row.name}</div>
                        <div className="vf-row-meta">{row.note}</div>
                      </div>
                      <div className="vf-row-side">
                        <div className="vf-row-meta">{row.users_count} {t("users").toLowerCase()}</div>
                        <Icon name="ph-caret-right" size={15} style={{ color: "var(--text-faint)" }} />
                      </div>
                    </Link>
                  ))}
                </div>
              )}
            </section>
          )}

          {isPlatform && d.recent_payments && d.recent_payments.length > 0 && (
            <section className="vf-panel" aria-labelledby="payments-title">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main"><h2 id="payments-title">{t("recentPayments")}</h2></div>
                <Link className="btn btn-ghost btn-sm" href="/platform/payments">{t("all")} <Icon name="ph-arrow-right" size={13} /></Link>
              </div>
              <div className="table-wrap">
                <table className="table">
                  <thead><tr><th>{sw ? "Ankara" : "Invoice"}</th><th>{t("companies")}</th><th className="num">{t("amount")}</th><th>{t("status")}</th><th>{t("date")}</th></tr></thead>
                  <tbody>
                    {d.recent_payments.map((p) => (
                      <tr key={p.id}>
                        <td className="tnum">{p.number}</td>
                        <td>{p.company ?? "—"}</td>
                        <td className="num">{money(p.total, p.currency)}</td>
                        <td><span className={`badge ${p.status === "paid" ? "tone-ok" : p.status === "pending" ? "tone-warn" : "tone-neutral"}`}>{p.status}</span></td>
                        <td className="text-muted">{formatDate(p.created_at, locale)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}
        </div>

        {/* ── the context ── */}
        {(hasContext || isPlatform) && (
          <aside className="app-dash-aside">
            {d.by_stage && d.by_stage.length > 0 && (
              <section className="vf-panel">
                <div className="vf-panel-head"><div className="vf-panel-head-main"><h2>{t("byStage")}</h2></div></div>
                <div className="vf-panel-pad app-bars">
                  {d.by_stage.map((row) => (
                    <div key={row.name} className="app-bar-row">
                      <div className="app-bar-top">
                        <span className="app-bar-name">{row.name}</span>
                        <span className="app-bar-count tnum">{row.count}</span>
                        <span className="app-bar-value tnum">{compactMoney(row.total, company?.currency)}</span>
                      </div>
                      <div className="vf-meter"><span style={{ width: row.share }} /></div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {d.volume && d.volume.length > 0 && <VolumeChart volume={d.volume} currency={company?.currency} />}

            {d.by_department && d.by_department.length > 0 && (
              <section className="vf-panel">
                <div className="vf-panel-head">
                  <div className="vf-panel-head-main">
                    <h2>{t("spendByDept")}</h2>
                    <div className="vf-panel-sub">{sw ? "Vocha zilizoidhinishwa" : "Approved vouchers"}</div>
                  </div>
                </div>
                <div className="vf-panel-pad app-bars">
                  {d.by_department.slice(0, 6).map((row) => (
                    <div key={row.id} className="app-bar-row">
                      <div className="app-bar-top">
                        <span className="app-bar-name">{row.name}</span>
                        <span className="app-bar-count tnum">{row.count}</span>
                        <span className="app-bar-value tnum">{compactMoney(row.total, company?.currency)}</span>
                      </div>
                      <div className="vf-meter"><span style={{ width: row.share }} /></div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {isPlatform && d.recent_companies && d.recent_companies.length > 0 && (
              <section className="vf-panel">
                <div className="vf-panel-head"><div className="vf-panel-head-main"><h2>{t("recentCompanies")}</h2></div></div>
                <ul className="app-mini-list">
                  {d.recent_companies.map((c) => (
                    <li key={c.id}>
                      <Link href={`/platform/companies/${c.id}`}>
                        <span className="app-mini-title">{c.name}</span>
                        <span className="app-mini-meta">{[c.plan, `${c.users_count} ${t("users").toLowerCase()}`, `${c.vouchers_count} ${t("vouchers").toLowerCase()}`].filter(Boolean).join(" · ")}</span>
                      </Link>
                      <span className={`badge ${c.status === "active" ? "tone-ok" : c.status === "trial" ? "tone-info" : "tone-bad"}`}>{c.status}</span>
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </aside>
        )}
      </div>
    </div>
  );
}

/** Seven months of voucher value as quiet single-colour columns; the current month is emphasised. */
function VolumeChart({ volume, currency }: { volume: NonNullable<DashboardPayload["data"]["volume"]>; currency?: string }) {
  const { locale } = useApp();
  const max = Math.max(1, ...volume.map((v) => v.total));
  const current = volume.find((v) => v.is_current);

  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main">
          <h2>{locale === "sw" ? "Thamani ya vocha" : "Voucher value"}</h2>
          <div className="vf-panel-sub">{locale === "sw" ? "Miezi 7 iliyopita" : "Last 7 months"}</div>
        </div>
        {current && <div className="app-chart-now tnum">{compactMoney(current.total, currency)}</div>}
      </div>
      <div className="vf-panel-pad">
        <div className="app-columns" role="img" aria-label={volume.map((v) => `${v.label}: ${money(v.total, currency)}`).join(", ")}>
          {volume.map((v) => (
            <div key={v.period} className="app-column" data-current={v.is_current || undefined} title={`${v.label} · ${v.count} · ${money(v.total, currency)}`}>
              <span className="app-column-bar" style={{ height: `${Math.max(3, (v.total / max) * 100)}%` }} />
              <span className="app-column-label">{v.label}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/** The shape of the dashboard, so the page does not jump when data arrives. */
function DashboardSkeleton() {
  return (
    <div className="app-page app-dashboard" aria-busy="true">
      <span className="sr-only">Loading</span>
      <div style={{ display: "grid", gap: 8, marginBottom: 22 }}>
        <div className="skeleton" style={{ height: 14, width: 160 }} />
        <div className="skeleton" style={{ height: 26, width: "min(420px, 80%)" }} />
        <div className="skeleton" style={{ height: 14, width: "min(320px, 60%)" }} />
      </div>
      <div className="skeleton" style={{ height: 88, marginBottom: 20 }} />
      <div className="app-dash-grid">
        <div className="skeleton" style={{ height: 320 }} />
        <div className="skeleton" style={{ height: 320 }} />
      </div>
    </div>
  );
}
