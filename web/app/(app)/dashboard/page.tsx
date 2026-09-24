"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, money, relativeTime } from "@/lib/format";
import {
  Banner, EmptyState, ErrorState, Icon, Meter, StatBlock,
  type Kpi, type Tone,
} from "@/components/ui";
import { VoucherList } from "@/components/voucher-bits";
import type { AuditEntry, DashboardPayload, Paginated, Role, Usage, Voucher } from "@/lib/types";

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
  manager: [["ph-seal-check", "info"], ["ph-check-circle", "ok"], ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"]],
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
  // The reader's own clock decides the greeting, not the server's (which runs on UTC).
  const hour = new Date().getHours();
  const greeting = t(hour < 12 ? "goodMorning" : hour < 17 ? "goodAfternoon" : "goodEvening");
  const hasContext = Boolean(d.by_stage?.length || d.volume?.length || d.by_department?.length);
  // Six figures read as two rows of three; four as one row.
  const kpiCols = stats.length === 6 || stats.length === 3 ? 3 : Math.min(stats.length, 4);
  const today = new Intl.DateTimeFormat(sw ? "sw-TZ" : "en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(new Date());

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

      {isAdmin ? (
        <header className="vf-pagehead app-dash-head">
          <div className="vf-pagehead-main">
            <h1 className="vf-pagehead-title">{greeting}, {firstName}</h1>
            <p className="vf-pagehead-sub">{today}{company?.name ? ` · ${company.name}` : ""}</p>
          </div>
          <div className="vf-pagehead-actions">
            <Link className="btn btn-secondary btn-sm" href="/reports"><Icon name="ph-chart-bar" size={15} /> {t("reports")}</Link>
          </div>
        </header>
      ) : (
        <header className="vf-pagehead app-dash-head">
          <div className="vf-pagehead-main">
            <p className="app-dash-hello">{greeting}, {firstName}</p>
            <h1 className="vf-pagehead-title">{d.headline}</h1>
            {d.sub && <p className="vf-pagehead-sub">{d.sub}</p>}
          </div>
          <div className="vf-pagehead-actions">
            {isPlatform
              ? <Link className="btn btn-primary btn-sm" href="/platform/companies"><Icon name="ph-buildings" size={15} /> {t("companies")}</Link>
              : <Link className="btn btn-secondary btn-sm" href="/reports"><Icon name="ph-chart-bar" size={15} /> {t("reports")}</Link>}
          </div>
        </header>
      )}

      {isAdmin && <AttentionStrip />}

      <section className="app-section" aria-label={sw ? "Takwimu" : "Key figures"}>
        <div className="vf-kpis" style={{ gridTemplateColumns: `repeat(${kpiCols}, minmax(0, 1fr))` }}>
          {stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
        </div>
      </section>

      {isAdmin ? (
        <>
          {(d.volume?.length || d.by_department?.length) ? (
            <div className="app-dash-row">
              {d.volume && d.volume.length > 0 && <VolumeChart volume={d.volume} currency={company?.currency} />}
              {d.by_department && d.by_department.length > 0 && <DepartmentSpend rows={d.by_department} currency={company?.currency} />}
            </div>
          ) : null}
          <div className="app-dash-row">
            <QueuePanel title={queueTitle} queue={queue} total={payload.queue_total_text} note={t("stalledNote")} isCashier={false} />
            <div className="app-dash-aside">
              <PlanUsage />
              <RecentActivity />
            </div>
          </div>
        </>
      ) : (
        <div className={`app-dash-grid${hasContext || isPlatform ? "" : " is-single"}`}>
          {/* ── the work ── */}
          <div className="app-dash-main">
            {!isPlatform && (
              <QueuePanel title={queueTitle} queue={queue} total={payload.queue_total_text} note={t("clearedNote")} isCashier={isCashier} />
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
                            <span className={`badge ${row.status === "trial" ? "tone-warn" : "tone-bad"}`}>
                              <Icon name={row.status === "trial" ? "ph-hourglass-medium" : "ph-warning-circle"} size={13} /> {row.status}
                            </span>
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
                          <td><InvoiceBadge status={p.status} /></td>
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
                  <div className="vf-panel-pad app-hbars">
                    {d.by_stage.map((row) => (
                      <HBar key={row.name} name={row.name} share={row.share} value={compactMoney(row.total, company?.currency)} count={row.count} />
                    ))}
                  </div>
                </section>
              )}

              {d.volume && d.volume.length > 0 && <VolumeChart volume={d.volume} currency={company?.currency} />}

              {d.by_department && d.by_department.length > 0 && <DepartmentSpend rows={d.by_department} currency={company?.currency} />}

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
                        <CompanyBadge status={c.status} />
                      </li>
                    ))}
                  </ul>
                </section>
              )}
            </aside>
          )}
        </div>
      )}
    </div>
  );
}

