"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthShowcase, VouchFlowMark } from "@/components/login-brand";
import { LoginVerification } from "@/components/login-verification";
import type { LoginChallenge } from "@/lib/types";
import { Icon, LanguageToggle, Spinner, ThemeToggle } from "@/components/ui";

/**
 * Whether to offer the seeded demo accounts.
 *
 * Off on a real deployment. These are working credentials for a live database,
 * and a public site should not print them beside a sign-in box, least of all
 * the company administrator's.
 *
 * Both tests are written against `process.env` directly, rather than through
 * the exported API_MODE, and both read variables that are ALWAYS defined:
 * NODE_ENV is set by every build, and NEXT_PUBLIC_API_MODE is required for the
 * app to run at all. That matters more than it looks. The bundler only
 * substitutes environment variables it can see, so a condition resting on an
 * optional flag stays a runtime lookup and cannot fold, the panel survives
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
 * immediately, one per step of the default route, plus the two admin scopes.
 *
 * Referenced only by <DemoAccounts>, which is only rendered when
 * SHOW_DEMO_ACCOUNTS holds, so when that folds to false this becomes
 * unreachable and goes with it.
 */
const DEMO_PASSWORD = "Password123!";

const DEMO = [
  { label: "Employee", person: "Frank Kessy", email: "frank@watercom.test", icon: "ph-user", note: "raises vouchers, sees only their own" },
  { label: "HOD", person: "Joseph Mrisho", email: "joseph@watercom.test", icon: "ph-signature", note: "reviews and signs, never approves" },
  { label: "Managing Director", person: "Emmanuel Massawe", email: "emmanuel@watercom.test", icon: "ph-seal-check", note: "approves or rejects, the final decision" },
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
  /** Set when the password was right but a one-time code is still required. */
  const [challenge, setChallenge] = useState<LoginChallenge | null>(null);

  const pickDemo = (demoEmail: string) => {
    setEmail(demoEmail);
    setPassword(DEMO_PASSWORD);
  };
  const [error, setError] = useState<ApiError | Error | null>(null);

  useEffect(() => {
    if (ready && user) router.replace("/home");
  }, [ready, user, router]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const result = await signIn(email, password);
      if (result.status === "verify") {
        setChallenge(result.challenge);
        setBusy(false);
        return;
      }
      setDone(true);
      router.push("/home");
    } catch (err) {
      setError(err as Error);
      setBusy(false);
    }
  }

  const fieldError = (name: string) => (error instanceof ApiError ? error.field(name) : undefined);
  const emailError = fieldError("email");
  const passwordError = fieldError("password");

  return (
    <div className="au au-split">
      <AuthShowcase />

      <main className="au-panel">
        <header className="au-panel-bar">
          <span className="au-mobile-brand"><VouchFlowMark size={30} /><span>VouchFlow</span></span>
          <div className="au-tools">
            <LanguageToggle />
            <ThemeToggle />
          </div>
        </header>

        {challenge ? (
          <div className="au-body vf-login-body" key="verify">
            <LoginVerification
              challenge={challenge}
              showDemoHint={process.env.NEXT_PUBLIC_API_MODE !== "live"}
              onVerified={() => {
                setDone(true);
                router.push("/home");
              }}
              onRestart={(message) => {
                setChallenge(null);
                setPassword("");
                setError(message ? new Error(message) : null);
              }}
            />
          </div>
        ) : (
        <div className="au-body" key="password">
          <header className="au-head">
            <h1>{t("authSignInTitle")}</h1>
            <p>{t("authSignInSub")}</p>
          </header>

          <form onSubmit={submit} className="au-form" noValidate aria-busy={busy}>
            {error && !emailError && !passwordError && (
              <div role="alert" className="vf-alert tone-bad au-alert">
                <Icon name="ph-warning-circle" size={18} style={{ flex: "none" }} />
                <div className="vf-alert-text">{error.message}</div>
              </div>
            )}

            {done && (
              <div role="status" className="vf-alert tone-ok au-alert">
                <Icon name="ph-check-circle" size={18} style={{ flex: "none" }} />
                <div className="vf-alert-text">{t("signedInOpening")}</div>
              </div>
            )}

            <div className="au-field">
              <label htmlFor="email">{t("emailAddress")}</label>
              <input
                id="email" type="email" inputMode="email" className="au-input" value={email}
                autoComplete="username" autoCapitalize="none" spellCheck={false} required
                aria-invalid={!!emailError} aria-describedby={emailError ? "email-error" : undefined}
                onChange={(e) => setEmail(e.target.value)} placeholder={t("emailPh")}
              />
              {emailError && (
                <div className="au-error" id="email-error"><Icon name="ph-warning-circle" size={14} /> {emailError}</div>
              )}
            </div>

            <div className="au-field">
              <label htmlFor="password">{t("password")}</label>
              <div className="au-password">
                <input
                  id="password" className="au-input" type={reveal ? "text" : "password"} value={password}
                  autoComplete="current-password" required
                  aria-invalid={!!passwordError} aria-describedby={passwordError ? "password-error" : undefined}
                  onChange={(e) => setPassword(e.target.value)} placeholder={t("passwordPh")}
                />
                <button
                  type="button" className="au-reveal" onClick={() => setReveal((v) => !v)}
                  aria-label={reveal ? t("hidePassword") : t("showPassword")} aria-pressed={reveal}
                  title={reveal ? t("hidePassword") : t("showPassword")}
                >
                  <Icon name={reveal ? "ph-eye-slash" : "ph-eye"} size={18} />
                </button>
              </div>
              {passwordError && (
                <div className="au-error" id="password-error"><Icon name="ph-warning-circle" size={14} /> {passwordError}</div>
              )}
            </div>

            <div className="au-row">
              <label className="au-check">
                <input type="checkbox" defaultChecked />
                <span>{t("rememberMe")}</span>
              </label>
              <Link href="/verify?purpose=password_reset" className="au-link">{t("forgotPassword")}</Link>
            </div>

            <button className="au-submit" disabled={busy} type="submit">
              {done ? (
                <><Icon name="ph-check" size={18} /> {t("signIn")}</>
              ) : busy ? (
                <Spinner label={t("signingIn")} />
              ) : (
                t("signIn")
              )}
            </button>
          </form>

          <p className="au-alt">{t("newToVouchflow")} <Link href="/register" className="au-link">{t("registerCompany")}</Link></p>

          {SHOW_DEMO_ACCOUNTS && <DemoAccounts selected={email} onPick={pickDemo} />}
        </div>
        )}

        <footer className="au-foot">
          <Icon name="ph-lock-simple" size={14} />
          <span>{t("authSecure")}</span>
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
    <details className="au-demo">
      <summary><Icon name="ph-user-switch" size={16} /> {t("authDemo")} <span className="au-demo-caret"><Icon name="ph-caret-down" size={14} /></span></summary>
      <div className="au-demo-list">
        {DEMO.map((account) => (
          <button
            key={account.email}
            type="button"
            aria-pressed={selected === account.email}
            onClick={() => onPick(account.email)}
            className="au-demo-item"
          >
            <span className="au-demo-icon"><Icon name={account.icon} size={16} /></span>
            <span className="au-demo-text">
              <strong>{account.label}</strong>
              <span>{account.person} · {account.note}</span>
            </span>
            {selected === account.email && <span className="au-demo-tick"><Icon name="ph-check" size={16} /></span>}
          </button>
        ))}
        <p className="au-demo-note">{t("authDemoNote")}</p>
      </div>
    </details>
  );
}
