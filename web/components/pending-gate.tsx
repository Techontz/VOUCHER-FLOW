"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { AuthFrame } from "@/components/auth-frame";
import { PayDialog, PlanDialog } from "@/components/billing-dialogs";
import { Icon, Spinner } from "@/components/ui";
import type { Company, Invoice, Paginated, Plan, User } from "@/lib/types";

/**
 * What a self-registered company sees until a platform administrator approves
 * it: who it is, the plan it chose, a way to pay for it, and a way to check
 * whether it has been let in. Nothing of the product itself.
 *
 * Only the calls the API still allows a pending company are made here —
 * billing/*, auth/me and logout.
 */

interface Billing { plan: Plan | null; available_plans: Plan[] }

export function PendingGate() {
  const { t, company, locale, refresh, signOut, toast, reportError } = useApp();
  const [billing, setBilling] = useState<Billing | null>(null);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [planDialog, setPlanDialog] = useState(false);
  const [payDialog, setPayDialog] = useState<Invoice | null>(null);
  const [checking, setChecking] = useState(false);
  const [starting, setStarting] = useState(false);

  const load = useCallback(() => {
    api.get<Billing>("/billing/subscription")
      .then((r) => setBilling({ plan: r.plan ?? null, available_plans: r.available_plans ?? [] }))
      .catch(() => setBilling({ plan: null, available_plans: [] }));
    api.get<Paginated<Invoice>>("/billing/invoices", { per_page: 20 })
      .then((r) => setInvoices(r.data)).catch(() => setInvoices([]));
  }, []);

  useEffect(load, [load, locale]);

  const plan = billing?.plan ?? company?.plan ?? null;
  const unpaid = invoices.find((i) => i.status === "pending" || i.status === "failed") ?? null;
  const paid = !unpaid && invoices.some((i) => i.status === "paid");

  async function checkStatus() {
    setChecking(true);
    try {
      const data = await api.get<{ user: User; company: Company | null }>("/auth/me");
      if (data.company?.status === "pending") {
        toast(t("pendingStill"), t("pendingStillSub"), "warn");
        load();
      } else {
        toast(t("pendingApprovedToast"), data.company?.name, "ok");
        // The shell re-renders into the product once the context has the new status.
        await refresh();
      }
    } catch (err) {
      reportError(err);
    } finally { setChecking(false); }
  }

  /** Pay the open invoice, or raise one for the chosen plan first. */
  async function payNow() {
    if (unpaid) { setPayDialog(unpaid); return; }
    if (!plan) { setPlanDialog(true); return; }
    setStarting(true);
    try {
      const res = await api.post<{ invoice: Invoice | null }>("/billing/subscribe", { plan_id: plan.id, billing_cycle: "monthly" });
      load();
      if (res.invoice) setPayDialog(res.invoice);
    } catch (err) {
      reportError(err);
    } finally { setStarting(false); }
  }

  return (
    <AuthFrame
      kicker={t("pendingKicker")}
      title={company?.name ?? "VouchFlow"}
      sub={t("pendingLine")}
      footer={
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => void signOut()}>
          <Icon name="ph-sign-out" size={16} /> {t("signOut")}
        </button>
      }
    >
      <div className="vf-pending">
        <span className="vf-pending-mark" aria-hidden="true"><Icon name="ph-hourglass-medium" size={34} /></span>

        <div className="vf-pending-plan">
          <div className="vf-pending-plan-text">
            <span className="vf-pending-label">{t("plan")}</span>
            <strong>{plan?.name ?? t("pendingNoPlan")}</strong>
          </div>
          {plan && (
            <span className="vf-pending-price tnum">
              {plan.price > 0 ? <>{money(plan.price, plan.currency)} <small>{t("perMonthShort")}</small></> : "—"}
            </span>
          )}
        </div>

        {(unpaid || paid) && (
          <div className={`vf-pending-state ${paid ? "tone-ok" : "tone-warn"}`}>
            <Icon name={paid ? "ph-check-circle" : "ph-receipt"} size={17} />
            <span>{paid ? t("pendingPaid") : `${t("pendingDue")} · ${unpaid?.amount_text ?? ""}`}</span>
          </div>
        )}

        <div className="vf-pending-actions">
          {!paid && (
            <button type="button" className="btn btn-primary btn-lg" onClick={() => void payNow()} disabled={starting || !billing}>
              {starting ? <Spinner /> : <><Icon name="ph-credit-card" size={18} /> {t("payNow")}</>}
            </button>
          )}
          <button type="button" className="btn btn-secondary btn-lg" onClick={() => setPlanDialog(true)}
            disabled={!billing || billing.available_plans.length === 0}>
            <Icon name="ph-crown-simple" size={18} /> {plan ? t("changePlan") : t("pendingChoosePlan")}
          </button>
          <button type="button" className="btn btn-ghost btn-lg" onClick={() => void checkStatus()} disabled={checking}>
            {checking ? <Spinner /> : <><Icon name="ph-arrows-clockwise" size={18} /> {t("pendingCheckStatus")}</>}
          </button>
        </div>
      </div>

      <PlanDialog open={planDialog} plans={billing?.available_plans ?? []} initialPlanId={plan?.id ?? null}
        onClose={() => setPlanDialog(false)}
        onSubscribed={async (invoice) => {
          toast(t("pendingPlanChosen"), undefined, "ok");
          setPlanDialog(false);
          await refresh();
          load();
          setPayDialog(invoice);
        }} />

      <PayDialog invoice={payDialog} onClose={() => setPayDialog(null)}
        onPaid={async () => {
          setPayDialog(null);
          await refresh();
          load();
        }} />
    </AuthFrame>
  );
}