/* ───────────────────────────────────────────────────────── pieces ── */

/** A company's account state, as icon + label. */
function CompanyBadge({ status }: { status: string }) {
  const tone = status === "active" ? "ok" : status === "trial" ? "warn" : "bad";
  const icon = status === "active" ? "ph-check-circle" : status === "trial" ? "ph-hourglass-medium" : "ph-warning-circle";
  return <span className={`badge tone-${tone}`}><Icon name={icon} size={13} /> {status}</span>;
}

function InvoiceBadge({ status }: { status: string }) {
  const tone = status === "paid" ? "ok" : status === "pending" ? "warn" : status === "failed" ? "bad" : "neutral";
  const icon = status === "paid" ? "ph-check-circle" : status === "pending" ? "ph-hourglass-medium" : status === "failed" ? "ph-x-circle" : "ph-minus-circle";
  return <span className={`badge tone-${tone}`}><Icon name={icon} size={13} /> {status}</span>;
}

/** The work this person owes, or a clear "nothing waiting" with the next useful step. */
function QueuePanel({ title, queue, total, note, isCashier }: {
  title: string; queue: NonNullable<DashboardPayload["queue"]>; total?: string; note: string; isCashier: boolean;
}) {
  const { t } = useApp();
  return (
    <section className="vf-panel" id="queue" aria-labelledby="queue-title">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main app-panel-title">
          <h2 id="queue-title">{title}</h2>
          <span className="vf-count">{queue.length}</span>
        </div>
        {total && queue.length > 0 && (
          <div className="app-queue-total">{t("total")} <strong className="tnum">{total}</strong></div>
        )}
      </div>
      {queue.length > 0 ? (
        <>
          <VoucherList vouchers={queue} bare />
          <div className="app-panel-foot">
            <Icon name="ph-info" size={15} />
            <span>{note}</span>
          </div>
        </>
      ) : (
        <EmptyState
          tone="ok" icon="ph-checks" title={t("nothingOnYou")} body={t("historyInReports")}
          action={
            <>
              <Link className="btn btn-secondary btn-sm" href="/reports"><Icon name="ph-chart-bar" size={15} /> {t("reports")}</Link>
              {!isCashier && <Link className="btn btn-primary btn-sm" href="/vouchers/new"><Icon name="ph-plus" size={15} /> {t("createVoucher")}</Link>}
            </>
          }
        />
      )}
    </section>
  );
}

/**
 * What is waiting across the company, and on whom — three counts from the
 * voucher list itself, each a way into the list behind it.
 */
function AttentionStrip() {
  const { locale, company } = useApp();
  const sw = locale === "sw";
  const [cells, setCells] = useState<{ total: number; amount?: number }[] | null>(null);

  useEffect(() => {
    const count = (status: string) => api.get<Paginated<Voucher>>("/vouchers", { status, per_page: 1 })
      .then((r) => ({ total: r.meta?.total ?? r.data.length, amount: r.meta?.total_amount }))
      .catch(() => ({ total: 0 }));
    Promise.all([count("pending"), count("approved"), count("changes_requested")]).then(setCells);
  }, []);

  const currency = company?.currency ?? "TZS";
  const items = [
    { href: "/approvals", icon: "ph-seal-check", tone: "brand",
      title: (n: number) => sw ? `${n} zinasubiri idhini` : `${n} awaiting approval`,
      sub: sw ? "katika mtiririko wa idhini" : "in the approval workflow" },
    { href: "/payments", icon: "ph-wallet", tone: "ok",
      title: (n: number) => sw ? `${n} zimeidhinishwa, hazijalipwa` : `${n} approved, not yet paid`,
      sub: sw ? "kwenye foleni ya malipo" : "in the payment queue" },
    { href: "/vouchers?status=changes_requested", icon: "ph-arrow-u-up-left", tone: "warn",
      title: (n: number) => sw ? `${n} zimerudishwa kwa mabadiliko` : `${n} returned for changes`,
      sub: sw ? "zinasubiri waombaji kuwasilisha tena" : "waiting on the requesters to resubmit" },
  ];

  return (
    <div className="vf-panel app-attn" aria-label={sw ? "Kinachosubiri" : "What is waiting"}>
      {items.map((item, i) => {
        const cell = cells?.[i];
        return (
          <Link key={item.href} href={item.href} className="app-attn-cell">
            <span className={`app-attn-icon tone-${item.tone}`}><Icon name={item.icon} size={19} /></span>
            <span className="app-attn-text">
              {cell ? <span className="app-attn-title tnum">{item.title(cell.total)}</span> : <span className="skeleton" style={{ height: 14, width: 150, display: "block" }} />}
              <span className="app-attn-sub">
                {cell && cell.amount != null && cell.total > 0 ? `${compactMoney(cell.amount, currency)} · ` : ""}{item.sub}
              </span>
            </span>
            <Icon name="ph-arrow-right" size={17} style={{ color: "var(--text-muted)", flex: "none" }} />
          </Link>
        );
      })}
    </div>
  );
}

