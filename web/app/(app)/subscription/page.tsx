"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime, money } from "@/lib/format";
import { Banner, EmptyState, Meter, ErrorState, Icon, LoadingBlock } from "@/components/ui";
import { PayDialog, PlanDialog } from "@/components/billing-dialogs";
import { Figure, FigureStrip, SettingsLayout } from "@/components/app-ui";
import type { Invoice, Paginated, Plan, Subscription, Usage } from "@/lib/types";

interface Payload {
  subscription: Subscription | null;
  plan: Plan | null;
  usage: Usage;
  company_status: string;
  is_expired: boolean;
  days_remaining: number | null;
  auto_renew: boolean;
  available_plans: Plan[];
}

export default function SubscriptionPage() {
  const { t, company, locale, refresh, toast, reportError } = useApp();
  const [payload, setPayload] = useState<Payload | null>(null);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [error, setError] = useState<string | null>(null);

  const [planDialog, setPlanDialog] = useState(false);
  const [payDialog, setPayDialog] = useState<Invoice | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<Payload>("/billing/subscription")
      .then(setPayload)
      .catch((err) => setError(err.message));
    api.get<Paginated<Invoice>>("/billing/invoices", { per_page: 20 })
      .then((r) => setInvoices(r.data)).catch(() => setInvoices([]));
  }, []);

  useEffect(load, [load, locale]);

  async function toggleAutoRenew(value: boolean) {
    try {
      await api.post("/billing/auto-renew", { auto_renew: value });
      toast(value ? "Auto-renew on" : "Auto-renew off", undefined, value ? "ok" : "warn");
      await refresh();
      load();
    } catch (err) { reportError(err); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!payload || !company) return <LoadingBlock rows={5} />;

  const usage = payload.usage;
  const metrics = [usage.users, usage.vouchers_this_month, usage.departments, usage.storage];

  return (
    <SettingsLayout title={t("subscription")}
      sub={payload.subscription
        ? `${payload.plan?.name ?? ""} · ${payload.subscription.billing_cycle === "annual" ? "Annual" : "Monthly"} · ${money(payload.subscription.amount, payload.subscription.currency)}`
        : payload.plan?.name ?? "No plan"}
      actions={<button className="btn btn-primary" onClick={() => setPlanDialog(true)}><Icon name="ph-crown-simple" size={15} /> {t("changePlan")}</button>}>

      {payload.is_expired && (
        <Banner tone="danger" icon="ph-warning-circle" title={t("expired")}>{t("expiredBody")}</Banner>
      )}

      {!payload.is_expired && company.status === "trial" && (
        <Banner tone="warn" icon="ph-clock" title={`${t("trialEnds")} ${formatDate(company.trial_ends_at, locale)}`}>
          {payload.days_remaining} days remaining.
        </Banner>
      )}

      <div className="app-stack">
        <FigureStrip>
          <Figure label={t("currentPlan")} value={payload.plan?.name ?? "—"} sub={company.status} />
          <Figure label={company.status === "trial" ? t("trialEnds") : t("renewsOn")}
            value={formatDate(company.status === "trial" ? company.trial_ends_at : company.current_period_end, locale)}
            sub={payload.days_remaining !== null ? `${payload.days_remaining} days` : undefined} />
          <Figure label={t("seats")} value={`${usage.users.used} / ${usage.users.unlimited ? "∞" : usage.users.limit}`} sub={t("seatsUsed")} />
        </FigureStrip>

        <section className="vf-panel">
          <div className="vf-panel-head">
            <div className="vf-panel-head-main"><h2>{t("usageThisPeriod")}</h2></div>
            <label className="switch">
              <input type="checkbox" checked={payload.auto_renew} onChange={(e) => toggleAutoRenew(e.target.checked)} />
              <span className="track" />
              {t("autoRenew")}
            </label>
          </div>
          <div className="vf-panel-pad app-bars">
            {metrics.map((metric) => (
              <div key={metric.label} className="app-bar-row">
                <div className="app-bar-top">
                  <span className="app-bar-name">{metric.label}</span>
                  <span className="app-bar-value tnum" style={{ color: metric.exceeded ? "var(--danger)" : undefined, minWidth: 0 }}>
                    {metric.used.toLocaleString()}{metric.unit && ` ${metric.unit}`} {t("of")} {metric.unlimited ? "unlimited" : `${metric.limit?.toLocaleString()}${metric.unit ? ` ${metric.unit}` : ""}`}
                  </span>
                </div>
                <Meter percent={metric.percent ?? 4} exceeded={metric.exceeded} />
              </div>
            ))}
          </div>
        </section>

        <section className="vf-panel">
          <div className="vf-panel-head"><div className="vf-panel-head-main app-panel-title"><h2>{t("billingHistory")}</h2><span className="vf-count">{invoices.length}</span></div></div>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>{t("invoice")}</th><th>{t("plan")}</th><th className="num">{t("amount")}</th>
                  <th>{t("method")}</th><th>{t("status")}</th><th>{t("date")}</th><th /></tr>
              </thead>
              <tbody>
                {invoices.map((invoice) => (
                  <tr key={invoice.id}>
                    <td className="tnum" style={{ fontWeight: 500 }}>{invoice.number}</td>
                    <td>{invoice.description}</td>
                    <td className="num" style={{ whiteSpace: "nowrap", fontWeight: 600 }}>{invoice.amount_text}</td>
                    <td>{invoice.method_label}</td>
                    <td>
                      <span className={`badge ${invoice.status === "paid" ? "tone-ok" : invoice.status === "failed" ? "tone-bad" : invoice.status === "pending" ? "tone-warn" : "tone-neutral"}`}>{invoice.status}</span>
                      {invoice.failure_reason && <div className="app-cell-sub" style={{ color: "var(--danger)" }}>{invoice.failure_reason}</div>}
                    </td>
                    <td className="text-muted" style={{ whiteSpace: "nowrap" }}>{formatDate(invoice.paid_at ?? invoice.issued_at, locale)}</td>
                    <td className="app-row-actions">
                      {(invoice.status === "pending" || invoice.status === "failed") && (
                        <button className="btn btn-primary btn-sm" onClick={() => setPayDialog(invoice)}>{t("payNow")}</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {invoices.length === 0 && <EmptyState icon="ph-receipt" title="No invoices yet." />}
        </section>
      </div>

      <PlanDialog open={planDialog} plans={payload.available_plans} initialPlanId={payload.plan?.id ?? null}
        onClose={() => setPlanDialog(false)}
        onSubscribed={async (invoice, message) => {
          toast("Plan changed", message, "ok");
          setPlanDialog(false);
          await refresh();
          load();
          setPayDialog(invoice);
        }} />

      <PayDialog invoice={payDialog} onClose={() => setPayDialog(null)}
        onPaid={async () => { setPayDialog(null); await refresh(); load(); }} />
    </SettingsLayout>
  );
}
