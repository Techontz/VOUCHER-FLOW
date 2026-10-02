"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { Dialog, Field, Spinner } from "@/components/ui";
import type { Invoice, Plan } from "@/lib/types";

/*
 * The two billing steps a company administrator takes — choose a plan
 * (POST /billing/subscribe, which raises an invoice) and pay that invoice
 * (POST /billing/invoices/{id}/pay). Shared by Subscription and by the
 * awaiting-approval screen, so both go through exactly the same calls.
 */

/** Choose a plan and billing cycle; resolves with the invoice the API raised. */
export function PlanDialog({
  open, plans, initialPlanId, onClose, onSubscribed,
}: {
  open: boolean;
  plans: Plan[];
  initialPlanId: number | null;
  onClose: () => void;
  onSubscribed: (invoice: Invoice | null, message: string) => void | Promise<void>;
}) {
  const { t, reportError } = useApp();
  const [selected, setSelected] = useState<number | null>(initialPlanId);
  const [cycle, setCycle] = useState<"monthly" | "annual">("monthly");
  const [busy, setBusy] = useState(false);
  // Follow the current plan until the person picks one themselves.
  const [seen, setSeen] = useState(initialPlanId);
  if (seen !== initialPlanId) { setSeen(initialPlanId); setSelected(initialPlanId); }

  async function confirm() {
    if (!selected) return;
    setBusy(true);
    try {
      const res = await api.post<{ invoice: Invoice | null; message: string }>("/billing/subscribe", { plan_id: selected, billing_cycle: cycle });
      await onSubscribed(res.invoice ?? null, res.message);
    } catch (err) {
      reportError(err, "Could not change the plan");
    } finally { setBusy(false); }
  }

  return (
    <Dialog open={open} title={t("changePlan")} onClose={onClose} wide busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("cancel")}</button>
        <button className="btn btn-primary" onClick={confirm} disabled={busy || !selected}>
          {busy ? <Spinner /> : t("confirm")}
        </button>
      </>}>
      <div style={{ display: "grid", gap: "var(--space-2)" }}>
        {plans.map((plan) => (
          <label key={plan.id} style={{
            display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer",
            border: `1px solid ${selected === plan.id ? "var(--color-accent-500)" : "var(--color-divider)"}`,
            background: selected === plan.id ? "var(--color-accent-100)" : "transparent",
            borderRadius: "var(--radius-md)", padding: "10px var(--space-3)",
          }}>
            <input type="radio" name="plan" checked={selected === plan.id} onChange={() => setSelected(plan.id)} style={{ marginTop: 4 }} />
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
  );
}

/** Pay one invoice by mobile money, card or bank transfer. */
export function PayDialog({
  invoice, onClose, onPaid,
}: {
  invoice: Invoice | null;
  onClose: () => void;
  onPaid: (invoice: Invoice) => void | Promise<void>;
}) {
  const { t, toast, reportError } = useApp();
  const [method, setMethod] = useState<"mobile_money" | "card" | "bank_transfer">("mobile_money");
  const [reference, setReference] = useState("");
  const [busy, setBusy] = useState(false);

  async function pay() {
    if (!invoice) return;
    setBusy(true);
    try {
      const res = await api.post<{ invoice: Invoice; message: string }>(`/billing/invoices/${invoice.id}/pay`, {
        method, reference: reference || undefined,
      });
      toast("Payment successful", `${res.invoice.amount_text} · receipt ${res.invoice.provider_ref}`, "ok");
      setReference("");
      await onPaid(res.invoice);
    } catch (err) {
      reportError(err, "The payment did not go through");
    } finally { setBusy(false); }
  }

  return (
    <Dialog open={invoice !== null} title={t("payNow")} onClose={onClose} busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("cancel")}</button>
        <button className="btn btn-primary" onClick={pay} disabled={busy || (method !== "bank_transfer" && !reference)}>
          {busy ? <Spinner /> : `${t("payNow")} ${invoice?.amount_text ?? ""}`}
        </button>
      </>}>
      {invoice && (
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <div style={{ fontSize: 14.5 }}>{invoice.number} · {invoice.description}</div>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 26, fontVariantNumeric: "tabular-nums" }}>
            {invoice.amount_text}
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
  );
}
