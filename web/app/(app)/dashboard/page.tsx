"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate } from "@/lib/format";
import {
  Banner, EmptyState, ErrorState, Icon, LoadingBlock, Note, PageHeader,
  Panel, SectionTitle, StatBlock, StatGrid,
} from "@/components/ui";
import { VoucherCard } from "@/components/voucher-bits";
import type { DashboardPayload } from "@/lib/types";

/**
 * The dashboard is an action queue, not a history page.
 *
 * It shows only what this person must do next. The moment they act, the
 * voucher moves to whoever is next in the workflow and leaves this screen —
 * so an empty dashboard means the work is genuinely clear, not that nothing
 * happened. Everything already dealt with is found through Reports.
 */
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
  if (!payload) return <LoadingBlock rows={5} />;

  const d = payload.data;
  const queue = payload.queue ?? d.queue ?? [];
  const isCashier = user?.role === "cashier";
  const isEmployee = user?.role === "employee";
  const isAdmin = user?.role === "company_admin";
  const isPlatform = user?.role === "super_admin";
  const expiring = company && company.status === "trial" && (company.days_remaining ?? 99) <= 7;

  const queueTitle = isCashier ? t("paymentQueue")
    : isEmployee ? t("actionQueue")
    : isAdmin ? t("stalled")
    : t("pendingApprovals");

  return (
    <div style={{ maxWidth: 1120 }}>
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

      <PageHeader
        kicker={`${payload.greeting}, ${user?.name.split(" ")[0] ?? ""}`}
        title={d.headline}
        sub={d.sub}
        actions={
          isPlatform ? (
            <Link className="btn btn-primary" href="/platform/companies">
              <Icon name="ph-buildings" size={15} /> {t("companies")}
            </Link>
          ) : isCashier ? (
            <Link className="btn btn-secondary" href="/reports">
              <Icon name="ph-chart-line" size={15} /> {t("reports")}
            </Link>
          ) : (
            <>
              <Link className="btn btn-primary" href="/vouchers/new">
                <Icon name="ph-plus-circle" size={15} /> {t("createVoucher")}
              </Link>
              <Link className="btn btn-secondary" href="/reports">{t("reports")}</Link>
            </>
          )
        }
      />

      <div style={{ marginBottom: "var(--space-7)" }}>
        <StatGrid>
          {d.stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
        </StatGrid>
      </div>

      {/* ── the queue ── */}
      {queue.length > 0 && (
        <section style={{ marginBottom: "var(--space-7)" }}>
          <SectionTitle actions={
            payload.queue_total_text ? (
              <span style={{ fontSize: 14, color: "var(--color-neutral-600)", fontVariantNumeric: "tabular-nums" }}>
                {payload.queue_total_text}
              </span>
            ) : undefined
          }>
            {queueTitle} · {queue.length}
          </SectionTitle>

          <div style={{ display: "grid", gap: "var(--space-3)" }}>
            {queue.map((voucher) => <VoucherCard key={voucher.id} voucher={voucher} />)}
          </div>

          <div style={{ marginTop: "var(--space-4)", maxWidth: "74ch" }}>
            <Note>{isAdmin ? t("stalledNote") : t("clearedNote")}</Note>
          </div>
        </section>
      )}

      {queue.length === 0 && !isPlatform && (
        <section style={{ marginBottom: "var(--space-7)" }}>
          <EmptyState
            icon="ph-check-square-offset"
            title={t("nothingOnYou")}
            body={t("historyInReports")}
            action={<Link className="btn btn-secondary" href="/reports">
              <Icon name="ph-chart-line" size={15} /> {t("reports")}
            </Link>}
          />
        </section>
      )}

      {/* ── where the company's open work is sitting ── */}
      {d.by_stage && d.by_stage.length > 0 && (
        <section style={{ marginBottom: "var(--space-7)" }}>
          <SectionTitle>{t("byStage")}</SectionTitle>
          <Panel>
            <div style={{ display: "grid", gap: "var(--space-3)" }}>
              {d.by_stage.map((row) => (
                <div key={row.name}>
                  <div style={{ display: "flex", gap: "var(--space-2)", fontSize: 14, alignItems: "baseline" }}>
                    <span style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {row.name}
                    </span>
                    <span style={{ fontVariantNumeric: "tabular-nums", color: "var(--color-neutral-700)" }}>{row.count}</span>
                    <span style={{ fontVariantNumeric: "tabular-nums", fontWeight: 600, minWidth: 96, textAlign: "right" }}>
                      {compactMoney(row.total, company?.currency)}
                    </span>
                  </div>
                  <div className="vf-meter" style={{ marginTop: 4 }}><span style={{ width: row.share }} /></div>
                </div>
              ))}
            </div>
          </Panel>
        </section>
      )}

      {/* ── the platform's own queue ── */}
      {d.attention && (
        <section>
          <SectionTitle actions={<Link className="btn btn-ghost btn-sm" href="/platform/companies">{t("all")}</Link>}>
            {t("companies")}
          </SectionTitle>
          {d.attention.length === 0 ? (
            <EmptyState icon="ph-check-square-offset" title={t("nothingOnYou")} body={t("historyInReports")} />
          ) : (
            <Panel pad={false}>
              <div className="table-wrap">
                <table className="table">
                  <thead>
                    <tr>
                      <th>{t("companyName")}</th><th>{t("plan")}</th>
                      <th>{t("users")}</th><th>{t("status")}</th><th></th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.attention.map((row) => (
                      <tr key={row.id}>
                        <td><Link href={`/platform/companies/${row.id}`}>{row.name}</Link></td>
                        <td>{row.plan ?? "—"}</td>
                        <td style={{ fontVariantNumeric: "tabular-nums" }}>{row.users_count}</td>
                        <td>
                          <span className={`tag ${row.status === "trial" ? "tag-outline" : "tag-accent-2"}`}>
                            {row.status}
                          </span>
                        </td>
                        <td style={{ color: "var(--color-neutral-600)" }}>{row.note}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </Panel>
          )}
        </section>
      )}
    </div>
  );
}
