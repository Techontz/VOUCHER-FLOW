"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, money } from "@/lib/format";
import {
  Banner, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader,
  SectionTitle, StatBlock, StatGrid,
} from "@/components/ui";
import { VoucherCard, VoucherTable } from "@/components/voucher-bits";
import type { DashboardPayload } from "@/lib/types";

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
  const queue = d.queue ?? [];
  const recent = d.recent ?? [];
  const expiring = company && company.status === "trial" && (company.days_remaining ?? 99) <= 7;

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
          user?.role !== "super_admin" ? (
            <>
              <Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus-circle" size={15} /> {t("createVoucher")}</Link>
              <Link className="btn btn-secondary" href="/vouchers">{t("trackMine")}</Link>
            </>
          ) : (
            <Link className="btn btn-primary" href="/platform/companies"><Icon name="ph-buildings" size={15} /> {t("companies")}</Link>
          )
        }
      />

      <div style={{ marginBottom: "var(--space-8)" }}>
        <StatGrid>
          {d.stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
        </StatGrid>
      </div>

      {/* Approver queue */}
      {queue.length > 0 && (
        <section style={{ marginBottom: "var(--space-8)" }}>
          <SectionTitle>{t("pendingApprovals")}</SectionTitle>
          <div style={{ display: "grid", gap: "var(--space-3)" }}>
            {queue.map((voucher) => <VoucherCard key={voucher.id} voucher={voucher} />)}
          </div>
          <div style={{ marginTop: "var(--space-4)", fontSize: 14, color: "var(--color-neutral-700)", borderLeft: "2px solid var(--color-accent-300)", paddingLeft: 12, maxWidth: "62ch" }}>
            {t("signOnlyNote")}
          </div>
        </section>
      )}

      {queue.length === 0 && (user?.role === "hod" || user?.role === "manager" || user?.role === "finance" || user?.role === "director") && (
        <section style={{ marginBottom: "var(--space-8)" }}>
          <EmptyState icon="ph-check-square-offset" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
            action={<Link className="btn btn-secondary" href="/vouchers">{t("register")}</Link>} />
        </section>
      )}

      {/* Admin charts */}
      {(d.volume || d.by_department) && (
        <section className="vf-split" style={{ marginBottom: "var(--space-8)" }}>
          {d.volume && (
            <div>
              <SectionTitle>{t("voucherVolume")}</SectionTitle>
              <div style={{ display: "flex", alignItems: "flex-end", gap: "var(--space-3)", height: 150, borderBottom: "1px solid var(--color-text)", paddingBottom: 2 }}>
                {(() => {
                  const max = Math.max(...d.volume!.map((b) => b.count), 1);
                  return d.volume!.map((bar) => (
                    <div key={bar.period} style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "flex-end", alignItems: "center", gap: 6, height: "100%" }}>
                      <div style={{ fontSize: 12, fontVariantNumeric: "tabular-nums", color: "var(--color-neutral-600)" }}>{bar.count}</div>
                      <div
                        title={`${bar.label}: ${bar.count} vouchers, ${money(bar.total, company?.currency)}`}
                        style={{
                          width: "100%", height: `${Math.max(3, (bar.count / max) * 100)}%`,
                          background: bar.is_current ? "var(--color-accent-2-500)" : "var(--color-accent-500)",
                        }}
                      />
                    </div>
                  ));
                })()}
              </div>
              <div style={{ display: "flex", gap: "var(--space-3)", marginTop: 6 }}>
                {d.volume.map((bar) => (
                  <div key={bar.period} style={{ flex: 1, textAlign: "center", fontSize: 12, color: "var(--color-neutral-600)" }}>{bar.label}</div>
                ))}
              </div>
            </div>
          )}

          {d.by_department && d.by_department.length > 0 && (
            <div>
              <SectionTitle>{t("spendByDept")}</SectionTitle>
              <div style={{ display: "grid", gap: "var(--space-2)" }}>
                {d.by_department.map((row) => (
                  <div key={row.id}>
                    <div style={{ display: "flex", gap: "var(--space-2)", fontSize: 14, alignItems: "baseline" }}>
                      <span style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{row.name}</span>
                      <span style={{ fontVariantNumeric: "tabular-nums", color: "var(--color-neutral-700)" }}>{row.count}</span>
                      <span style={{ fontVariantNumeric: "tabular-nums", fontWeight: 600, minWidth: 92, textAlign: "right" }}>
                        {compactMoney(row.total, company?.currency)}
                      </span>
                    </div>
                    <div style={{ height: 5, background: "var(--color-neutral-200)", marginTop: 3 }}>
                      <div style={{ height: "100%", width: row.share, background: "var(--color-accent-500)" }} />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {/* Platform panels */}
      {d.recent_companies && (
        <section className="vf-split" style={{ marginBottom: "var(--space-8)" }}>
          <div>
            <SectionTitle actions={<Link className="btn btn-ghost btn-sm" href="/platform/companies">{t("all")}</Link>}>
              {t("recentCompanies")}
            </SectionTitle>
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>{t("companyName")}</th><th>{t("plan")}</th><th>{t("users")}</th><th>{t("status")}</th></tr></thead>
                <tbody>
                  {d.recent_companies.map((row: any) => (
                    <tr key={row.id}>
                      <td><Link href={`/platform/companies/${row.id}`}>{row.name}</Link></td>
                      <td>{row.plan ?? "—"}</td>
                      <td style={{ fontVariantNumeric: "tabular-nums" }}>{row.users_count}</td>
                      <td><span className={`tag ${row.status === "active" ? "tag-accent" : row.status === "trial" ? "tag-outline" : "tag-accent-2"}`}>{row.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          <div>
            <SectionTitle actions={<Link className="btn btn-ghost btn-sm" href="/platform/payments">{t("all")}</Link>}>
              {t("recentPayments")}
            </SectionTitle>
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>{t("invoice")}</th><th>{t("companyName")}</th><th style={{ textAlign: "right" }}>{t("amount")}</th><th>{t("status")}</th></tr></thead>
                <tbody>
                  {(d.recent_payments ?? []).map((row: any) => (
                    <tr key={row.id}>
                      <td style={{ fontVariantNumeric: "tabular-nums" }}>{row.number}</td>
                      <td>{row.company}</td>
                      <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{money(row.total, row.currency)}</td>
                      <td><span className={`tag ${row.status === "paid" ? "tag-accent" : row.status === "pending" ? "tag-outline" : "tag-accent-2"}`}>{row.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      )}

      {/* Recent vouchers */}
      {recent.length > 0 && (
        <section>
          <SectionTitle actions={<Link className="btn btn-ghost btn-sm" href="/vouchers">{t("all")}</Link>}>
            {user?.role === "employee" ? t("myRecent") : t("recentVouchers")}
          </SectionTitle>
          <VoucherTable vouchers={recent} />
        </section>
      )}

      {recent.length === 0 && queue.length === 0 && user?.role === "employee" && (
        <EmptyState title={t("noVouchersYet")} body={t("noVouchersBody")}
          action={<Link className="btn btn-primary" href="/vouchers/new">{t("createVoucher")}</Link>} />
      )}
    </div>
  );
}
