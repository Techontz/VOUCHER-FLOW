"use client";

import { Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";

type Invitation = { name: string; email: string; company: string | null };

/** Where an invited person chooses their password, from the emailed link. */
function InviteInner() {
  const router = useRouter();
  const params = useSearchParams();
  const { t, toast } = useApp();
  const token = params.get("token") ?? "";

  const [invitation, setInvitation] = useState<Invitation | null>(null);
  const [gone, setGone] = useState<string | null>(token ? null : "This link is incomplete. Open it again from your invitation email.");
  const [password, setPassword] = useState("");
  const [passwordConfirm, setPasswordConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    if (!token) return;
    api.get<Invitation>(`/auth/invitation/${encodeURIComponent(token)}`)
      .then(setInvitation)
      .catch((err) => setGone(err instanceof ApiError ? err.message : "This invitation could not be opened."));
  }, [token]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.post("/auth/invitation/accept", { token, password, password_confirmation: passwordConfirm });
      toast("Password set", `Sign in with ${invitation?.email ?? "your email"} and your new password.`, "ok");
      router.push("/login");
    } catch (err) {
      if (err instanceof ApiError) {
        if (err.field("token")) setGone(err.field("token") ?? null);
        else setError(err);
      }
      setBusy(false);
    }
  }

  const mismatch = passwordConfirm.length > 0 && password !== passwordConfirm;

  return (
    <AuthFrame
      kicker="Invitation"
      title={invitation ? `Welcome, ${invitation.name}` : "Set your password"}
      sub={invitation
        ? `You have been added to ${invitation.company ?? "VouchFlow"}. Choose a password to finish setting up your account.`
        : "Choose a password to finish setting up your account."}
    >
      {gone ? (
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <div role="alert" style={{ border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)", color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "10px var(--space-3)", fontSize: 14 }}>
            {gone}
          </div>
          <Link className="btn btn-secondary btn-block" href="/login">{t("signIn")}</Link>
        </div>
      ) : !invitation ? (
        <div style={{ display: "grid", placeItems: "center", padding: "var(--space-6)" }}><Spinner label={t("loading")} /></div>
      ) : (
        <form onSubmit={submit} style={{ display: "grid", gap: "var(--space-3)" }} noValidate>
          {error && Object.keys(error.errors).length === 0 && (
            <div role="alert" style={{ border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)", color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "10px var(--space-3)", fontSize: 14 }}>
              {error.message}
            </div>
          )}

          <Field label={t("email")} htmlFor="invite-email">
            <input id="invite-email" className="input" value={invitation.email} readOnly autoComplete="username" />
          </Field>
          <Field label={t("newPassword")} htmlFor="invite-password" error={error?.field("password")} hint="At least 8 characters." required>
            <input id="invite-password" className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} minLength={8} required autoComplete="new-password" autoFocus />
          </Field>
          <Field label={t("confirmPassword")} htmlFor="invite-confirm" error={mismatch ? "The passwords do not match." : undefined} required>
            <input id="invite-confirm" className="input" type="password" value={passwordConfirm} onChange={(e) => setPasswordConfirm(e.target.value)} required autoComplete="new-password" />
          </Field>

          <button className="btn btn-primary btn-block" type="submit" disabled={busy || password.length < 8 || password !== passwordConfirm}>
            {busy ? <Spinner label={t("loading")} /> : <><Icon name="ph-check-circle" size={16} /> Set password</>}
          </button>
        </form>
      )}
    </AuthFrame>
  );
}

export default function InvitePage() {
  return (
    <Suspense fallback={<div style={{ padding: "var(--space-8)" }}>Loading…</div>}>
      <InviteInner />
    </Suspense>
  );
}
