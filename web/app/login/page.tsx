"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";

/**
 * Seeded accounts, offered so the whole workflow can be walked through
 * immediately — one per step of the default route, plus the two admin scopes.
 */
const DEMO = [
  { label: "Employee", person: "John Mwakyusa", email: "john@acme.test", icon: "ph-user", note: "raises vouchers, sees only their own" },
  { label: "HOD", person: "Asha Mushi", email: "asha@acme.test", icon: "ph-signature", note: "reviews and signs — never approves" },
  { label: "CEO", person: "Daniel Joseph", email: "daniel@acme.test", icon: "ph-seal-check", note: "approves or rejects — the final decision" },
  { label: "Cashier", person: "Fatuma Kalinga", email: "fatuma@acme.test", icon: "ph-wallet", note: "releases the funds and records the reference" },
  { label: "Company Admin", person: "Neema William", email: "admin@acme.test", icon: "ph-buildings", note: "runs Acme Tanzania Ltd" },
  { label: "Super Admin", person: "Grace Kimaro", email: "super@vouchflow.test", icon: "ph-globe-hemisphere-east", note: "runs the platform" },
];

export default function LoginPage() {
  const router = useRouter();
  const { t, signIn, user, ready } = useApp();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | Error | null>(null);

  useEffect(() => {
    if (ready && user) router.replace("/dashboard");
  }, [ready, user, router]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signIn(email, password);
      router.push("/dashboard");
    } catch (err) {
      setError(err as Error);
      setBusy(false);
    }
  }

  const fieldError = (name: string) => (error instanceof ApiError ? error.field(name) : undefined);

  return (
    <AuthFrame
      kicker="VouchFlow"
      title={t("login")}
      sub={t("heroSub")}
      footer={<>{t("noAccountYet")} <Link href="/register">{t("registerCompany")}</Link></>}
      aside={
        <div className="vf-panel" style={{ padding: "var(--space-4)" }}>
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
            {t("demoSignInAs")}
          </div>
          <div style={{ display: "grid", gap: 6 }}>
            {DEMO.map((account) => (
              <button
                key={account.email}
                type="button"
                aria-pressed={email === account.email}
                onClick={() => { setEmail(account.email); setPassword("Password123!"); }}
                className="vf-choice"
                style={{ padding: "10px 12px", borderRadius: 12 }}
              >
                <span className="vf-choice-icon" style={{ width: 30, height: 30 }}>
                  <Icon name={account.icon} size={16} />
                </span>
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: "block", fontWeight: 600, fontSize: 14.5 }}>
                    {account.label} <span style={{ fontWeight: 400, color: "var(--color-neutral-600)" }}>· {account.person}</span>
                  </span>
                  <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{account.note}</span>
                </span>
              </button>
            ))}
          </div>
          <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)", marginTop: "var(--space-3)" }}>
            Password for every demo account: <code>Password123!</code>. This prototype runs on
            local mock data — nothing leaves your browser.
          </div>
        </div>
      }
    >
      <form onSubmit={submit} style={{ display: "grid", gap: "var(--space-3)" }} noValidate>
        {error && !fieldError("email") && (
          <div role="alert" style={{ border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)", color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "10px var(--space-3)", fontSize: 14 }}>
            {error.message}
          </div>
        )}

        <Field label={t("emailOrPhone")} htmlFor="email" error={fieldError("email")} required>
          <input
id="email" type="email" className="input" value={email} autoComplete="username" required
            aria-invalid={!!fieldError("email")}
            onChange={(e) => setEmail(e.target.value)} placeholder="you@company.com"
          />
        </Field>

        <Field label={t("password")} htmlFor="password" error={fieldError("password")} required>
          <input
            id="password" className="input" type="password" value={password} autoComplete="current-password" required
            onChange={(e) => setPassword(e.target.value)} placeholder="••••••••"
          />
        </Field>

        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", flexWrap: "wrap" }}>
          <label className="radio" style={{ fontSize: 14 }}>
            <input type="checkbox" defaultChecked />
            <span className="dot" />
            {t("rememberMe")}
          </label>
          <div style={{ flex: 1 }} />
          <Link href="/verify?purpose=password_reset" style={{ fontSize: 14 }}>{t("forgotPassword")}</Link>
        </div>

        <button className="btn btn-primary btn-block" disabled={busy} type="submit">
          {busy ? <Spinner label={t("loading")} /> : <><Icon name="ph-sign-in" size={16} /> {t("login")}</>}
        </button>
      </form>
    </AuthFrame>
  );
}
