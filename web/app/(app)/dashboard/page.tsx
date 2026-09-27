"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, money, relativeTime } from "@/lib/format";
import { translateKey, type Locale } from "@/lib/i18n";
import {
  Banner, ErrorState, Icon, StatBlock, StatGrid,
  type Kpi, type Tone,
} from "@/components/ui";
import { VoucherList } from "@/components/voucher-bits";
import type { DashboardActivity, DashboardPayload, DashboardView, Role } from "@/lib/types";

/**
 * The dashboard: a greeting, one plain sentence about what is waiting on you,
 * the figures for your role, and the work itself.
 *
 * What each role sees — and every number on it — is decided by the backend
 * from the vouchers that user may see. This page decides only how it reads,
 * and translates each figure by its stable key, falling back to the English
 * text the API sent.
 */

type Look = [icon: string, tone: Tone];

/*
 * Icon and tone per figure, by the figure's stable key — so a figure keeps its
 * look whichever role's dashboard it appears on. Only the numbers that ask
 * for action are coloured.
 */
const LOOKS: Record<string, Look> = {
  "dash.stat.myVouchers": ["ph-receipt", "neutral"],
  "dash.stat.pending": ["ph-hourglass-medium", "info"],
  "dash.stat.approved": ["ph-seal-check", "ok"],
  "dash.stat.rejected": ["ph-x-circle", "bad"],
  "dash.stat.paidVouchers": ["ph-check-circle", "ok"],
  "dash.stat.amountRaised": ["ph-coins", "neutral"],
  "dash.stat.awaitingSignature": ["ph-signature", "info"],
  "dash.stat.signedThisMonth": ["ph-pen-nib", "ok"],
  "dash.stat.deptVouchersThisMonth": ["ph-files", "neutral"],
  "dash.stat.deptValue": ["ph-coins", "neutral"],
  "dash.stat.deptExpenses": ["ph-buildings", "neutral"],
  "dash.stat.awaitingApproval": ["ph-seal-check", "info"],
  "dash.stat.approvedThisMonth": ["ph-check-circle", "ok"],
  "dash.stat.rejectedThisMonth": ["ph-x-circle", "bad"],
  "dash.stat.totalValue": ["ph-coins", "neutral"],
  "dash.stat.awaitingPayment": ["ph-wallet", "info"],
  "dash.stat.pendingPayments": ["ph-bank", "neutral"],
  "dash.stat.paidThisMonth": ["ph-money", "ok"],
  "dash.stat.activeUsers": ["ph-users-three", "neutral"],
  "dash.stat.submittedVouchers": ["ph-receipt", "neutral"],
  "dash.stat.inWorkflow": ["ph-arrows-clockwise", "info"],
  "dash.stat.approvedIncludingPaid": ["ph-seal-check", "ok"],
  "dash.stat.valueThisMonth": ["ph-chart-line-up", "neutral"],
  "dash.stat.avgApprovalTime": ["ph-timer", "neutral"],
  "dash.stat.totalCompanies": ["ph-buildings", "neutral"],
  "dash.stat.monthlyRevenue": ["ph-currency-circle-dollar", "ok"],
  "dash.stat.trailingRevenue": ["ph-chart-line-up", "neutral"],
  "dash.stat.totalUsers": ["ph-users-three", "neutral"],
  "dash.stat.totalVouchers": ["ph-receipt", "neutral"],
  "dash.stat.pendingApprovedRejected": ["ph-stack", "neutral"],
  "dash.stat.needsAttention": ["ph-warning-circle", "warn"],
  "dash.stat.outstanding": ["ph-receipt", "neutral"],
};

/** The dashboard a role gets when an older payload carries no `view`. */
const VIEW_BY_ROLE: Partial<Record<Role, DashboardView>> = {
  employee: "employee", hod: "hod", manager: "approver", ceo: "approver", director: "approver",
  finance: "approver", cashier: "cashier", company_admin: "admin", super_admin: "platform",
} as Partial<Record<Role, DashboardView>>;

