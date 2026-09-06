"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";
import { money } from "@/lib/format";
import type { Company, Plan, User } from "@/lib/types";

export default function RegisterPage() {
  const router = useRouter();
  const { t, applySession, toast } = useApp();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [planCode, setPlanCode] = useState("business");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  const [form, setForm] = useState({
    company_name: "", business_email: "", phone: "", address: "", country: "TZ", currency: "TZS",
    name: "", email: "", password: "", password_confirmation: "",
  });

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<{
        token: string; user: User; company: Company;
        otp: { code: string | null; identifier: string };
      }>("/auth/register", { ...form, plan_code: planCode });

      applySession(res.token, res.user, res.company);
      toast("Company created", `${res.company.name} is on a ${res.company.plan?.name ?? ""} trial.`, "ok");

      const code = res.otp?.code ? `&code=${res.otp.code}` : "";
      router.push(`/verify?identifier=${encodeURIComponent(res.otp.identifier)}&purpose=registration&next=onboarding${code}`);
    } catch (err) {
      if (err instanceof ApiError) setError(err);
      setBusy(false);
    }
  }

  const fe = (name: string) => error?.field(name);

  return (
    <AuthFrame
      kicker={t("getStarted")}
      title={t("registerCompany")}
      sub={t("heroNote")}
      footer={<>{t("alreadyRegistered")} <Link href="/login">{t("login")}</Link></>}
      aside={
        <div style={{ border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-4)", background: "var(--color-neutral-100)" }}>
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
            {t("plan")}
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            {plans.filter((p) => p.is_public).map((plan) => (
              <label key={plan.id} style={{
                display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer",
                border: `1px solid ${planCode === plan.code ? "var(--color-accent-500)" : "var(--color-divider)"}`,
                background: planCode === plan.code ? "var(--color-accent-100)" : "transparent",
                borderRadius: "var(--radius-md)", padding: "10px var(--space-3)",
              }}>
                <input
                  type="radio" name="plan" value={plan.code} checked={planCode === plan.code}
                  onChange={() => setPlanCode(plan.code)} style={{ marginTop: 4 }}
                />
                <span style={{ flex: 1 }}>
                  <span style={{ display: "block", fontWeight: 600, fontSize: 15 }}>{plan.label}</span>
                  <span style={{ display: "block", fontSize: 13, color: "var(--color-neutral-700)" }}>
                    {plan.price > 0 ? `${money(plan.price, plan.currency)} ${t("perMonthShort")}` : "Custom pricing"}
                    {" · "}{plan.trial_days}-day trial
                  </span>
                  <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{plan.blurb}</span>
                </span>
              </label>
            ))}
          </div>
        </div>
      }
    >
      <form onSubmit={submit} style={{ display: "grid", gap: "var(--space-3)" }} noValidate>
        {error && Object.keys(error.errors).length === 0 && (
          <div role="alert" style={{ border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)", color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "10px var(--space-3)", fontSize: 14 }}>
            {error.message}
          </div>
        )}

        <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
          {t("companyProfile")}
        </div>
        <Field label={t("companyName")} htmlFor="company_name" error={fe("company_name")} required>
          <input id="company_name" className="input" value={form.company_name} onChange={set("company_name")} required />
        </Field>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-3)" }}>
          <Field label={t("businessEmail")} htmlFor="business_email" error={fe("business_email")} required>
            <input id="business_email" className="input" type="email" value={form.business_email} onChange={set("business_email")} required />
          </Field>
          <Field label={t("phone")} htmlFor="phone" error={fe("phone")}>
            <input id="phone" className="input" value={form.phone} onChange={set("phone")} placeholder="+255 …" />
          </Field>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-3)" }}>
          <Field label={t("country")} htmlFor="country">
            <select id="country" className="input" value={form.country} onChange={set("country")}>
              <option value="TZ">Tanzania</option><option value="KE">Kenya</option>
              <option value="UG">Uganda</option><option value="RW">Rwanda</option><option value="ZA">South Africa</option>
            </select>
          </Field>
          <Field label={t("currency")} htmlFor="currency">
            <select id="currency" className="input" value={form.currency} onChange={set("currency")}>
              <option>TZS</option><option>KES</option><option>USD</option><option>EUR</option>
            </select>
          </Field>
        </div>

        <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginTop: "var(--space-2)" }}>
          {t("createAccount")}
        </div>
        <Field label={t("fullName")} htmlFor="name" error={fe("name")} required>
          <input id="name" className="input" value={form.name} onChange={set("name")} required autoComplete="name" />
        </Field>
        <Field label={t("email")} htmlFor="email" error={fe("email")} required>
          <input id="email" className="input" type="email" value={form.email} onChange={set("email")} required autoComplete="email" />
        </Field>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-3)" }}>
          <Field label={t("password")} htmlFor="password" error={fe("password")} hint="At least 8 characters" required>
            <input id="password" className="input" type="password" value={form.password} onChange={set("password")} required minLength={8} autoComplete="new-password" />
          </Field>
          <Field label={t("confirmPassword")} htmlFor="password_confirmation" required>
            <input id="password_confirmation" className="input" type="password" value={form.password_confirmation} onChange={set("password_confirmation")} required autoComplete="new-password" />
          </Field>
        </div>

        <button className="btn btn-primary btn-block" disabled={busy} type="submit">
          {busy ? <Spinner label={t("loading")} /> : <><Icon name="ph-buildings" size={16} /> {t("createAccount")}</>}
        </button>
      </form>
    </AuthFrame>
  );
}