/** One labelled horizontal bar: name, a track scaled to the largest row, and the value. */
function HBar({ name, share, value, count }: { name: string; share: string; value: string; count?: number }) {
  return (
    <div className="app-hbar" title={count != null ? `${name} · ${count} · ${value}` : `${name} · ${value}`}>
      <span className="app-hbar-name">{name}</span>
      <span className="app-hbar-track"><span style={{ width: share }} /></span>
      <span className="app-hbar-value tnum">{value}</span>
    </div>
  );
}

function DepartmentSpend({ rows, currency }: { rows: NonNullable<DashboardPayload["data"]["by_department"]>; currency?: string }) {
  const { t, locale } = useApp();
  const sw = locale === "sw";
  const shown = rows.filter((r) => r.total > 0).slice(0, 7);
  const max = Math.max(1, ...shown.map((r) => r.total));
  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main">
          <h2>{t("spendByDept")}</h2>
          <div className="vf-panel-sub">{sw ? "Vocha zilizoidhinishwa" : "Approved vouchers"} · {currency ?? "TZS"}</div>
        </div>
        <Link className="btn btn-ghost btn-sm" href="/reports">{sw ? "Ripoti kamili" : "Full report"} <Icon name="ph-arrow-right" size={13} /></Link>
      </div>
      <div className="vf-panel-pad app-hbars">
        {shown.length === 0
          ? <p className="app-muted-line"><Icon name="ph-info" size={15} /> {sw ? "Hakuna matumizi yaliyoidhinishwa bado." : "No approved spend yet."}</p>
          : shown.map((row) => (
            <HBar key={row.id} name={row.name} share={`${(row.total / max) * 100}%`} value={compactMoney(row.total, currency)} count={row.count} />
          ))}
      </div>
    </section>
  );
}

/** The plan's limits next to what the company uses, from the same figures UsageLimits enforces. */
function PlanUsage() {
  const { locale, company } = useApp();
  const sw = locale === "sw";
  const [usage, setUsage] = useState<Usage | null>(null);
  useEffect(() => {
    api.get<{ data: Usage }>("/company/usage").then((r) => setUsage(r.data)).catch(() => setUsage(null));
  }, []);
  if (!usage) return null;
  const metrics = [usage.users, usage.departments, usage.storage, usage.vouchers_this_month];
  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main">
          <h2>{sw ? "Matumizi ya mpango" : "Plan usage"}</h2>
          <div className="vf-panel-sub">{usage.plan ?? company?.plan?.name ?? ""}</div>
        </div>
        <Link className="btn btn-ghost btn-sm" href="/subscription">{sw ? "Mpango" : "Plan"} <Icon name="ph-arrow-right" size={13} /></Link>
      </div>
      <div className="vf-panel-pad app-usage">
        {metrics.map((m) => (
          <div key={m.label} className="app-usage-row">
            <div className="app-usage-top">
              <span>{m.label}</span>
              <span className="tnum">{m.unlimited ? `${m.used.toLocaleString()} · ${sw ? "bila kikomo" : "unlimited"}` : `${m.used.toLocaleString()} / ${m.limit?.toLocaleString()}${m.unit ? ` ${m.unit}` : ""}`}</span>
            </div>
            {!m.unlimited && <Meter percent={m.percent} exceeded={m.exceeded} />}
          </div>
        ))}
      </div>
    </section>
  );
}

