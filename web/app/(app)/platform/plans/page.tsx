"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { Dialog, ErrorState, Field, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import type { Plan } from "@/lib/types";

const blank = {
  code: "", name: "", blurb: "", price: 0, currency: "TZS", billing_cycle: "monthly",
  max_users: "", max_vouchers_per_month: "", max_departments: "", max_approval_levels: "",
  storage_mb: "", trial_days: 14, is_active: true, is_public: true, sort_order: 0,
};

export default function PlatformPlansPage() {
  const { t, toast, reportError } = useApp();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState(false);
  const [editing, setEditing] = useState<Plan | null>(null);
  const [form, setForm] = useState<typeof blank>(blank);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Plan[] }>("/platform/plans").then((r) => setPlans(r.data)).catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  function openCreate() { setEditing(null); setForm(blank); setFormError(null); setDialog(true); }

  function openEdit(plan: Plan) {
    setEditing(plan);
    setForm({
      code: plan.code, name: plan.name, blurb: plan.blurb ?? "", price: plan.price, currency: plan.currency,
      billing_cycle: plan.billing_cycle,
      max_users: plan.max_users?.toString() ?? "", max_vouchers_per_month: plan.max_vouchers_per_month?.toString() ?? "",
      max_departments: plan.max_departments?.toString() ?? "", max_approval_levels: plan.max_approval_levels?.toString() ?? "",
      storage_mb: plan.storage_mb?.toString() ?? "", trial_days: plan.trial_days,
      is_active: plan.is_active, is_public: plan.is_public, sort_order: plan.sort_order,
    });
    setFormError(null);
    setDialog(true);
  }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const nullable = (v: string) => (v === "" ? null : Number(v));
      const payload = {
        ...form,
        price: Number(form.price),
        max_users: nullable(form.max_users),
        max_vouchers_per_month: nullable(form.max_vouchers_per_month),
        max_departments: nullable(form.max_departments),
        max_approval_levels: nullable(form.max_approval_levels),
        storage_mb: nullable(form.storage_mb),
      };
      if (editing) await api.put(`/platform/plans/${editing.id}`, payload);
      else await api.post("/platform/plans", payload);
      toast(editing ? "Plan updated" : "Plan created", form.name, "ok");
      setDialog(false); load();
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the plan");
    } finally { setBusy(false); }
  }

  const set = (key: keyof typeof blank) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.type === "checkbox" ? (e.target as HTMLInputElement).checked : e.target.value }));

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!plans) return <LoadingBlock rows={5} />;

  return (
    <div className="app-page">
      <PageHeader kicker="Platform" title={t("plansSubs")}
        sub="Limits defined here are enforced across every tenant on the plan."
        actions={<button className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={15} /> {t("add")}</button>} />

      <div className="table-wrap app-framed">
        <table className="table">
          <thead>
            <tr><th>{t("plan")}</th><th style={{ textAlign: "right" }}>{t("price")}</th><th>Cycle</th>
              <th style={{ textAlign: "right" }}>Users</th><th style={{ textAlign: "right" }}>Vouchers/mo</th>
              <th style={{ textAlign: "right" }}>Levels</th><th style={{ textAlign: "right" }}>Storage</th>
              <th style={{ textAlign: "right" }}>Companies</th><th>{t("status")}</th><th /></tr>
          </thead>
          <tbody>
            {plans.map((plan) => (
              <tr key={plan.id}>
                <td>
                  <span style={{ fontWeight: 500 }}>{plan.name}</span>
                  <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{plan.code}</span>
                </td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                  {plan.price > 0 ? money(plan.price, plan.currency) : "Custom"}
                </td>
                <td>{plan.billing_cycle}</td>
                <td style={{ textAlign: "right" }}>{plan.max_users ?? "∞"}</td>
                <td style={{ textAlign: "right" }}>{plan.max_vouchers_per_month ?? "∞"}</td>
                <td style={{ textAlign: "right" }}>{plan.max_approval_levels ?? "∞"}</td>
                <td style={{ textAlign: "right" }}>{plan.storage_mb ? `${plan.storage_mb} MB` : "∞"}</td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{plan.companies_count ?? 0}</td>
                <td><span className={`badge ${plan.is_active ? "tag-accent" : "tag-neutral"}`}>{plan.is_active ? t("active") : "Inactive"}</span></td>
                <td style={{ textAlign: "right" }}>
                  <button className="btn btn-ghost btn-sm" onClick={() => openEdit(plan)} aria-label={`Edit ${plan.name}`}>
                    <Icon name="ph-pencil-simple" size={14} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Dialog open={dialog} title={editing ? `${t("edit")} — ${editing.name}` : t("add")} onClose={() => setDialog(false)} wide
        actions={<>
          <button className="btn btn-secondary" onClick={() => setDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || !form.code}>{busy ? <Spinner /> : t("save")}</button>
        </>}>
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Name" htmlFor="pl-name" error={formError?.field("name")} required>
              <input id="pl-name" className="input" value={form.name} onChange={set("name")} required />
            </Field>
            <Field label="Code" htmlFor="pl-code" error={formError?.field("code")} required>
              <input id="pl-code" className="input" value={form.code} onChange={set("code")} required />
            </Field>
          </div>
          <Field label="Blurb" htmlFor="pl-blurb"><input id="pl-blurb" className="input" value={form.blurb} onChange={set("blurb")} /></Field>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(130px, 1fr))", gap: "var(--space-3)" }}>
            <Field label={t("price")} htmlFor="pl-price" required>
              <input id="pl-price" className="input" type="number" min={0} value={form.price} onChange={set("price")} required />
            </Field>
            <Field label={t("currency")} htmlFor="pl-currency">
              <select id="pl-currency" className="input" value={form.currency} onChange={set("currency")}>
                <option>TZS</option><option>KES</option><option>USD</option><option>EUR</option>
              </select>
            </Field>
            <Field label="Cycle" htmlFor="pl-cycle">
              <select id="pl-cycle" className="input" value={form.billing_cycle} onChange={set("billing_cycle")}>
                <option value="monthly">Monthly</option><option value="annual">Annual</option>
              </select>
            </Field>
            <Field label="Trial days" htmlFor="pl-trial">
              <input id="pl-trial" className="input" type="number" min={0} value={form.trial_days} onChange={set("trial_days")} />
            </Field>
          </div>
          <div style={{ fontSize: 12, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
            Limits — leave blank for unlimited
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(130px, 1fr))", gap: "var(--space-3)" }}>
            <Field label="Max users" htmlFor="pl-users"><input id="pl-users" className="input" type="number" min={1} value={form.max_users} onChange={set("max_users")} placeholder="∞" /></Field>
            <Field label="Vouchers / month" htmlFor="pl-vouchers"><input id="pl-vouchers" className="input" type="number" min={1} value={form.max_vouchers_per_month} onChange={set("max_vouchers_per_month")} placeholder="∞" /></Field>
            <Field label="Departments" htmlFor="pl-depts"><input id="pl-depts" className="input" type="number" min={1} value={form.max_departments} onChange={set("max_departments")} placeholder="∞" /></Field>
            <Field label="Approval levels" htmlFor="pl-levels"><input id="pl-levels" className="input" type="number" min={1} value={form.max_approval_levels} onChange={set("max_approval_levels")} placeholder="∞" /></Field>
            <Field label="Storage (MB)" htmlFor="pl-storage"><input id="pl-storage" className="input" type="number" min={1} value={form.storage_mb} onChange={set("storage_mb")} placeholder="∞" /></Field>
          </div>
          <div style={{ display: "flex", gap: "var(--space-4)", flexWrap: "wrap" }}>
            <label className="radio"><input type="checkbox" checked={form.is_active} onChange={set("is_active")} /><span className="dot" />Active</label>
            <label className="radio"><input type="checkbox" checked={form.is_public} onChange={set("is_public")} /><span className="dot" />Shown on pricing page</label>
          </div>
        </div>
      </Dialog>
    </div>
  );
}
