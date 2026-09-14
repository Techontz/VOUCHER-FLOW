"use client";

import { useCallback, useEffect, useState } from "react";
import { api, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { Field, Icon, LoadingBlock, Spinner } from "@/components/ui";
import { FormSection, Tabs, ThemeSwitch } from "@/components/app-ui";
import { SignaturePad } from "@/components/signature-pad";

interface Session { id: number; device: string; last_used_at: string | null; created_at: string | null; is_current: boolean }

type ProfileTab = "details" | "signature" | "security" | "appearance";

export default function ProfilePage() {
  const { t, user, locale, refresh, toast, reportError, signOut, setLocale } = useApp();
  const [tab, setTab] = useState<ProfileTab>("details");

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

  const sw = locale === "sw";

  return (
    <div className="app-page app-profile">
      <header className="app-profile-head">
        <span className="app-avatar app-avatar-lg" aria-hidden="true">{user.initials}</span>
        <div className="app-profile-id">
          <h1 className="vf-pagehead-title">{user.name}</h1>
          <p className="vf-pagehead-sub">{[user.job_title, user.role_label, user.department?.name].filter(Boolean).join(" · ")}</p>
        </div>
      </header>

      <Tabs<ProfileTab> value={tab} onChange={setTab} label={t("profile")} items={[
        { value: "details", label: t("personalDetails"), icon: "ph-user" },
        { value: "signature", label: t("signature"), icon: "ph-signature" },
        { value: "security", label: t("changePassword"), icon: "ph-lock-key" },
        { value: "appearance", label: sw ? "Mwonekano na lugha" : "Appearance & language", icon: "ph-palette" },
      ]} />

      {tab === "details" && (
        <form onSubmit={saveProfile} className="vf-panel">
          <div className="vf-panel-pad">
            <FormSection title={t("personalDetails")} description="How colleagues see you on vouchers, comments and the approval trail.">
              <Field label={t("fullName")} htmlFor="p-name" required>
                <input id="p-name" className="input" value={profile.name} onChange={(e) => setProfile((p) => ({ ...p, name: e.target.value }))} required />
              </Field>
              <Field label={t("email")} htmlFor="p-email" hint="Contact your administrator to change your address">
                <input id="p-email" className="input" value={user.email} readOnly />
              </Field>
              <div className="vf-form-row">
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
            </FormSection>
          </div>
          <div className="app-form-foot">
            <span />
            <div className="app-form-foot-end"><button className="btn btn-primary" disabled={savingProfile}>{savingProfile ? <Spinner /> : t("saveChanges")}</button></div>
          </div>
        </form>
      )}

      {tab === "signature" && (
        <section className="vf-panel">
          <div className="vf-panel-pad">
            <FormSection title={t("signature")} description="Your saved signature is offered whenever you sign a voucher, and is printed on the PDF.">
              <SignaturePad value={signature} onChange={setSignature} hasSaved={!!savedSignature} savedSignature={savedSignature} />
              {user.signature_updated_at && (
                <p className="field-hint">Last updated {formatDateTime(user.signature_updated_at, locale)}</p>
              )}
            </FormSection>
          </div>
          <div className="app-form-foot">
            {savedSignature ? <button className="btn btn-danger" onClick={removeSignature}><Icon name="ph-trash" size={14} /> {t("remove")}</button> : <span />}
            <div className="app-form-foot-end">
              <button className="btn btn-primary" onClick={storeSignature} disabled={!signature || savingSignature}>
                {savingSignature ? <Spinner /> : t("save")}
              </button>
            </div>
          </div>
        </section>
      )}

      {tab === "security" && (
        <div className="app-stack">
          <form onSubmit={changePassword} className="vf-panel">
            <div className="vf-panel-pad">
              <FormSection title={t("changePassword")} description="Use at least 8 characters. Other devices stay signed in until you sign them out below.">
                <Field label={t("currentPassword")} htmlFor="cp-current" required>
                  <input id="cp-current" className="input" type="password" autoComplete="current-password" required
                    value={passwords.current_password} onChange={(e) => setPasswords((p) => ({ ...p, current_password: e.target.value }))} />
                </Field>
                <div className="vf-form-row">
                  <Field label={t("newPassword")} htmlFor="cp-new" required>
                    <input id="cp-new" className="input" type="password" autoComplete="new-password" minLength={8} required
                      value={passwords.password} onChange={(e) => setPasswords((p) => ({ ...p, password: e.target.value }))} />
                  </Field>
                  <Field label={t("confirmPassword")} htmlFor="cp-confirm" required>
                    <input id="cp-confirm" className="input" type="password" autoComplete="new-password" required
                      value={passwords.password_confirmation} onChange={(e) => setPasswords((p) => ({ ...p, password_confirmation: e.target.value }))} />
                  </Field>
                </div>
              </FormSection>
            </div>
            <div className="app-form-foot">
              <span />
              <div className="app-form-foot-end"><button className="btn btn-primary" disabled={changingPassword}>{changingPassword ? <Spinner /> : t("changePassword")}</button></div>
            </div>
          </form>

          <section className="vf-panel">
            <div className="vf-panel-head">
              <div className="vf-panel-head-main"><h2>{t("activeSessions")}</h2></div>
              <button className="btn btn-secondary btn-sm" onClick={async () => {
                try { await api.post("/auth/logout-all"); toast("Signed out everywhere", undefined, "ok"); await signOut(); }
                catch (err) { reportError(err); }
              }}><Icon name="ph-sign-out" size={14} /> Sign out everywhere</button>
            </div>
            {sessions === null ? <div className="vf-panel-pad"><LoadingBlock rows={2} /></div> : (
              <ul className="app-mini-list">
                {sessions.map((session) => (
                  <li key={session.id}>
                    <Icon name="ph-device-mobile" size={17} style={{ color: "var(--text-muted)" }} />
                    <span className="app-sessions-text">
                      <span className="app-mini-title">{session.device}{session.is_current ? ` · ${t("thisDevice")}` : ""}</span>
                      <span className="app-mini-meta">{session.last_used_at ? formatDateTime(session.last_used_at, locale) : formatDateTime(session.created_at, locale)}</span>
                    </span>
                    {session.is_current ? <span className="badge tone-ok">{t("thisDevice")}</span> : (
                      <button className="btn btn-ghost btn-sm" onClick={async () => {
                        try { await api.delete(`/auth/sessions/${session.id}`); loadSessions(); toast("Session revoked", undefined, "warn"); }
                        catch (err) { reportError(err); }
                      }}>{t("revoke")}</button>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      )}

      {tab === "appearance" && (
        <section className="vf-panel">
          <div className="vf-panel-pad">
            <FormSection title={sw ? "Mwonekano" : "Appearance"} description={sw ? "Mwanga ni chaguo-msingi. Chaguo lako linahifadhiwa kwenye wasifu wako." : "Light is the default. Your choice is saved to your profile and follows you to every device."}>
              <div><ThemeSwitch /></div>
            </FormSection>
            <FormSection title={t("language")} description={sw ? "Lugha ya kiolesura." : "The language of the interface."}>
              <div className="seg" role="group" aria-label={t("language")}>
                {([["en", "English"], ["sw", "Kiswahili"]] as const).map(([code, label]) => (
                  <button key={code} type="button" onClick={() => setLocale(code)} aria-selected={locale === code}>{label}</button>
                ))}
              </div>
            </FormSection>
          </div>
        </section>
      )}
    </div>
  );
}
