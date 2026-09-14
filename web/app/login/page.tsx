"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { LoginBrand } from "@/components/login-brand";
import { Icon, LanguageToggle, Spinner, ThemeToggle } from "@/components/ui";

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
  const [reveal, setReveal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);

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
      setDone(true);
      router.push("/dashboard");
    } catch (err) {
      setError(err as Error);
      setBusy(false);
    }
  }

  const fieldError = (name: string) => (error instanceof ApiError ? error.field(name) : undefined);
  const emailError = fieldError("email");
  const passwordError = fieldError("password");

  return (
    <div className="vf-login">
      <LoginBrand />

      <main className="vf-login-panel">
        <div className="vf-login-tools">
          <LanguageToggle />
          <ThemeToggle />
        </div>

        <div className="vf-login-body">
          <header className="vf-login-head">
            <h1>{t("loginWelcome")}</h1>
            <p>{t("loginSub")}</p>
          </header>

          <form onSubmit={submit} className="vf-login-form" noValidate aria-busy={busy}>
            {error && !emailError && !passwordError && (
              <div role="alert" className="vf-alert tone-bad vf-login-alert">
                <Icon name="ph-warning-circle" size={20} style={{ flex: "none" }} />
                <div className="vf-alert-text">{error.message}</div>
              </div>
            )}

            {done && (
              <div role="status" className="vf-alert tone-ok vf-login-alert">
                <Icon name="ph-check-circle" size={20} style={{ flex: "none" }} />
                <div className="vf-alert-text">{t("signedInOpening")}</div>
              </div>
            )}

            <div className="field">
              <label htmlFor="email">{t("emailAddress")}</label>
              <input
                id="email" type="email" inputMode="email" className="input vf-login-input" value={email}
                autoComplete="username" autoCapitalize="none" spellCheck={false} required
                aria-invalid={!!emailError} aria-describedby={emailError ? "email-error" : undefined}
                onChange={(e) => setEmail(e.target.value)} placeholder={t("emailPh")}
              />
              {emailError && (
                <div className="field-error" id="email-error"><Icon name="ph-warning-circle" size={15} /> {emailError}</div>
              )}
            </div>

            <div className="field">
              <div className="vf-login-label-row">
                <label htmlFor="password">{t("password")}</label>
                <Link href="/verify?purpose=password_reset">{t("forgotPassword")}</Link>
              </div>
              <div className="vf-login-password">
                <input
                  id="password" className="input vf-login-input" type={reveal ? "text" : "password"} value={password}
                  autoComplete="current-password" required
                  aria-invalid={!!passwordError} aria-describedby={passwordError ? "password-error" : undefined}
                  onChange={(e) => setPassword(e.target.value)} placeholder={t("passwordPh")}
                />
                <button
                  type="button" className="vf-login-reveal" onClick={() => setReveal((v) => !v)}
                  aria-label={reveal ? t("hidePassword") : t("showPassword")} aria-pressed={reveal}
                  title={reveal ? t("hidePassword") : t("showPassword")}
                >
                  <Icon name={reveal ? "ph-eye-slash" : "ph-eye"} size={19} />
                </button>
              </div>
              {passwordError && (
                <div className="field-error" id="password-error"><Icon name="ph-warning-circle" size={15} /> {passwordError}</div>
              )}
            </div>

            <label className="radio vf-login-remember">
              <input type="checkbox" defaultChecked />
              <span className="dot" />
              {t("rememberMe")}
            </label>

            <button className="btn btn-primary btn-lg vf-login-submit" disabled={busy} type="submit">
              {done ? (
                <><Icon name="ph-check" size={18} /> {t("signIn")}</>
              ) : busy ? (
                <Spinner label={t("signingIn")} />
              ) : (
                <>{t("signIn")} <Icon name="ph-arrow-right" size={18} /></>
              )}
            </button>
          </form>

          <div className="vf-login-alt">
            <p>{t("newToVouchflow")} <Link href="/register">{t("registerCompany")}</Link></p>
            <p className="vf-login-alt-note">{t("staffAccountsNote")}</p>
          </div>

          {SHOW_DEMO_ACCOUNTS && <DemoAccounts selected={email} onPick={pickDemo} />}
        </div>

        <footer className="vf-login-foot">
          <Icon name="ph-shield-check" size={15} />
          <span><strong>VouchFlow</strong> · {t("loginFooter")}</span>
        </footer>
      </main>
    </div>
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
    <div className="vf-panel vf-login-demo">
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
