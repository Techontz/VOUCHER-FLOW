"use client";

import { useEffect, useRef, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import type { LoginChallenge, LoginChannel, LoginCodeSent } from "@/lib/types";
import { Icon, Spinner } from "@/components/ui";

/** Failures after which the challenge is gone and only a fresh sign-in helps. */
const TERMINAL: Record<string, MessageKey> = {
  too_many_attempts: "twoStepErrTooManyAttempts",
  challenge_expired: "twoStepErrExpired",
  account_unavailable: "twoStepErrUnavailable",
  too_many_sends: "twoStepErrTooManySends",
};

/** Recoverable failures, worded in the active language. */
const RECOVERABLE: Record<string, MessageKey> = {
  invalid_code: "twoStepErrInvalid",
  code_expired: "twoStepErrCodeExpired",
  no_code: "twoStepErrNoCode",
  resend_cooldown: "twoStepErrCooldown",
  delivery_failed: "twoStepErrDelivery",
};

const EMPTY = ["", "", "", "", "", ""];

/**
 * The second step of signing in: choose where the code goes (when the account
 * has both an email address and a phone), then enter it.
 *
 * The challenge lives only in this component's state — never in storage — so
 * closing or reloading the tab simply means signing in again.
 */
export function LoginVerification({
  challenge,
  showDemoHint,
  onVerified,
  onRestart,
}: {
  challenge: LoginChallenge;
  showDemoHint: boolean;
  onVerified: () => void;
  /** The challenge can no longer be used; return to the password step with this message. */
  onRestart: (message: string) => void;
}) {
  const { t, verifyLogin } = useApp();
  const channels = challenge.channels;
  const initialDestination = channels.find((c) => c.channel === challenge.sent_to)?.destination ?? null;

  const [sentTo, setSentTo] = useState<LoginChannel | null>(challenge.sent_to);
  const [destination, setDestination] = useState<string | null>(initialDestination);
  const [choosing, setChoosing] = useState(challenge.sent_to === null);
  const [picked, setPicked] = useState<LoginChannel>(challenge.sent_to ?? channels[0]?.channel ?? "email");
  const [codeMinutes, setCodeMinutes] = useState<number | null>(
    challenge.code_expires_in ? Math.round(challenge.code_expires_in / 60) : null,
  );
  const [digits, setDigits] = useState<string[]>(EMPTY);
  const [verifying, setVerifying] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [resendAt, setResendAt] = useState<number | null>(
    () => (challenge.resend_in ? Date.now() + challenge.resend_in * 1000 : null),
  );
  const [now, setNow] = useState(() => Date.now());
  const inputs = useRef<Array<HTMLInputElement | null>>([]);

  const code = digits.join("");
  const wait = resendAt ? Math.max(0, Math.ceil((resendAt - now) / 1000)) : 0;

  // Tick once a second while the resend button is held back.
  useEffect(() => {
    if (!resendAt) return;
    const id = window.setInterval(() => {
      const at = Date.now();
      setNow(at);
      if (at >= resendAt) {
        setResendAt(null);
        window.clearInterval(id);
      }
    }, 1000);
    return () => window.clearInterval(id);
  }, [resendAt]);

  useEffect(() => {
    if (!choosing) inputs.current[0]?.focus();
  }, [choosing]);

  /** Turns an API failure into a message, or hands back to the password step. */
  function handleFailure(err: unknown) {
    if (!(err instanceof ApiError)) {
      setError(err instanceof Error ? err.message : t("somethingWrong"));
      return;
    }
    const reason = err.reason;
    if (reason && TERMINAL[reason]) {
      onRestart(t(TERMINAL[reason]));
      return;
    }
    if (reason === "resend_cooldown") {
      const retry = Number(err.details.retry_after);
      if (retry > 0) {
        setNow(Date.now());
        setResendAt(Date.now() + retry * 1000);
      }
    }
    if (reason === "no_code" && channels.length > 1) setChoosing(true);

    let message = reason && RECOVERABLE[reason] ? t(RECOVERABLE[reason]) : (err.field("channel") ?? err.message);
    if (reason === "invalid_code") {
      const left = Number(err.details.attempts_remaining);
      if (Number.isFinite(left) && left > 0) {
        message += " " + (left === 1 ? t("twoStepAttemptLeft") : t("twoStepAttemptsLeft").replace("{n}", String(left)));
      }
      setDigits(EMPTY);
      inputs.current[0]?.focus();
    }
    setError(message);
  }

  async function send(channel: LoginChannel, resend = false) {
    setSending(true);
    setError(null);
    setNotice(null);
    try {
      const res = await api.post<LoginCodeSent>("/auth/login/send-code", { challenge: challenge.challenge, channel });
      setSentTo(res.sent_to);
      setDestination(res.destination);
      setCodeMinutes(res.code_expires_in ? Math.round(res.code_expires_in / 60) : null);
      setNow(Date.now());
      setResendAt(res.resend_in ? Date.now() + res.resend_in * 1000 : null);
      setDigits(EMPTY);
      setChoosing(false);
      if (resend) setNotice(t("twoStepResent"));
    } catch (err) {
      handleFailure(err);
    } finally {
      setSending(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (choosing) {
      await send(picked);
      return;
    }
    if (code.length < 6) return;
    setVerifying(true);
    setError(null);
    setNotice(null);
    try {
      await verifyLogin(challenge.challenge, code);
      onVerified();
    } catch (err) {
      handleFailure(err);
      setVerifying(false);
    }
  }

  function setDigit(index: number, value: string) {
    const clean = value.replace(/\D/g, "");
    if (!clean) {
      setDigits((d) => d.map((v, i) => (i === index ? "" : v)));
      return;
    }
    // Pasting or autofilling the whole code into any box fills the row.
    if (clean.length > 1) {
      setDigits((d) => d.map((v, i) => clean[i - index] ?? (i < index ? v : "")));
      inputs.current[Math.min(5, index + clean.length - 1)]?.focus();
      return;
    }
    setDigits((d) => d.map((v, i) => (i === index ? clean : v)));
    if (index < 5) inputs.current[index + 1]?.focus();
  }

  const busy = verifying || sending;
  const channelLabel = (channel: LoginChannel) => (channel === "sms" ? t("twoStepViaSms") : t("twoStepViaEmail"));

  return (
    <>
      <header className="vf-login-head">
        <h1>{t("twoStepTitle")}</h1>
        <p>{choosing ? t("twoStepChoose") : t("twoStepSub")}</p>
      </header>

      <form onSubmit={submit} className="vf-login-form" noValidate aria-busy={busy}>
        {error && (
          <div role="alert" className="vf-alert tone-bad vf-login-alert">
            <Icon name="ph-warning-circle" size={20} style={{ flex: "none" }} />
            <div className="vf-alert-text">{error}</div>
          </div>
        )}
        {notice && !error && (
          <div role="status" className="vf-alert tone-ok vf-login-alert">
            <Icon name="ph-check-circle" size={20} style={{ flex: "none" }} />
            <div className="vf-alert-text">{notice}</div>
          </div>
        )}

        {choosing ? (
          <>
            <div role="group" aria-label={t("twoStepChoose")} style={{ display: "grid", gap: 10 }}>
              {channels.map((option) => (
                <button
                  key={option.channel}
                  type="button"
                  aria-pressed={picked === option.channel}
                  className="vf-choice"
                  onClick={() => setPicked(option.channel)}
                >
                  <span className="vf-choice-icon">
                    <Icon name={option.channel === "sms" ? "ph-device-mobile" : "ph-envelope-simple"} size={20} />
                  </span>
                  <span className="vf-choice-text">
                    <span className="vf-choice-label">{channelLabel(option.channel)}</span>
                    <span className="vf-choice-sub">{option.destination}</span>
                  </span>
                </button>
              ))}
            </div>

            <button className="btn btn-primary btn-lg vf-login-submit" type="submit" disabled={busy}>
              {sending ? <Spinner label={t("loading")} /> : <>{t("twoStepSendCode")} <Icon name="ph-arrow-right" size={18} /></>}
            </button>
          </>
        ) : (
          <>
            <p style={{ margin: 0, fontSize: "var(--text-base)", lineHeight: 1.55, color: "var(--color-neutral-600)" }}>
              {t("twoStepSentTo")} <strong style={{ color: "var(--color-text)" }}>{destination ?? (sentTo ? channelLabel(sentTo) : "")}</strong>.
              {codeMinutes ? <> {t("twoStepValidFor").replace("{n}", String(codeMinutes))}</> : null}
            </p>

            <div className="field">
              <label htmlFor="login-otp-0">{t("twoStepCodeLabel")}</label>
              <div
                style={{ display: "flex", gap: 8 }}
                onPaste={(e) => {
                  const text = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
                  if (text) {
                    e.preventDefault();
                    setDigits(Array.from({ length: 6 }, (_, i) => text[i] ?? ""));
                    inputs.current[Math.min(5, text.length)]?.focus();
                  }
                }}
              >
                {digits.map((digit, index) => (
                  <input
                    key={index}
                    id={`login-otp-${index}`}
                    ref={(el) => { inputs.current[index] = el; }}
                    className="input"
                    inputMode="numeric"
                    autoComplete={index === 0 ? "one-time-code" : "off"}
                    maxLength={6}
                    value={digit}
                    disabled={verifying}
                    aria-label={t("twoStepDigit").replace("{n}", String(index + 1))}
                    aria-invalid={!!error}
                    onChange={(e) => setDigit(index, e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Backspace" && !digits[index] && index > 0) inputs.current[index - 1]?.focus();
                    }}
                    style={{ textAlign: "center", fontSize: 20, fontVariantNumeric: "tabular-nums", height: 52, padding: 0, minWidth: 0 }}
                  />
                ))}
              </div>
            </div>

            <button className="btn btn-primary btn-lg vf-login-submit" type="submit" disabled={busy || code.length < 6}>
              {verifying ? <Spinner label={t("twoStepVerifying")} /> : <>{t("twoStepVerify")} <Icon name="ph-arrow-right" size={18} /></>}
            </button>

            <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "space-between", gap: 8 }}>
              <button
                type="button"
                className="btn btn-ghost btn-sm"
                disabled={busy || wait > 0 || !sentTo}
                onClick={() => sentTo && send(sentTo, true)}
                aria-live="polite"
              >
                <Icon name="ph-arrow-clockwise" size={15} />{" "}
                {wait > 0 ? t("twoStepResendIn").replace("{n}", String(wait)) : t("resendCode")}
              </button>
              {channels.length > 1 && (
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  disabled={busy}
                  onClick={() => {
                    setError(null);
                    setNotice(null);
                    setDigits(EMPTY);
                    setChoosing(true);
                  }}
                >
                  <Icon name="ph-swap" size={15} /> {t("twoStepOtherMethod")}
                </button>
              )}
            </div>
          </>
        )}

        {showDemoHint && (
          <p style={{ margin: 0, fontSize: "var(--text-sm)", color: "var(--color-neutral-600)" }}>
            <Icon name="ph-info" size={14} /> {t("twoStepDemoHint")}
          </p>
        )}
      </form>

      <div className="vf-login-alt">
        <p>
          <button
            type="button"
            className="btn btn-ghost btn-sm"
            disabled={verifying}
            onClick={() => onRestart("")}
          >
            <Icon name="ph-arrow-left" size={15} /> {t("twoStepBack")}
          </button>
        </p>
      </div>
    </>
  );
}