/** The last few things that happened in the company, from the audit log. */
function RecentActivity() {
  const { locale } = useApp();
  const sw = locale === "sw";
  const [rows, setRows] = useState<AuditEntry[] | null>(null);
  useEffect(() => {
    api.get<Paginated<AuditEntry>>("/audit-logs", { per_page: 5 }).then((r) => setRows(r.data)).catch(() => setRows([]));
  }, []);
  if (!rows || rows.length === 0) return null;
  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main"><h2>{sw ? "Shughuli za karibuni" : "Recent activity"}</h2></div>
        <Link className="btn btn-ghost btn-sm" href="/audit">{sw ? "Kumbukumbu" : "Audit log"} <Icon name="ph-arrow-right" size={13} /></Link>
      </div>
      <ul className="app-activity">
        {rows.map((row) => (
          <li key={row.id}>
            <span className="app-avatar" aria-hidden="true">{row.actor.initials}</span>
            <span className="app-activity-text">
              <span><strong>{row.actor.name}</strong> {row.description.startsWith(row.actor.name) ? row.description.slice(row.actor.name.length).trim() : row.description}</span>
              {row.change_summary && <span className="app-activity-sub">{row.change_summary}</span>}
            </span>
            <span className="app-activity-when">{relativeTime(row.created_at, locale)}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

/**
 * Voucher value per month as quiet columns on a faint grid; the current month
 * is the only coloured bar. Hovering a column names its month, count and value.
 */
function VolumeChart({ volume, currency }: { volume: NonNullable<DashboardPayload["data"]["volume"]>; currency?: string }) {
  const { locale } = useApp();
  const sw = locale === "sw";
  const max = Math.max(1, ...volume.map((v) => v.total));
  const current = volume.find((v) => v.is_current);
  const [hover, setHover] = useState<string | null>(null);
  const shown = volume.find((v) => v.period === hover) ?? current;

  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main">
          <h2>{sw ? "Thamani ya vocha kwa mwezi" : "Voucher value per month"}</h2>
          <div className="vf-panel-sub">{currency ?? "TZS"} · {sw ? `miezi ${volume.length} iliyopita` : `last ${volume.length} months`}</div>
        </div>
        {shown && (
          <div className="app-chart-now tnum">
            <span className="app-chart-now-label">{shown.label}</span> {compactMoney(shown.total, currency)}
            <span className="app-chart-now-label"> · {shown.count}</span>
          </div>
        )}
      </div>
      <div className="vf-panel-pad">
        <div className="app-columns" role="img" aria-label={volume.map((v) => `${v.label}: ${money(v.total, currency)}`).join(", ")}
          style={{ gridTemplateColumns: `repeat(${volume.length}, minmax(0, 1fr))` }} onMouseLeave={() => setHover(null)}>
          {volume.map((v) => (
            <div key={v.period} className="app-column" data-current={v.is_current || undefined} data-hover={hover === v.period || undefined}
              onMouseEnter={() => setHover(v.period)} title={`${v.label} · ${v.count} · ${money(v.total, currency)}`}>
              <span className="app-column-bar" style={{ height: `${Math.max(2, (v.total / max) * 100)}%` }} />
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
      <div style={{ display: "grid", gap: 8, marginBottom: 24 }}>
        <div className="skeleton" style={{ height: 26, width: "min(360px, 80%)" }} />
        <div className="skeleton" style={{ height: 14, width: "min(280px, 60%)" }} />
      </div>
      <div className="vf-kpis" style={{ marginBottom: 20 }}>
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="vf-kpi">
            <div className="skeleton" style={{ height: 11, width: 90 }} />
            <div className="skeleton" style={{ height: 24, width: 130 }} />
            <div className="skeleton" style={{ height: 10, width: 110 }} />
          </div>
        ))}
      </div>
      <div className="app-dash-grid">
        <div className="skeleton" style={{ height: 320, borderRadius: 12 }} />
        <div className="skeleton" style={{ height: 320, borderRadius: 12 }} />
      </div>
    </div>
  );
}
