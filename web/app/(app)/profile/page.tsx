"use client";

import { useCallback, useEffect, useState } from "react";
import { api, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { Field, Icon, LoadingBlock, PageHeader, SectionTitle, Spinner } from "@/components/ui";
import { SignaturePad } from "@/components/signature-pad";

interface Session { id: number; device: string; last_used_at: string | null; created_at: string | null; is_current: boolean }

export default function ProfilePage() {
  const { t, user, locale, refresh, toast, reportError, signOut } = useApp();

  const [profile, setProfile] = useState({ name: "", phone: "", job_title: "" });
  const [avatar, setAvatar] = useState<File | null>(null);
  const [savingProfile, setSavingProfile] = useState(false);

  const [signature, setSignature] = useState<string | null>(null);
  const [savedSignature, setSavedSignature] = useState<string | null>(null);
  const [savingSignature, setSavingSignature] = useState(false);

  const [passwords, setPasswords] = useState({ current_password: "", password: "", password_confirmation: "" });
  const [changingPassword, setChangingPassword] = useState(false);

  const [sessions, setSessions] = useState<Session[] | null>(null);

  useEffect(() => {
    if (!user) return;
    setProfile({ name: user.name, phone: user.phone ?? "", job_title: user.job_title ?? "" });
  }, [user]);

  const loadSessions = useCallback(() => {
    api.get<{ data: Session[] }>("/auth/sessions").then((r) => setSessions(r.data)).catch(() => setSessions([]));
  }, []);

  useEffect(() => {
    loadSessions();
    if (user?.has_signature) {
      api.get<{ signature: string | null }>("/profile/signature")
        .then((r) => setSavedSignature(r.signature))
        .catch(() => undefined);
    }
  }, [loadSessions, user?.has_signature]);

  async function saveProfile(e: React.FormEvent) {
    e.preventDefault();
    setSavingProfile(true);
    try {
      if (avatar) {
        const form = new FormData();
        form.append("avatar", avatar);
        Object.entries(profile).forEach(([k, v]) => form.append(k, v));
        await request("/profile", { method: "POST", form });
      } else {
        await api.put("/profile", profile);
      }
      await refresh();
      toast("Profile updated", undefined, "ok");
      setAvatar(null);
    } catch (err) {
      reportError(err, "Could not update your profile");
    } finally {
      setSavingProfile(false);
    }
  }

  async function storeSignature() {
    if (!signature) return;
    setSavingSignature(true);
    try {
      await api.post("/profile/signature", { signature });
      setSavedSignature(signature);
      await refresh();
      toast("Signature saved", "It will be offered whenever you sign a voucher.", "ok");
    } catch (err) {
      reportError(err, "Could not save the signature");
    } finally {
      setSavingSignature(false);
    }
  }

  async function removeSignature() {
    try {
      await api.delete("/profile/signature");
      setSavedSignature(null);
      setSignature(null);
      await refresh();
      toast("Signature removed", undefined, "warn");
    } catch (err) {
      reportError(err, "Could not remove the signature");
    }
  }

  async function changePassword(e: React.FormEvent) {
    e.preventDefault();
    setChangingPassword(true);
    try {
      await api.post("/auth/change-password", passwords);
      setPasswords({ current_password: "", password: "", password_confirmation: "" });
      toast("Password updated", undefined, "ok");
    } catch (err) {
      reportError(err, "Could not change your password");
    } finally {
      setChangingPassword(false);
    }
  }

  if (!user) return <LoadingBlock rows={4} />;

  return (
    <div style={{ maxWidth: 940 }}>
      <PageHeader kicker={t("profile")} title={user.name} sub={`${user.role_label}${user.department ? ` · ${user.department.name}` : ""}`} />

      <div className="vf-split">
        <div style={{ display: "grid", gap: "var(--space-8)" }}>
          <section>
            <SectionTitle>{t("personalDetails")}</SectionTitle>
            <form onSubmit={saveProfile} style={{ display: "grid", gap: "var(--space-3)" }}>
              <Field label={t("fullName")} htmlFor="p-name" required>
                <input id="p-name" className="input" value={profile.name} onChange={(e) => setProfile((p) => ({ ...p, name: e.target.value }))} required />
              </Field>
              <Field label={t("email")} htmlFor="p-email" hint="Contact your administrator to change your address">
                <input id="p-email" className="input" value={user.email} readOnly />
              </Field>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("phone")} htmlFor="p-phone">
                  <input id="p-phone" className="input" value={profile.phone} onChange={(e) => setProfile((p) => ({ ...p, phone: e.target.value }))} />
                </Field>
                <Field label={t("jobTitle")} htmlFor="p-title">
                  <input id="p-title" className="input" value={profile.job_title} onChange={(e) => setProfile((p) => ({ ...p, job_title: e.target.value }))} />
                </Field>
              </div>
              <Field label="Photo" htmlFor="p-avatar">
                <input id="p-avatar" className="input" type="file" accept="image/*" onChange={(e) => setAvatar(e.target.files?.[0] ?? null)} />
              </Field>
              <div><button className="btn btn-primary" disabled={savingProfile}>{savingProfile ? <Spinner /> : t("saveChanges")}</button></div>
            </form>
          </section>

          <section>
            <SectionTitle>{t("changePassword")}</SectionTitle>
            <form onSubmit={changePassword} style={{ display: "grid", gap: "var(--space-3)" }}>
              <Field label={t("currentPassword")} htmlFor="cp-current" required>
                <input id="cp-current" className="input" type="password" autoComplete="current-password" required
                  value={passwords.current_password} onChange={(e) => setPasswords((p) => ({ ...p, current_password: e.target.value }))} />
              </Field>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("newPassword")} htmlFor="cp-new" required>
                  <input id="cp-new" className="input" type="password" autoComplete="new-password" minLength={8} required
                    value={passwords.password} onChange={(e) => setPasswords((p) => ({ ...p, password: e.target.value }))} />
                </Field>
                <Field label={t("confirmPassword")} htmlFor="cp-confirm" required>
                  <input id="cp-confirm" className="input" type="password" autoComplete="new-password" required
                    value={passwords.password_confirmation} onChange={(e) => setPasswords((p) => ({ ...p, password_confirmation: e.target.value }))} />
                </Field>
              </div>
              <div><button className="btn btn-secondary" disabled={changingPassword}>{changingPassword ? <Spinner /> : t("changePassword")}</button></div>
            </form>
          </section>
        </div>

        <div style={{ display: "grid", gap: "var(--space-8)" }}>
          <section>
            <SectionTitle>{t("signature")}</SectionTitle>
            <p style={{ fontSize: 14.5, color: "var(--color-neutral-700)" }}>
              Your saved signature is offered whenever you sign a voucher, and is printed on the PDF.
            </p>
            <SignaturePad value={signature} onChange={setSignature} hasSaved={!!savedSignature} savedSignature={savedSignature} />
            <div style={{ display: "flex", gap: "var(--space-2)", marginTop: "var(--space-3)", flexWrap: "wrap" }}>
              <button className="btn btn-primary" onClick={storeSignature} disabled={!signature || savingSignature}>
                {savingSignature ? <Spinner /> : t("save")}
              </button>
              {savedSignature && <button className="btn btn-secondary btn-danger" onClick={removeSignature}>{t("remove")}</button>}
            </div>
            {user.signature_updated_at && (
              <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)", marginTop: 6 }}>
                Last updated {formatDateTime(user.signature_updated_at, locale)}
              </div>
            )}
          </section>

          <section>
            <SectionTitle actions={
              <button className="btn btn-ghost btn-sm" onClick={async () => {
                try { await api.post("/auth/logout-all"); toast("Signed out everywhere", undefined, "ok"); await signOut(); }
                catch (err) { reportError(err); }
              }}>Sign out everywhere</button>
            }>{t("activeSessions")}</SectionTitle>

            {sessions === null ? <LoadingBlock rows={2} /> : (
              <div style={{ display: "grid", gap: 4 }}>
                {sessions.map((session) => (
                  <div key={session.id} style={{
                    display: "flex", alignItems: "center", gap: "var(--space-3)",
                    border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-2) var(--space-3)",
                  }}>
                    <Icon name="ph-device-mobile" size={18} color="var(--color-neutral-600)" />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 14.5, fontWeight: session.is_current ? 600 : 400 }}>
                        {session.device}{session.is_current ? ` · ${t("thisDevice")}` : ""}
                      </div>
                      <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)" }}>
                        {session.last_used_at ? formatDateTime(session.last_used_at, locale) : formatDateTime(session.created_at, locale)}
                      </div>
                    </div>
                    {!session.is_current && (
                      <button className="btn btn-ghost btn-sm" onClick={async () => {
                        try { await api.delete(`/auth/sessions/${session.id}`); loadSessions(); toast("Session revoked", undefined, "warn"); }
                        catch (err) { reportError(err); }
                      }}>{t("revoke")}</button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
