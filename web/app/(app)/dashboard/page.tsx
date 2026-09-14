"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate } from "@/lib/format";
import {
  Banner, EmptyState, ErrorState, Icon, Note, Panel, SectionTitle, StatBlock, StatGrid,
  type Kpi, type Tone,
} from "@/components/ui";
import { VoucherList } from "@/components/voucher-bits";
import type { DashboardPayload, Role } from "@/lib/types";

/**
 * The dashboard is an action queue, not a history page.
 *
 * Its first job is the five-second answer: what needs me, right now. The
 * moment someone acts, the voucher moves to whoever is next and leaves this
 * screen — an empty dashboard means the work is genuinely clear. Everything
 * already dealt with lives in Reports.
 *
 * What each role sees is decided by the backend (queue, stats, stage
 * breakdown); this page only decides how it reads.
 */

/*
 * Icons and tones for each role's stats, by position. The backend sends each
 * role's stats as a fixed, ordered set, so position is stable — and unlike the
 * label it does not change with the language. Only the number that asks for
 * action is coloured; the rest stay neutral so it stands out.
 */
type Look = [icon: string, tone: Tone];

const LOOKS: Partial<Record<Role, Look[]>> = {
  employee: [
    ["ph-pencil-simple-line", "info"], ["ph-hourglass-medium", "neutral"],
    ["ph-check-circle", "ok"], ["ph-receipt", "neutral"],
  ],
  hod: [
    ["ph-signature", "info"], ["ph-check-circle", "ok"],
    ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"],
  ],
  ceo: [
    ["ph-seal-check", "info"], ["ph-check-circle", "ok"],
    ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"],
  ],
  director: [
    ["ph-seal-check", "info"], ["ph-check-circle", "ok"],
    ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"],
  ],
  finance: [
    ["ph-seal-check", "info"], ["ph-check-circle", "ok"],
    ["ph-arrow-u-up-left", "warn"], ["ph-coins", "neutral"],
  ],
  cashier: [
    ["ph-wallet", "info"], ["ph-bank", "neutral"],
    ["ph-money", "neutral"], ["ph-check-circle", "ok"],
  ],
  company_admin: [
    ["ph-receipt", "neutral"], ["ph-hourglass-medium", "info"], ["ph-check-circle", "ok"],
    ["ph-x-circle", "bad"], ["ph-chart-line-up", "neutral"], ["ph-timer", "neutral"],
  ],
  super_admin: [
    ["ph-buildings", "neutral"], ["ph-currency-circle-dollar", "ok"], ["ph-chart-line-up", "neutral"],
    ["ph-users-three", "neutral"], ["ph-receipt", "neutral"], ["ph-stack", "neutral"],
  ],
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
    // The first number is the queue itself; clicking it goes there.
    href: index === 0 && queue.length > 0 && !isPlatform && !isAdmin ? "#queue" : undefined,
  }));

  const firstName = user?.name.split(" ")[0] ?? "";

  return (
    <div className="vf-dashboard">
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

      <header className="vf-greeting">
        <div className="vf-greeting-main">
          <p className="vf-greeting-hello">{payload.greeting}, {firstName}</p>
          <h1 className="vf-greeting-title">{d.headline}</h1>
          {d.sub && <p className="vf-greeting-sub">{d.sub}</p>}
        </div>
        <div className="vf-pagehead-actions">
          {isPlatform ? (
            <Link className="btn btn-primary" href="/platform/companies">
              <Icon name="ph-buildings" size={17} /> {t("companies")}
            </Link>
          ) : isCashier ? (
            <Link className="btn btn-secondary" href="/reports">
              <Icon name="ph-chart-line" size={17} /> {t("reports")}
            </Link>
          ) : (
            <>
              <Link className="btn btn-secondary" href="/reports">
                <Icon name="ph-chart-line" size={17} /> {t("reports")}
              </Link>
              <Link className="btn btn-primary" href="/vouchers/new">
                <Icon name="ph-plus" size={17} /> {t("createVoucher")}
              </Link>
            </>
          )}
        </div>
      </header>

      <section className="vf-dash-section">
        <StatGrid>
          {stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
        </StatGrid>
      </section>

      {/* ── the queue ── */}
      {queue.length > 0 && (
        <section className="vf-dash-section" id="queue">
          <SectionTitle
            count={queue.length}
            actions={payload.queue_total_text
              ? <span className="vf-queue-total">{t("total")} <strong>{payload.queue_total_text}</strong></span>
              : undefined}
          >
            {queueTitle}
          </SectionTitle>

          <VoucherList vouchers={queue} />

          <div style={{ marginTop: 12 }}>
            <Note>{isAdmin ? t("stalledNote") : t("clearedNote")}</Note>
          </div>
        </section>
      )}

      {queue.length === 0 && !isPlatform && (
        <section className="vf-dash-section">
          <div className="vf-panel">
            <EmptyState
              tone="ok"
              icon="ph-check-circle"
              title={t("nothingOnYou")}
              body={t("historyInReports")}
              action={
                <>
                  <Link className="btn btn-secondary" href="/reports">
                    <Icon name="ph-chart-line" size={17} /> {t("reports")}
                  </Link>
                  {!isCashier && (
                    <Link className="btn btn-primary" href="/vouchers/new">
                      <Icon name="ph-plus" size={17} /> {t("createVoucher")}
                    </Link>
                  )}
                </>
              }
            />
          </div>
        </section>
      )}

      {/* ── where the company's open work is sitting ── */}
      {d.by_stage && d.by_stage.length > 0 && (
        <section className="vf-dash-section">
          <SectionTitle>{t("byStage")}</SectionTitle>
          <Panel>
            <div className="vf-stages">
              {d.by_stage.map((row) => (
                <div key={row.name} className="vf-stage">
                  <div className="vf-stage-row">
                    <span className="vf-stage-name">{row.name}</span>
                    <span className="vf-stage-count">{row.count}</span>
                    <span className="vf-stage-total">{compactMoney(row.total, company?.currency)}</span>
                  </div>
                  <div className="vf-meter"><span style={{ width: row.share }} /></div>
                </div>
              ))}
            </div>
          </Panel>
        </section>
      )}

      {/* ── the platform's own queue ── */}
      {d.attention && (
        <section className="vf-dash-section">
          <SectionTitle
            count={d.attention.length}
            actions={<Link className="btn btn-ghost btn-sm" href="/platform/companies">{t("all")} <Icon name="ph-arrow-right" size={14} /></Link>}
          >
            {t("companiesNeedingAttention")}
          </SectionTitle>
          {d.attention.length === 0 ? (
            <div className="vf-panel">
              <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingOnYou")} body={t("historyInReports")} />
            </div>
          ) : (
            <div className="vf-panel vf-list">
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
                    <Icon name="ph-caret-right" size={16} style={{ color: "var(--color-neutral-500)" }} />
                  </div>
                </Link>
              ))}
            </div>
          )}
        </section>
      )}
    </div>
  );
}

/** The shape of the dashboard, so the page does not jump when data arrives. */
function DashboardSkeleton() {
  return (
    <div className="vf-dashboard" aria-busy="true">
      <span className="sr-only">Loading</span>
      <div style={{ display: "grid", gap: 10, marginBottom: 28 }}>
        <div className="skeleton" style={{ height: 16, width: 180 }} />
        <div className="skeleton" style={{ height: 32, width: "min(460px, 80%)" }} />
        <div className="skeleton" style={{ height: 16, width: "min(340px, 60%)" }} />
      </div>
      <div className="vf-kpis" style={{ marginBottom: 32 }}>
        {[0, 1, 2, 3].map((i) => <div key={i} className="skeleton" style={{ height: 112, borderRadius: 14 }} />)}
      </div>
      <div className="skeleton" style={{ height: 20, width: 200, marginBottom: 14 }} />
      <div className="skeleton" style={{ height: 240, borderRadius: 14 }} />
    </div>
  );
}
