"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";

function VerifyInner() {
  const router = useRouter();
  const params = useSearchParams();
  const { t, toast, reportError } = useApp();

  const purpose = params.get("purpose") ?? "registration";
  const next = params.get("next");
  const isReset = purpose === "password_reset";

  const [identifier, setIdentifier] = useState(params.get("identifier") ?? "");
  const [digits, setDigits] = useState<string[]>(() => {
    const prefilled = params.get("code") ?? "";
    return Array.from({ length: 6 }, (_, i) => prefilled[i] ?? "");
  });
  const [password, setPassword] = useState("");
  const [passwordConfirm, setPasswordConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(!!params.get("code"));
  const [error, setError] = useState<ApiError | null>(null);
  const inputs = useRef<Array<HTMLInputElement | null>>([]);

  const code = digits.join("");

  useEffect(() => {
    if (params.get("code")) inputs.current[5]?.focus();
  }, [params]);

  function setDigit(index: number, value: string) {
    const clean = value.replace(/\D/g, "");
    if (!clean) {
      setDigits((d) => d.map((v, i) => (i === index ? "" : v)));
      return;
    }
    // Pasting the whole code into any box fills the row.
    if (clean.length > 1) {
      setDigits((d) => d.map((v, i) => clean[i - index] ?? (i < index ? v : "")));
      inputs.current[Math.min(5, index + clean.length - 1)]?.focus();
      return;
    }
    setDigits((d) => d.map((v, i) => (i === index ? clean : v)));
    if (index < 5) inputs.current[index + 1]?.focus();
  }

  async function sendCode() {
    if (!identifier) return;
    setBusy(true);
    try {
      const endpoint = isReset ? "/auth/forgot-password" : "/auth/otp/send";
      const body = isReset ? { email: identifier } : { identifier, purpose };
      const res = await api.post<{ otp?: { code: string | null } }>(endpoint, body);
      setSent(true);
      const issued = res.otp?.code;
      if (issued) {
        setDigits(issued.split(""));
        toast("Code sent", `Development code: ${issued}`, "warn");
      } else {
        toast("Code sent", "Check your inbox for the six-digit code.", "ok");
      }
    } catch (err) {
      reportError(err, "Could not send the code");
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (isReset) {
        await api.post("/auth/reset-password", { email: identifier, code, password, password_confirmation: passwordConfirm });
        toast("Password updated", "Sign in with your new password.", "ok");
        router.push("/login");
        return;
      }
      await api.post("/auth/otp/verify", { identifier, code, purpose });
      toast("Verified", "Your account is confirmed.", "ok");
      router.push(next === "onboarding" ? "/onboarding" : "/dashboard");
    } catch (err) {
      if (err instanceof ApiError) setError(err);
      setBusy(false);
    }
  }

  return (
    <AuthFrame
      kicker={isReset ? t("forgotPassword") : t("verifyNumber")}
      title={isReset ? t("changePassword") : t("verifyNumber")}
      sub={isReset
        ? "Enter the address on your account and we will send a reset code."
        : "We sent a six-digit code. Enter it below to confirm your account."}
    >
      <form onSubmit={submit} style={{ display: "grid", gap: "var(--space-3)" }} noValidate>
        {error && Object.keys(error.errors).length === 0 && (
          <div role="alert" style={{ border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)", color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "10px var(--space-3)", fontSize: 14 }}>
            {error.message}
          </div>
        )}

        <Field label={t("email")} htmlFor="identifier" error={error?.field("email") ?? error?.field("identifier")} required>
          <div style={{ display: "flex", gap: "var(--space-2)" }}>
            <input id="identifier" className="input" value={identifier} onChange={(e) => setIdentifier(e.target.value)} required />
            <button type="button" className="btn btn-secondary" onClick={sendCode} disabled={busy || !identifier} style={{ whiteSpace: "nowrap" }}>
              {sent ? t("resendCode") : "Send code"}
            </button>
          </div>
        </Field>

        <div className="field">
          <label htmlFor="otp-0">Six-digit code</label>
          <div style={{ display: "flex", gap: 8 }} onPaste={(e) => {
            const text = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
            if (text) { e.preventDefault(); setDigits(Array.from({ length: 6 }, (_, i) => text[i] ?? "")); }
          }}>
            {digits.map((digit, index) => (
              <input
                key={index}
                id={`otp-${index}`}
                ref={(el) => { inputs.current[index] = el; }}
                className="input"
                inputMode="numeric"
                autoComplete={index === 0 ? "one-time-code" : "off"}
                maxLength={6}
                value={digit}
                aria-label={`Digit ${index + 1}`}
                onChange={(e) => setDigit(index, e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Backspace" && !digits[index] && index > 0) inputs.current[index - 1]?.focus();
                }}
                style={{ textAlign: "center", fontSize: 20, fontVariantNumeric: "tabular-nums", height: 52, padding: 0 }}
              />
            ))}
          </div>
          {error?.field("code") && <div className="field-error">{error.field("code")}</div>}
        </div>

        {isReset && (
          <>
            <Field label={t("newPassword")} htmlFor="new-password" error={error?.field("password")} required>
              <input id="new-password" className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} minLength={8} required autoComplete="new-password" />
            </Field>
            <Field label={t("confirmPassword")} htmlFor="confirm-password" required>
              <input id="confirm-password" className="input" type="password" value={passwordConfirm} onChange={(e) => setPasswordConfirm(e.target.value)} required autoComplete="new-password" />
            </Field>
          </>
        )}

        <button className="btn btn-primary btn-block" type="submit" disabled={busy || code.length < 6}>
          {busy ? <Spinner label={t("loading")} /> : <><Icon name="ph-check-circle" size={16} /> {t("verifyContinue")}</>}
        </button>
      </form>
    </AuthFrame>
  );
}

export default function VerifyPage() {
  return (
    <Suspense fallback={<div style={{ padding: "var(--space-8)" }}>Loading…</div>}>
      <VerifyInner />
    </Suspense>
  );
}
