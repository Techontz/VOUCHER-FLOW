"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime, money } from "@/lib/format";
import {
  Banner, Dialog, ErrorState, Field, Icon, LoadingBlock, PageHeader, SectionTitle, Spinner, StatBlock, StatGrid,
} from "@/components/ui";
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
  const [selectedPlan, setSelectedPlan] = useState<number | null>(null);
  const [cycle, setCycle] = useState<"monthly" | "annual">("monthly");
  const [method, setMethod] = useState<"mobile_money" | "card" | "bank_transfer">("mobile_money");
  const [reference, setReference] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.get<Payload>("/billing/subscription")
      .then((data) => { setPayload(data); setSelectedPlan(data.plan?.id ?? null); })
      .catch((err) => setError(err.message));
    api.get<Paginated<Invoice>>("/billing/invoices", { per_page: 20 })
      .then((r) => setInvoices(r.data)).catch(() => setInvoices([]));
  }, []);

  useEffect(load, [load, locale]);

  async function changePlan() {
    if (!selectedPlan) return;
    setBusy(true);
    try {
      const res = await api.post<{ invoice: Invoice; message: string }>("/billing/subscribe", { plan_id: selectedPlan, billing_cycle: cycle });
      toast("Plan changed", res.message, "ok");
      setPlanDialog(false);
      await refresh();
      load();
      setPayDialog(res.invoice);
    } catch (err) {
      reportError(err, "Could not change the plan");
    } finally { setBusy(false); }
  }

  async function pay() {
    if (!payDialog) return;
    setBusy(true);
    try {
      const res = await api.post<{ invoice: Invoice; message: string }>(`/billing/invoices/${payDialog.id}/pay`, {
        method, reference: reference || undefined,
      });
      toast("Payment successful", `${res.invoice.amount_text} · receipt ${res.invoice.provider_ref}`, "ok");
      setPayDialog(null);
      setReference("");
      await refresh();
      load();
    } catch (err) {
      reportError(err, "The payment did not go through");
    } finally { setBusy(false); }
  }

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
    <div style={{ maxWidth: 1080 }}>
      <PageHeader kicker={t("subscription")} title={payload.plan?.name ?? "No plan"}
        sub={payload.subscription
          ? `${payload.subscription.billing_cycle === "annual" ? "Annual" : "Monthly"} · ${money(payload.subscription.amount, payload.subscription.currency)}`
          : undefined}
        actions={<button className="btn btn-primary" onClick={() => setPlanDialog(true)}><Icon name="ph-crown-simple" size={15} /> {t("changePlan")}</button>} />

      {payload.is_expired && (
        <Banner tone="danger" icon="ph-warning-circle" title={t("expired")}>{t("expiredBody")}</Banner>
      )}

      {!payload.is_expired && company.status === "trial" && (
        <Banner tone="warn" icon="ph-clock" title={`${t("trialEnds")} ${formatDate(company.trial_ends_at, locale)}`}>
          {payload.days_remaining} days remaining.
        </Banner>
      )}

      <section style={{ marginBottom: "var(--space-8)" }}>
        <SectionTitle>{t("usageThisPeriod")}</SectionTitle>
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          {metrics.map((metric) => (
            <div key={metric.label}>
              <div style={{ display: "flex", gap: "var(--space-2)", fontSize: 14.5, alignItems: "baseline" }}>
                <span style={{ flex: 1 }}>{metric.label}</span>
                <span style={{ fontVariantNumeric: "tabular-nums", color: metric.exceeded ? "var(--color-accent-2-700)" : "var(--color-neutral-700)" }}>
                  {metric.used.toLocaleString()}{metric.unit && ` ${metric.unit}`} {t("of")} {metric.unlimited ? "unlimited" : `${metric.limit?.toLocaleString()}${metric.unit ? ` ${metric.unit}` : ""}`}
                </span>
              </div>
              <div style={{ height: 6, background: "var(--color-neutral-200)", marginTop: 4 }}>
                <div style={{
                  height: "100%", width: `${metric.percent ?? 4}%`,
                  background: metric.exceeded ? "var(--color-accent-2-500)" : "var(--color-accent-500)",
                }} />
              </div>
            </div>
          ))}
        </div>
      </section>

      <section style={{ marginBottom: "var(--space-8)" }}>
        <StatGrid>
          <StatBlock label={t("currentPlan")} value={payload.plan?.name ?? "—"} sub={company.status} />
          <StatBlock label={company.status === "trial" ? t("trialEnds") : t("renewsOn")}
            value={formatDate(company.status === "trial" ? company.trial_ends_at : company.current_period_end, locale)}
            sub={payload.days_remaining !== null ? `${payload.days_remaining} days` : ""} />
          <StatBlock label={t("seats")} value={`${usage.users.used} / ${usage.users.unlimited ? "∞" : usage.users.limit}`} sub={t("seatsUsed")} />
        </StatGrid>
        <label className="switch" style={{ marginTop: "var(--space-4)" }}>
          <input type="checkbox" checked={payload.auto_renew} onChange={(e) => toggleAutoRenew(e.target.checked)} />
          <span className="track" />
          {t("autoRenew")}
        </label>
      </section>

      <section>
        <SectionTitle>{t("billingHistory")}</SectionTitle>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr><th>{t("invoice")}</th><th>{t("plan")}</th><th style={{ textAlign: "right" }}>{t("amount")}</th>
                <th>{t("method")}</th><th>{t("status")}</th><th>{t("date")}</th><th /></tr>
            </thead>
            <tbody>
              {invoices.map((invoice) => (
                <tr key={invoice.id}>
                  <td style={{ fontVariantNumeric: "tabular-nums" }}>{invoice.number}</td>
                  <td>{invoice.description}</td>
                  <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{invoice.amount_text}</td>
                  <td>{invoice.method_label}</td>
                  <td>
                    <span className={`tag ${invoice.status_tag}`}>{invoice.status}</span>
                    {invoice.failure_reason && <div style={{ fontSize: 12, color: "var(--color-accent-2-700)" }}>{invoice.failure_reason}</div>}
                  </td>
                  <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>
                    {formatDate(invoice.paid_at ?? invoice.issued_at, locale)}
                  </td>
                  <td style={{ textAlign: "right" }}>
                    {(invoice.status === "pending" || invoice.status === "failed") && (
                      <button className="btn btn-primary btn-sm" onClick={() => setPayDialog(invoice)}>{t("payNow")}</button>
                    )}
                  </td>
                </tr>
              ))}
              {invoices.length === 0 && (
                <tr><td colSpan={7} style={{ textAlign: "center", color: "var(--color-neutral-600)", padding: "var(--space-6)" }}>
                  No invoices yet.
                </td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <Dialog open={planDialog} title={t("changePlan")} onClose={() => setPlanDialog(false)} wide
        actions={<>
          <button className="btn btn-secondary" onClick={() => setPlanDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={changePlan} disabled={busy || !selectedPlan}>
            {busy ? <Spinner /> : t("confirm")}
          </button>
        </>}>
        <div style={{ display: "grid", gap: "var(--space-2)" }}>
          {payload.available_plans.map((plan) => (
            <label key={plan.id} style={{
              display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer",
              border: `1px solid ${selectedPlan === plan.id ? "var(--color-accent-500)" : "var(--color-divider)"}`,
              background: selectedPlan === plan.id ? "var(--color-accent-100)" : "transparent",
              borderRadius: "var(--radius-md)", padding: "10px var(--space-3)",
            }}>
              <input type="radio" name="plan" checked={selectedPlan === plan.id} onChange={() => setSelectedPlan(plan.id)} style={{ marginTop: 4 }} />
              <span style={{ flex: 1 }}>
                <span style={{ display: "block", fontWeight: 600 }}>
                  {plan.name} — {plan.price > 0 ? money(plan.price, plan.currency) : "Custom"}
                  {plan.price > 0 && <span style={{ fontWeight: 400, color: "var(--color-neutral-600)" }}> {t("perMonthShort")}</span>}
                </span>
                <span style={{ display: "block", fontSize: 13.5, color: "var(--color-neutral-700)" }}>
                  {plan.max_users ?? "Unlimited"} users · {plan.max_vouchers_per_month ?? "Unlimited"} vouchers/month · {plan.max_approval_levels ?? "Unlimited"} approval levels
                </span>
              </span>
            </label>
          ))}
          <Field label="Billing cycle" htmlFor="cycle" hint="Annual billing is charged at ten months">
            <select id="cycle" className="input" value={cycle} onChange={(e) => setCycle(e.target.value as "monthly" | "annual")}>
              <option value="monthly">Monthly</option>
              <option value="annual">Annual</option>
            </select>
          </Field>
        </div>
      </Dialog>

      <Dialog open={payDialog !== null} title={t("payNow")} onClose={() => setPayDialog(null)}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setPayDialog(null)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={pay} disabled={busy || (method !== "bank_transfer" && !reference)}>
            {busy ? <Spinner /> : `${t("payNow")} ${payDialog?.amount_text ?? ""}`}
          </button>
        </>}>
        {payDialog && (
          <div style={{ display: "grid", gap: "var(--space-3)" }}>
            <div style={{ fontSize: 14.5 }}>{payDialog.number} · {payDialog.description}</div>
            <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 26, fontVariantNumeric: "tabular-nums" }}>
              {payDialog.amount_text}
            </div>
            <Field label={t("method")} htmlFor="pay-method">
              <select id="pay-method" className="input" value={method} onChange={(e) => setMethod(e.target.value as typeof method)}>
                <option value="mobile_money">{t("mobileMoney")}</option>
                <option value="card">{t("card")}</option>
                <option value="bank_transfer">{t("bankTransfer")}</option>
              </select>
            </Field>
            {method !== "bank_transfer" && (
              <Field label={method === "mobile_money" ? t("payMobilePrompt") : t("cardNumber")} htmlFor="pay-ref" required
                hint="Sandbox: any reference ending 0000 is declined, so the failure path is testable.">
                <input id="pay-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)}
                  placeholder={method === "mobile_money" ? "255712418226" : "4111 1111 1111 1111"} required />
              </Field>
            )}
            {method === "bank_transfer" && (
              <div style={{ fontSize: 14, color: "var(--color-neutral-700)" }}>
                The invoice is marked settled once the transfer is confirmed.
              </div>
            )}
          </div>
        )}
      </Dialog>
    </div>
  );
}