const STEP_ICON: Record<string, string> = {
  request: "ph-file-plus", sign: "ph-signature", approve: "ph-seal-check", pay: "ph-wallet", review: "ph-eye",
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
  const tr = (key: string | null | undefined, fallback: string, params?: Record<string, string | number> | null) =>
    translateKey(key, locale, fallback, params);

  const queue = payload.queue ?? d.queue ?? [];
  const queueTotal = payload.queue_total_text ?? d.queue_total_text;
  const view: DashboardView = d.view ?? (user?.role && VIEW_BY_ROLE[user.role]) ?? "employee";
  const isPlatform = view === "platform";
  const canCreate = !isPlatform && view !== "cashier";
  const expiring = company && company.status === "trial" && (company.days_remaining ?? 99) <= 7;

  const stats: Array<{ id: string; kpi: Kpi }> = d.stats.map((stat, index) => {
    const look: Look = (stat.key && LOOKS[stat.key]) || ["ph-chart-bar", "neutral"];
    const actionable = look[1] === "info" && Number(stat.value) > 0 && queue.length > 0 && !isPlatform;
    return {
      id: `${stat.key ?? stat.label}-${index}`,
      kpi: {
        label: tr(stat.key, stat.label, stat.params),
        value: stat.value,
        sub: stat.sub_key ? tr(stat.sub_key, stat.sub, stat.sub_params) : stat.sub,
        trend: stat.trend,
        up: stat.up,
        icon: look[0],
        tone: look[1],
        href: actionable ? "#queue" : undefined,
      },
    };
  });

  const firstName = user?.name.split(" ")[0] ?? "";
  const greeting = tr(`greeting.${payload.greeting}`, payload.greeting);

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
          {tr("dash.trialBanner", `${company.days_remaining} days remaining on your ${company.plan?.name ?? ""} trial.`,
            { days: company.days_remaining ?? 0, plan: company.plan?.name ?? "" })}
        </Banner>
      )}

      <header className="vf-pagehead app-dash-head">
        <div className="vf-pagehead-main">
          <h1 className="vf-pagehead-title">{greeting}{firstName ? `, ${firstName}` : ""}</h1>
          <p className="vf-pagehead-sub">
            {isPlatform ? tr("dash.introPlatform", "Here's the platform at a glance.") : tr("dash.intro", "Here's your voucher activity at a glance.")}
          </p>
        </div>
        <div className="vf-pagehead-actions">
          {isPlatform ? (
            <Link className="btn btn-primary" href="/platform/companies"><Icon name="ph-buildings" size={16} /> {t("companies")}</Link>
          ) : (
            <>
              <Link className="btn btn-secondary" href="/reports"><Icon name="ph-chart-line" size={16} /> {t("reports")}</Link>
              {canCreate && <Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus" size={16} /> {t("createVoucher")}</Link>}
            </>
          )}
        </div>
      </header>

      {/* One sentence about what is waiting on you — and where to go. */}
      {d.banner ? (
        <AttentionBanner banner={d.banner} tr={tr} />
      ) : isPlatform && (
        <div className="app-attn" data-tone="neutral">
          <span className="app-attn-icon"><Icon name="ph-globe-hemisphere-east" size={20} /></span>
          <div className="app-attn-text">
            <div className="app-attn-title">{d.headline}</div>
            {d.sub && <div className="app-attn-body">{d.sub}</div>}
          </div>
        </div>
      )}

      <section className="app-section app-dash-figures" data-count={stats.length} aria-label={tr("dash.keyFigures", "Key figures")}>
        <StatGrid>
          {stats.map((stat) => <StatBlock key={stat.id} {...stat.kpi} />)}
        </StatGrid>
      </section>

      <div className="app-dash-grid">
        {/* ── the work, then what has happened ── */}
        <div className="app-dash-main">
          {!isPlatform && queue.length > 0 && (
            <section className="vf-panel" id="queue" aria-labelledby="queue-title">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main app-panel-title">
                  <h2 id="queue-title">{tr(`dash.queue.${view}`, t("needsYourAction"))}</h2>
                  <span className="vf-count">{queue.length}</span>
                </div>
                {view === "approver" && queue.length > 1 && (
                  <Link className="btn btn-ghost btn-sm" href="/approvals"><Icon name="ph-checks" size={14} /> {t("approveSelected")}…</Link>
                )}
                {queueTotal && (
                  <div className="app-queue-total">{t("total")} <strong className="tnum">{queueTotal}</strong></div>
                )}
              </div>
              <VoucherList vouchers={queue} bare />
              <div className="app-panel-foot">
                <Icon name="ph-info" size={15} />
                <span>{view === "admin" ? t("stalledNote") : t("clearedNote")}</span>
              </div>
            </section>
          )}

          {!isPlatform && d.recent_activity && (
            <ActivityPanel
              title={tr(d.recent_activity_key, d.recent_activity_label ?? "Recent activity")}
              rows={d.recent_activity}
              selfId={user?.id}
              locale={locale}
              tr={tr}
              link={view === "employee"
                ? { href: "/vouchers", label: tr("dash.panel.voucherHistory", "View voucher history") }
                : { href: "/reports", label: tr("dash.panel.viewReports", "View reports") }}
            />
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
                <p className="app-dash-empty">{tr("dash.banner.clear", "Nothing needs your attention.")}</p>
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
                  <thead><tr><th>{locale === "sw" ? "Ankara" : "Invoice"}</th><th>{t("companies")}</th><th className="num">{t("amount")}</th><th>{t("status")}</th><th>{t("date")}</th></tr></thead>
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

        {/* ── the context for this role ── */}
        <aside className="app-dash-aside">
          {view === "admin" && (d.overview || d.workflow !== undefined || d.subscription) && (
            <>
              {d.overview && (
                <section className="vf-panel">
                  <div className="vf-panel-head"><div className="vf-panel-head-main"><h2>{tr("dash.panel.companyOverview", "Company overview")}</h2></div></div>
                  <dl className="app-dash-facts">
                    <div><dt>{tr("dash.panel.activeUsers", "Active users")}</dt><dd className="tnum">{d.overview.active_users}</dd></div>
                    <div><dt>{tr("dash.panel.departments", "Departments")}</dt><dd className="tnum">{d.overview.departments}</dd></div>
                  </dl>
                </section>
              )}
              <WorkflowCard workflow={d.workflow ?? null} locale={locale} tr={tr} />
              {d.subscription && (
                <section className="vf-panel">
                  <div className="vf-panel-head">
                    <div className="vf-panel-head-main"><h2>{tr("dash.panel.subscription", "Subscription")}</h2></div>
                    <Link className="btn btn-ghost btn-sm" href="/subscription">{tr("dash.panel.manageSubscription", "Manage subscription")} <Icon name="ph-arrow-right" size={13} /></Link>
                  </div>
                  <dl className="app-dash-facts">
                    <div><dt>{tr("dash.panel.plan", "Plan")}</dt><dd>{d.subscription.plan ?? "—"}</dd></div>
                    <div><dt>{tr("dash.panel.status", "Status")}</dt><dd>{tr(`subscription.${d.subscription.status}`, d.subscription.status)}</dd></div>
                    {d.subscription.status === "trial" ? (
                      <div><dt>{tr("dash.panel.trialEnds", "Trial ends")}</dt><dd>{formatDate(d.subscription.trial_ends_at, locale)}</dd></div>
                    ) : (
                      <div><dt>{tr("dash.panel.renews", "Renews")}</dt><dd>{formatDate(d.subscription.renews_at, locale)}</dd></div>
                    )}
                    {d.subscription.days_remaining !== null && (
                      <div><dt />
                        <dd className="text-muted">{tr("dash.panel.daysLeft", `${d.subscription.days_remaining} days remaining`, { days: d.subscription.days_remaining })}</dd>
                      </div>
                    )}
                  </dl>
                </section>
              )}
            </>
          )}

          {view === "hod" && d.recently_signed && (
            <section className="vf-panel">
              <div className="vf-panel-head"><div className="vf-panel-head-main"><h2>{tr("dash.panel.recentlySigned", "Recently signed")}</h2></div></div>
              {d.recently_signed.length === 0 ? (
                <p className="app-dash-empty">{tr("dash.activity.empty", "No activity yet.")}</p>
              ) : (
                <ul className="app-mini-list">
                  {d.recently_signed.map((v) => (
                    <li key={v.id}>
                      <Link href={`/vouchers/${v.id}`}>
                        <span className="app-mini-title tnum">{v.number}</span>
                        <span className="app-mini-meta">{v.payee}</span>
                      </Link>
                      <span className="tnum app-mini-amount">{v.amount_text}</span>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}

          {view === "cashier" && d.payment_totals && (
            <section className="vf-panel">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main">
                  <h2>{tr("dash.panel.paymentTotals", "Payment totals")}</h2>
                  <div className="vf-panel-sub">{tr("dash.panel.paymentTotalsSub", "Paid this month")}</div>
                </div>
              </div>
              <dl className="app-dash-facts">
                {([
                  ["paid", "dash.panel.paidTotal", "All payments"],
                  ["bank", "dash.panel.bank", "Bank transfers"],
                  ["cash", "dash.panel.cash", "Cash payments"],
                ] as const).map(([k, key, fallback]) => (
                  <div key={k}>
                    <dt>{tr(key, fallback)} <span className="text-muted tnum">· {d.payment_totals![k].count}</span></dt>
                    <dd className="tnum">{d.payment_totals![k].total_text}</dd>
                  </div>
                ))}
              </dl>
            </section>
          )}

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

          {d.by_department && (view === "approver" || d.by_department.length > 0) && (
            <section className="vf-panel">
              <div className="vf-panel-head">
                <div className="vf-panel-head-main">
                  <h2>{tr("dash.panel.deptSpending", "Department spending")}</h2>
                  <div className="vf-panel-sub">
                    {view === "approver"
                      ? tr("dash.panel.deptSpendingMonth", "Approved and paid this month")
                      : tr("dash.panel.deptSpendingAll", "Approved and paid vouchers")}
                  </div>
                </div>
              </div>
              {d.by_department.length === 0 ? (
                <p className="app-dash-empty">{tr("dash.activity.empty", "No activity yet.")}</p>
              ) : (
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
              )}
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

          {view === "employee" && (
            <section className="vf-panel">
              <div className="vf-panel-pad app-dash-links">
                <Link className="btn btn-secondary btn-block" href="/vouchers"><Icon name="ph-clock-counter-clockwise" size={16} /> {tr("dash.panel.voucherHistory", "View voucher history")}</Link>
                <Link className="btn btn-secondary btn-block" href="/reports"><Icon name="ph-chart-line" size={16} /> {tr("dash.panel.viewReports", "View reports")}</Link>
              </div>
            </section>
          )}
        </aside>
      </div>
    </div>
  );
}

type Tr = (key: string | null | undefined, fallback: string, params?: Record<string, string | number> | null) => string;

/** "You have 3 vouchers waiting for your attention." — or a plain all-clear. */
function AttentionBanner({ banner, tr }: { banner: NonNullable<DashboardPayload["data"]["banner"]>; tr: Tr }) {
  const pending = banner.count > 0;

  return (
    <div className="app-attn" data-tone={pending ? "info" : "ok"} role="status">
      <span className="app-attn-icon"><Icon name={pending ? "ph-bell-ringing" : "ph-check-circle"} size={20} /></span>
      <div className="app-attn-text">
        <div className="app-attn-title">{tr(banner.key, banner.title, banner.params)}</div>
        {banner.body && <div className="app-attn-body">{tr(banner.body_key, banner.body)}</div>}
      </div>
      {banner.action && (
        <a className="btn btn-primary btn-sm app-attn-action" href={banner.action.href}>
          {tr(banner.action.key, banner.action.label)} <Icon name="ph-arrow-right" size={14} />
        </a>
      )}
    </div>
  );
}

/** Who did what to which voucher, newest first. */
function ActivityPanel({ title, rows, selfId, locale, tr, link }: {
  title: string; rows: DashboardActivity[]; selfId?: number; locale: Locale; tr: Tr;
  link: { href: string; label: string };
}) {
  return (
    <section className="vf-panel" aria-label={title}>
      <div className="vf-panel-head">
        <div className="vf-panel-head-main"><h2>{title}</h2></div>
        <Link className="btn btn-ghost btn-sm" href={link.href}>{link.label} <Icon name="ph-arrow-right" size={13} /></Link>
      </div>
      {rows.length === 0 ? (
        <p className="app-dash-empty">{tr("dash.activity.empty", "No activity yet.")}</p>
      ) : (
        <ul className="app-activity">
          {rows.map((row) => (
            <li key={row.id}>
              <span className="app-activity-dot" data-action={row.action} />
              <div className="app-activity-main">
                <span>
                  <strong>{row.actor_id && row.actor_id === selfId ? tr("dash.activity.you", "You") : row.actor ?? "—"}</strong>{" "}
                  {tr(`activity.${row.action}`, row.action_label)}{" "}
                  <Link href={`/vouchers/${row.voucher_id}`} className="tnum">{row.voucher_number ?? `#${row.voucher_id}`}</Link>
                </span>
                <span className="app-activity-meta">
                  {[row.amount_text, relativeTime(row.at, locale)].filter(Boolean).join(" · ")}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** The default approval route, step by step, with a way into its settings. */
function WorkflowCard({ workflow, locale, tr }: { workflow: NonNullable<DashboardPayload["data"]["workflow"]> | null; locale: Locale; tr: Tr }) {
  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main">
          <h2>{tr("dash.panel.workflow", "Approval workflow")}</h2>
          <div className="vf-panel-sub">
            {workflow ? ((locale === "sw" && workflow.name_sw) || workflow.name) : tr("dash.panel.workflowSub", "Default route for new vouchers")}
          </div>
        </div>
        <Link className="btn btn-ghost btn-sm" href="/settings#workflow">{tr("dash.panel.manageWorkflow", "Manage workflow")} <Icon name="ph-arrow-right" size={13} /></Link>
      </div>
      {workflow && workflow.steps.length > 0 ? (
        <ol className="app-wf-route">
          {workflow.steps.map((step) => (
            <li key={step.position}>
              <span className="app-wf-route-icon"><Icon name={STEP_ICON[step.action] ?? "ph-circle"} size={15} /></span>
              <span className="app-wf-route-name">{(locale === "sw" && step.name_sw) || step.name}</span>
              <span className="app-wf-route-kind">{tr(`dash.step.${step.action}`, step.action)}</span>
            </li>
          ))}
        </ol>
      ) : (
        <p className="app-dash-empty">{tr("dash.panel.noWorkflow", "No default workflow is active.")}</p>
      )}
    </section>
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
        <div className="skeleton" style={{ height: 26, width: "min(320px, 70%)" }} />
        <div className="skeleton" style={{ height: 14, width: "min(300px, 60%)" }} />
      </div>
      <div className="skeleton" style={{ height: 64, marginBottom: 16 }} />
      <div className="skeleton" style={{ height: 88, marginBottom: 20 }} />
      <div className="app-dash-grid">
        <div className="skeleton" style={{ height: 320 }} />
        <div className="skeleton" style={{ height: 320 }} />
      </div>
    </div>
  );
}
