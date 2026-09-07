"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { AuthFrame } from "@/components/auth-frame";
import { Field, Icon, Spinner } from "@/components/ui";
import type { Plan, Workflow } from "@/lib/types";

type StepKey = "company" | "logo" | "departments" | "workflow" | "people" | "plan";

const STEPS: { key: StepKey; label: string }[] = [
  { key: "company", label: "Company details" },
  { key: "logo", label: "Logo & colour" },
  { key: "departments", label: "Departments" },
  { key: "workflow", label: "Approval workflow" },
  { key: "people", label: "Invite your team" },
  { key: "plan", label: "Subscription" },
];

export default function OnboardingPage() {
  const router = useRouter();
  const { t, company, user, ready, refresh, toast, reportError } = useApp();
  const [index, setIndex] = useState(0);
  const [busy, setBusy] = useState(false);

  const [profile, setProfile] = useState({ address: "", website: "", phone: "" });
  const [colour, setColour] = useState("#0088b0");
  const [logo, setLogo] = useState<File | null>(null);
  const [departments, setDepartments] = useState<string[]>(["Finance", "Operations", "Procurement"]);
  const [newDept, setNewDept] = useState("");
  const [preset, setPreset] = useState("default");
  const [presets, setPresets] = useState<{ key: string; name: string; description: string }[]>([]);
  const [invites, setInvites] = useState<{ name: string; email: string; role: string }[]>([
    { name: "", email: "", role: "hod" },
  ]);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [planId, setPlanId] = useState<number | null>(null);

  useEffect(() => {
    if (ready && !user) router.replace("/login");
  }, [ready, user, router]);

  useEffect(() => {
    if (!user) return;
    api.get<{ data: typeof presets }>("/workflows/presets").then((r) => setPresets(r.data)).catch(() => undefined);
    api.get<{ data: Plan[] }>("/plans").then((r) => {
      setPlans(r.data);
      setPlanId(company?.plan_id ?? r.data.find((p) => p.code === "business")?.id ?? null);
    }).catch(() => undefined);
    setProfile((p) => ({
      address: company?.address ?? p.address,
      website: company?.website ?? p.website,
      phone: company?.phone ?? p.phone,
    }));
    setColour(company?.primary_color ?? "#0088b0");
  }, [user, company]);

  const step = STEPS[index];

  async function persistStep(): Promise<boolean> {
    try {
      if (step.key === "company") {
        await api.put("/company", profile);
      }

      if (step.key === "logo") {
        const form = new FormData();
        form.append("primary_color", colour);
        if (logo) form.append("logo", logo);
        await request("/company/branding", { method: "POST", form });
      }

      if (step.key === "departments") {
        const existing = await api.get<{ data: { name: string }[] }>("/departments");
        const have = new Set(existing.data.map((d) => d.name.toLowerCase()));
        for (const name of departments) {
          if (name.trim() && !have.has(name.trim().toLowerCase())) {
            await api.post("/departments", { name: name.trim() });
          }
        }
      }

      if (step.key === "workflow") {
        await api.post<{ data: Workflow }>("/workflows/apply-preset", { preset });
      }

      if (step.key === "people") {
        for (const invite of invites) {
          if (invite.name.trim() && invite.email.trim()) {
            await api.post("/employees", {
              name: invite.name.trim(), email: invite.email.trim(), role: invite.role, send_invitation: true,
            });
          }
        }
      }

      if (step.key === "plan" && planId && planId !== company?.plan_id) {
        await api.post("/billing/subscribe", { plan_id: planId });
      }

      return true;
    } catch (err) {
      reportError(err, "Could not save that step");
      return false;
    }
  }

  async function advance() {
    setBusy(true);
    const ok = await persistStep();
    setBusy(false);
    if (!ok) return;

    if (index === STEPS.length - 1) {
      await refresh();
      toast("Setup complete", `${company?.name ?? "Your company"} is ready to go.`, "ok");
      router.push("/dashboard");
      return;
    }
    setIndex((i) => i + 1);
  }

  if (!ready || !user) {
    return <div style={{ padding: "var(--space-8)" }}><Spinner label={t("loading")} /></div>;
  }

  return (
    <AuthFrame
      kicker={t("companySetup")}
      title={step.label}
      sub={`${t("step")} ${index + 1} ${t("of")} ${STEPS.length}`}
      aside={
        <div style={{ border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-4)", background: "var(--color-neutral-100)" }}>
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
            {t("setupChecklist")}
          </div>
          {STEPS.map((entry, i) => (
            <div key={entry.key} style={{
              display: "flex", gap: 10, alignItems: "center", padding: "7px 0",
              color: i <= index ? "var(--color-text)" : "var(--color-neutral-600)",
            }}>
              <Icon name={i < index ? "ph-check-circle" : i === index ? "ph-circle-half" : "ph-circle"} size={18}
                color={i < index ? "var(--color-accent-600)" : undefined} />
              <span style={{ fontSize: 14.5 }}>{entry.label}</span>
            </div>
          ))}
        </div>
      }
    >
      <div style={{ display: "flex", gap: 4, marginBottom: "var(--space-4)" }} aria-hidden="true">
        {STEPS.map((entry, i) => (
          <div key={entry.key} style={{ flex: 1, height: 3, background: i <= index ? "var(--color-accent-500)" : "var(--color-neutral-300)" }} />
        ))}
      </div>

      <div style={{ display: "grid", gap: "var(--space-3)" }}>
        {step.key === "company" && (
          <>
            <Field label={t("address")} htmlFor="address">
              <input id="address" className="input" value={profile.address} onChange={(e) => setProfile((p) => ({ ...p, address: e.target.value }))} placeholder="Plot 44, Mikocheni · Dar es Salaam" />
            </Field>
            <Field label={t("phone")} htmlFor="ob-phone">
              <input id="ob-phone" className="input" value={profile.phone} onChange={(e) => setProfile((p) => ({ ...p, phone: e.target.value }))} />
            </Field>
            <Field label={t("website")} htmlFor="website">
              <input id="website" className="input" value={profile.website} onChange={(e) => setProfile((p) => ({ ...p, website: e.target.value }))} placeholder="https://" />
            </Field>
          </>
        )}

        {step.key === "logo" && (
          <>
            <Field label={t("logo")} htmlFor="logo" hint="PNG or JPG, up to 2 MB. It prints on every voucher.">
              <input id="logo" className="input" type="file" accept="image/*" onChange={(e) => setLogo(e.target.files?.[0] ?? null)} />
            </Field>
            <Field label={t("primaryColour")} htmlFor="colour">
              <div style={{ display: "flex", gap: "var(--space-2)", alignItems: "center", flexWrap: "wrap" }}>
                <input id="colour" type="color" value={colour} onChange={(e) => setColour(e.target.value)} style={{ width: 52, height: 36, border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", background: "transparent", cursor: "pointer" }} />
                <input className="input" value={colour} onChange={(e) => setColour(e.target.value)} style={{ maxWidth: 140 }} />
                {["#0088b0", "#d6006c", "#1f6f4a", "#8a4b12"].map((c) => (
                  <button key={c} type="button" onClick={() => setColour(c)} aria-label={`Use ${c}`}
                    style={{ width: 30, height: 30, background: c, border: colour === c ? "2px solid var(--color-text)" : "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", cursor: "pointer" }} />
                ))}
              </div>
            </Field>
          </>
        )}

        {step.key === "departments" && (
          <>
            <div style={{ display: "flex", gap: "var(--space-2)" }}>
              <input className="input" value={newDept} placeholder="Add a department" onChange={(e) => setNewDept(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") { e.preventDefault(); if (newDept.trim()) { setDepartments((d) => [...d, newDept.trim()]); setNewDept(""); } }
                }} />
              <button type="button" className="btn btn-secondary" onClick={() => { if (newDept.trim()) { setDepartments((d) => [...d, newDept.trim()]); setNewDept(""); } }}>
                {t("add")}
              </button>
            </div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {departments.map((name, i) => (
                <span key={`${name}-${i}`} className="tag tag-neutral" style={{ fontSize: 13.5 }}>
                  {name}
                  <button type="button" onClick={() => setDepartments((d) => d.filter((_, j) => j !== i))}
                    aria-label={`Remove ${name}`} style={{ border: 0, background: "transparent", cursor: "pointer", color: "inherit", padding: 0, marginLeft: 4 }}>
                    <Icon name="ph-x" size={12} />
                  </button>
                </span>
              ))}
            </div>
          </>
        )}

        {step.key === "workflow" && (
          <>
            <p style={{ fontSize: 14.5, color: "var(--color-neutral-700)", margin: 0 }}>{t("wfIntro")}</p>
            {presets.map((entry) => (
              <label key={entry.key} style={{
                display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer",
                border: `1px solid ${preset === entry.key ? "var(--color-accent-500)" : "var(--color-divider)"}`,
                background: preset === entry.key ? "var(--color-accent-100)" : "transparent",
                borderRadius: "var(--radius-md)", padding: "10px var(--space-3)",
              }}>
                <input type="radio" name="preset" checked={preset === entry.key} onChange={() => setPreset(entry.key)} style={{ marginTop: 4 }} />
                <span>
                  <span style={{ display: "block", fontWeight: 600 }}>{entry.name}</span>
                  <span style={{ display: "block", fontSize: 13.5, color: "var(--color-neutral-700)" }}>{entry.description}</span>
                </span>
              </label>
            ))}
            <div style={{ fontSize: 13, color: "var(--color-neutral-600)" }}>
              You can change every step, its order and its permissions later under Settings.
            </div>
          </>
        )}

        {step.key === "people" && (
          <>
            {invites.map((invite, i) => (
              <div key={i} style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "var(--space-2)" }}>
                <input className="input" placeholder={t("fullName")} value={invite.name}
                  onChange={(e) => setInvites((v) => v.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
                <input className="input" type="email" placeholder={t("email")} value={invite.email}
                  onChange={(e) => setInvites((v) => v.map((x, j) => (j === i ? { ...x, email: e.target.value } : x)))} />
                <select className="input" value={invite.role}
                  onChange={(e) => setInvites((v) => v.map((x, j) => (j === i ? { ...x, role: e.target.value } : x)))}>
                  <option value="employee">Employee</option>
                  <option value="hod">Head of department</option>
                  <option value="ceo">CEO / approving manager</option>
                  <option value="cashier">Cashier · finance</option>
                  <option value="finance">Finance</option>
                  <option value="company_admin">Administrator</option>
                </select>
              </div>
            ))}
            <button type="button" className="btn btn-secondary" onClick={() => setInvites((v) => [...v, { name: "", email: "", role: "employee" }])}>
              <Icon name="ph-plus" size={15} /> {t("inviteUser")}
            </button>
          </>
        )}

        {step.key === "plan" && (
          <div style={{ display: "grid", gap: 8 }}>
            {plans.filter((p) => p.is_public).map((plan) => (
              <label key={plan.id} style={{
                display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer",
                border: `1px solid ${planId === plan.id ? "var(--color-accent-500)" : "var(--color-divider)"}`,
                background: planId === plan.id ? "var(--color-accent-100)" : "transparent",
                borderRadius: "var(--radius-md)", padding: "10px var(--space-3)",
              }}>
                <input type="radio" name="ob-plan" checked={planId === plan.id} onChange={() => setPlanId(plan.id)} style={{ marginTop: 4 }} />
                <span style={{ flex: 1 }}>
                  <span style={{ display: "block", fontWeight: 600 }}>{plan.label}</span>
                  <span style={{ display: "block", fontSize: 13.5, color: "var(--color-neutral-700)" }}>
                    {plan.max_users ? `${plan.max_users} users` : "Unlimited users"} ·{" "}
                    {plan.max_vouchers_per_month ? `${plan.max_vouchers_per_month} vouchers / month` : "Unlimited vouchers"}
                  </span>
                </span>
              </label>
            ))}
            <div style={{ fontSize: 13, color: "var(--color-neutral-600)" }}>
              Your trial runs first — you will not be charged today.
            </div>
          </div>
        )}
      </div>

      <div style={{ display: "flex", gap: "var(--space-2)", marginTop: "var(--space-6)", borderTop: "1px solid var(--color-divider)", paddingTop: "var(--space-4)", flexWrap: "wrap" }}>
        <button className="btn btn-secondary" onClick={() => setIndex((i) => Math.max(0, i - 1))} disabled={index === 0 || busy}>
          {t("back")}
        </button>
        <div style={{ flex: 1 }} />
        <button className="btn btn-ghost" onClick={() => router.push("/dashboard")} disabled={busy}>{t("skipSetup")}</button>
        <button className="btn btn-primary" onClick={advance} disabled={busy}>
          {busy ? <Spinner /> : index === STEPS.length - 1 ? t("finishSetup") : t("next")}
        </button>
      </div>
    </AuthFrame>
  );
}
