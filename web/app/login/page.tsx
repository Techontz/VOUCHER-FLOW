"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";

/**
 * Whether to offer the seeded demo accounts.
 *
 * Off on a real deployment. These are working credentials for a live database,
 * and a public site should not print them beside a sign-in box — least of all
 * the company administrator's.
 *
 * Both tests are written against `process.env` directly, rather than through
 * the exported API_MODE, and both read variables that are ALWAYS defined:
 * NODE_ENV is set by every build, and NEXT_PUBLIC_API_MODE is required for the
 * app to run at all. That matters more than it looks. The bundler only
 * substitutes environment variables it can see, so a condition resting on an
 * optional flag stays a runtime lookup and cannot fold — the panel survives
 * in the bundle, hidden but readable by anyone who opens the JS. Resting it on
 * two guaranteed values folds the whole expression to `false`, and the panel,
 * the account list and the shared password are dropped from the output.
 *
 *   next dev                → shown
 *   any build in mock mode  → shown; the fixture has no real accounts, and it
 *                             carries the same password in lib/mock/ anyway
 *   production + live       → hidden, and not present
 *
 * A live demo tenant that genuinely wants these shortcuts should add its own
 * condition here rather than an env flag, so the fold is preserved.
 */
const SHOW_DEMO_ACCOUNTS =
  process.env.NODE_ENV !== "production"
  || process.env.NEXT_PUBLIC_API_MODE !== "live";

/**
 * Seeded accounts, offered so the whole workflow can be walked through
 * immediately — one per step of the default route, plus the two admin scopes.
 *
 * Referenced only by <DemoAccounts>, which is only rendered when
 * SHOW_DEMO_ACCOUNTS holds — so when that folds to false this becomes
 * unreachable and goes with it.
 */
const DEMO_PASSWORD = "Password123!";

const DEMO = [
  { label: "Employee", person: "Frank Kessy", email: "frank@watercom.test", icon: "ph-user", note: "raises vouchers, sees only their own" },
  { label: "HOD", person: "Joseph Mrisho", email: "joseph@watercom.test", icon: "ph-signature", note: "reviews and signs — never approves" },
  { label: "Managing Director", person: "Emmanuel Massawe", email: "emmanuel@watercom.test", icon: "ph-seal-check", note: "approves or rejects — the final decision" },
  { label: "Cashier", person: "Mwajuma Hamisi", email: "mwajuma@watercom.test", icon: "ph-wallet", note: "releases the funds and records the reference" },
  { label: "Company Admin", person: "Neema Shirima", email: "admin@watercom.test", icon: "ph-buildings", note: "runs Watercom (T) Limited" },
  { label: "Super Admin", person: "Grace Kimaro", email: "super@vouchflow.test", icon: "ph-globe-hemisphere-east", note: "runs the platform" },
];

export default function LoginPage() {
  const router = useRouter();
  const { t, signIn, user, ready } = useApp();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  const pickDemo = (demoEmail: string) => {
    setEmail(demoEmail);
    setPassword(DEMO_PASSWORD);
  };
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
      aside={SHOW_DEMO_ACCOUNTS ? <DemoAccounts selected={email} onPick={pickDemo} /> : undefined}
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

/**
 * The demo sign-in panel. Rendered only where SHOW_DEMO_ACCOUNTS holds.
 *
 * Kept as a separate component so the account list and the shared password are
 * reachable from exactly one place: when the flag folds away at build time,
 * this function loses its only caller and the bundler drops it, the accounts
 * and the password together.
 */
function DemoAccounts({ selected, onPick }: { selected: string; onPick: (email: string) => void }) {
  const { t } = useApp();

  return (
    <div className="vf-panel" style={{ padding: "var(--space-4)" }}>
      <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
        {t("demoSignInAs")}
      </div>
      <div style={{ display: "grid", gap: 6 }}>
        {DEMO.map((account) => (
          <button
            key={account.email}
            type="button"
            aria-pressed={selected === account.email}
            onClick={() => onPick(account.email)}
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
        Every demo account uses the same password; choosing one fills it in.
      </div>
    </div>
  );
}
