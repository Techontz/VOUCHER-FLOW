"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, money } from "@/lib/format";
import {
  Dialog, ErrorState, Field, Icon, LoadingBlock, PageHeader, SectionTitle, Spinner, StatBlock, StatGrid,
} from "@/components/ui";
import type { Company, Invoice, Plan, Subscription, Usage, User } from "@/lib/types";

interface Detail {
  data: Company;
  usage: Usage;
  subscription: Subscription | null;
  invoices: Invoice[];
  admins: User[];
  vouchers: { total: number; pending: number; approved: number; rejected: number; value: number };
}

export default function PlatformCompanyPage() {
  const params = useParams<{ id: string }>();
  const { t, locale, toast, reportError } = useApp();
  const [detail, setDetail] = useState<Detail | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [planDialog, setPlanDialog] = useState(false);
  const [planId, setPlanId] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.get<Detail>(`/platform/companies/${params.id}`)
      .then((d) => { setDetail(d); setPlanId(d.data.plan_id); })
      .catch((err) => setError(err.message));
  }, [params.id]);

  useEffect(() => {
    load();
    api.get<{ data: Plan[] }>("/platform/plans").then((r) => setPlans(r.data)).catch(() => undefined);
  }, [load, locale]);

  async function changePlan() {
    if (!planId || !detail) return;
    setBusy(true);
    try {
      const res = await api.post<{ message: string }>(`/platform/companies/${detail.data.id}/change-plan`, { plan_id: planId });
      toast("Plan changed", res.message, "ok");
      setPlanDialog(false);
      load();
    } catch (err) { reportError(err, "Could not change the plan"); }
    finally { setBusy(false); }
  }

  async function setStatus(action: "suspend" | "activate") {
    if (!detail) return;
    try {
      await api.post(`/platform/companies/${detail.data.id}/${action}`);
      toast(action === "suspend" ? "Company suspended" : "Company activated", detail.data.name, action === "suspend" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!detail) return <LoadingBlock rows={6} />;

  const c = detail.data;

  return (
    <div className="app-page">
      <Link className="vf-back" href="/platform/companies">
        <Icon name="ph-arrow-left" size={14} /> {t("companies")}
      </Link>

      <PageHeader kicker={c.plan?.name ?? "No plan"} title={c.name}
        sub={[c.email, c.phone, c.address].filter(Boolean).join(" · ")}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setPlanDialog(true)}>{t("changePlan")}</button>
            {c.status === "suspended"
              ? <button className="btn btn-primary" onClick={() => setStatus("activate")}>{t("activate")}</button>
              : <button className="btn btn-secondary btn-danger" onClick={() => setStatus("suspend")}>{t("suspend")}</button>}
          </>
        } />

      <div style={{ marginBottom: "var(--space-8)" }}>
        <StatGrid>
          <StatBlock label={t("status")} value={c.status} sub={c.plan?.name ?? "—"} />
          <StatBlock label={t("users")} value={String(detail.usage.users.used)} sub={detail.usage.users.unlimited ? "unlimited" : `of ${detail.usage.users.limit}`} />
          <StatBlock label={t("vouchers")} value={String(detail.vouchers.total)} sub={`${detail.vouchers.pending} pending`} />
          <StatBlock label="Approved value" value={money(detail.vouchers.value, c.currency)} sub={`${detail.vouchers.approved} approved`} />
          <StatBlock label={c.status === "trial" ? t("trialEnds") : t("renewsOn")}
            value={formatDate(c.status === "trial" ? c.trial_ends_at : c.current_period_end, locale)}
            sub={c.days_remaining !== null ? `${c.days_remaining} days` : ""} />
          <StatBlock label="Storage" value={`${detail.usage.storage.used} MB`}
            sub={detail.usage.storage.unlimited ? "unlimited" : `of ${detail.usage.storage.limit} MB`} />
        </StatGrid>
      </div>

      <div className="vf-split">
        <section>
          <SectionTitle>{t("invoices")}</SectionTitle>
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>{t("invoice")}</th><th style={{ textAlign: "right" }}>{t("amount")}</th><th>{t("status")}</th><th>{t("date")}</th></tr></thead>
              <tbody>
                {detail.invoices.map((invoice) => (
                  <tr key={invoice.id}>
                    <td style={{ fontVariantNumeric: "tabular-nums" }}>{invoice.number}</td>
                    <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{invoice.amount_text}</td>
                    <td><span className={`badge ${invoice.status_tag}`}>{invoice.status}</span></td>
                    <td style={{ whiteSpace: "nowrap" }}>{formatDate(invoice.paid_at ?? invoice.issued_at, locale)}</td>
                  </tr>
                ))}
                {detail.invoices.length === 0 && (
                  <tr><td colSpan={4} style={{ color: "var(--color-neutral-600)", textAlign: "center", padding: "var(--space-4)" }}>No invoices.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <SectionTitle>Administrators</SectionTitle>
          <div style={{ display: "grid", gap: 4 }}>
            {detail.admins.map((admin) => (
              <div key={admin.id} style={{
                display: "flex", alignItems: "center", gap: "var(--space-3)",
                border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-2) var(--space-3)",
              }}>
                <span style={{ width: 28, height: 28, borderRadius: "50%", background: "var(--color-accent-200)", color: "var(--color-accent-800)", display: "grid", placeItems: "center", fontSize: 11.5, fontWeight: 600 }}>
                  {admin.initials}
                </span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14.5, fontWeight: 500 }}>{admin.name}</div>
                  <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)" }}>{admin.email}</div>
                </div>
                <span className={`badge ${admin.status === "active" ? "tag-accent" : "tag-neutral"}`}>{admin.status}</span>
              </div>
            ))}
          </div>
        </section>
      </div>

      <Dialog open={planDialog} title={t("changePlan")} onClose={() => setPlanDialog(false)}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setPlanDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={changePlan} disabled={busy || !planId}>{busy ? <Spinner /> : t("confirm")}</button>
        </>}>
        <Field label={t("plan")} htmlFor="pc-plan">
          <select id="pc-plan" className="input" value={planId ?? ""} onChange={(e) => setPlanId(Number(e.target.value))}>
            {plans.map((plan) => (
              <option key={plan.id} value={plan.id}>
                {plan.name} — {plan.price > 0 ? money(plan.price, plan.currency) : "Custom"}
              </option>
            ))}
          </select>
        </Field>
        <div style={{ fontSize: 13.5, color: "var(--color-neutral-600)" }}>
          The tenant is moved immediately and a new billing period starts. No payment is taken here.
        </div>
      </Dialog>
    </div>
  );
}
