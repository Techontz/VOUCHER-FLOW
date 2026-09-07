"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import {
  Banner, Dialog, ErrorState, Field, Icon, LoadingBlock, Note, PageHeader, SectionTitle, Spinner,
} from "@/components/ui";
import type { Company, Workflow, WorkflowStep, VoucherType } from "@/lib/types";

type Tab = "workflow" | "types" | "company";

interface DirectoryUser { id: number; name: string; role: string }

const ROLE_OPTIONS = [
  { value: "employee", label: "Employee" },
  { value: "hod", label: "HOD" },
  { value: "finance", label: "Finance" },
  { value: "ceo", label: "CEO" },
  { value: "cashier", label: "Cashier" },
  { value: "director", label: "Director" },
  { value: "custom", label: "Custom approver" },
];

const CAPS: { key: keyof WorkflowStep; label: string }[] = [
  { key: "can_sign", label: "Sign" },
  { key: "can_approve", label: "Approve" },
  { key: "can_reject", label: "Reject" },
  { key: "can_request_changes", label: "Request changes" },
  { key: "can_pay", label: "Record payment" },
  { key: "can_print", label: "Print / PDF" },
];

export default function SettingsPage() {
  const { t, company, refresh, toast, reportError } = useApp();
  const [tab, setTab] = useState<Tab>("workflow");

  return (
    <div style={{ maxWidth: 1080 }}>
      <PageHeader kicker={t("settings")} title={t("settings")} sub={t("wfIntro")} />

      <div className="seg" style={{ marginBottom: "var(--space-6)", flexWrap: "wrap" }} role="tablist">
        {([["workflow", t("approvalWorkflow")], ["types", t("voucherSettings")], ["company", t("companyProfile")]] as const).map(([key, label]) => (
          <button key={key} role="tab" aria-selected={tab === key} onClick={() => setTab(key as Tab)}
            style={{
              border: 0, padding: "8px 14px", fontSize: 13.5, cursor: "pointer", fontFamily: "var(--font-body)",
              background: tab === key ? "var(--color-accent)" : "transparent",
              color: tab === key ? "var(--color-bg)" : "var(--color-text)",
            }}>
            {label}
          </button>
        ))}
      </div>

      {tab === "workflow" && <WorkflowBuilder />}
      {tab === "types" && <VoucherTypes />}
      {tab === "company" && <CompanyProfile />}
    </div>
  );
}

/* ─────────────────────────────────────────────── workflow builder ───────── */

function WorkflowBuilder() {
  const { t, company, toast, reportError } = useApp();
  const [workflows, setWorkflows] = useState<Workflow[] | null>(null);
  const [steps, setSteps] = useState<WorkflowStep[]>([]);
  const [current, setCurrent] = useState<Workflow | null>(null);
  const [people, setPeople] = useState<DirectoryUser[]>([]);
  const [presets, setPresets] = useState<{ key: string; name: string; description: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [presetDialog, setPresetDialog] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Workflow[] }>("/workflows")
      .then((r) => {
        setWorkflows(r.data);
        const def = r.data.find((w) => w.is_default) ?? r.data[0] ?? null;
        setCurrent(def);
        setSteps(def ? def.steps.map((s) => ({ ...s })) : []);
      })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(() => {
    load();
    api.get<{ data: DirectoryUser[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
    api.get<{ data: typeof presets }>("/workflows/presets").then((r) => setPresets(r.data)).catch(() => undefined);
  }, [load]);

  function patch(index: number, changes: Partial<WorkflowStep>) {
    setSteps((list) => list.map((step, i) => (i === index ? { ...step, ...changes } : step)));
  }

  function move(index: number, direction: -1 | 1) {
    const target = index + direction;
    // The request step must stay first — it is the requester's own step.
    if (index === 0 || target < 1 || target >= steps.length) return;
    setSteps((list) => {
      const next = [...list];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }

  function addStep() {
    setSteps((list) => [...list, {
      position: list.length + 1, name: "New step", name_sw: null, label: "New step",
      role: "finance", role_label: "Finance", assigned_user_id: null, assignee_hint: "Assign a person or role",
      can_sign: false, can_approve: true, can_reject: true, can_request_changes: true, can_pay: false,
      can_print: true, can_download: true, requires_signature: false,
      min_amount: null, max_amount: null, is_request_step: false,
    }]);
  }

  async function save() {
    if (!current) return;
    setBusy(true);
    try {
      const res = await api.put<{ data: Workflow }>(`/workflows/${current.id}`, {
        name: current.name,
        description: current.description,
        is_default: current.is_default,
        is_active: current.is_active,
        steps: steps.map((step, i) => ({
          id: step.id, position: i + 1, name: step.name, name_sw: step.name_sw, role: step.role,
          assigned_user_id: step.assigned_user_id, assignee_hint: step.assignee_hint,
          can_sign: step.can_sign, can_approve: step.can_approve, can_reject: step.can_reject,
          can_request_changes: step.can_request_changes, can_print: step.can_print,
          can_download: step.can_download, requires_signature: step.can_sign,
          min_amount: step.min_amount, max_amount: step.max_amount,
        })),
      });
      setCurrent(res.data);
      setSteps(res.data.steps.map((s) => ({ ...s })));
      toast("Workflow saved", `${res.data.steps.length} steps · applies to vouchers created from now on.`, "ok");
      load();
    } catch (err) {
      reportError(err, "Could not save the workflow");
    } finally { setBusy(false); }
  }

  async function applyPreset(key: string) {
    setBusy(true);
    try {
      const res = await api.post<{ data: Workflow }>("/workflows/apply-preset", { preset: key });
      toast("Workflow applied", res.data.route_summary ?? res.data.name, "ok");
      setPresetDialog(false);
      load();
    } catch (err) {
      reportError(err, "Could not apply the preset");
    } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!workflows) return <LoadingBlock rows={5} />;
  if (!current) return <div>No workflow configured.</div>;

  const approvalLevels = Math.max(0, steps.length - 1);

  return (
    <div>
      <Banner tone="accent" icon="ph-info" title={t("currentRoute")}>
        {steps.map((s) => s.role_label ?? s.role).join(" → ")} → {t("completed")}
        {" · "}{approvalLevels} approval {approvalLevels === 1 ? "level" : "levels"}
      </Banner>

      <SectionTitle actions={
        <>
          <button className="btn btn-secondary btn-sm" onClick={() => setPresetDialog(true)}>{t("presets")}</button>
          <button className="btn btn-primary btn-sm" onClick={save} disabled={busy}>
            {busy ? <Spinner /> : t("saveWorkflow")}
          </button>
        </>
      }>{current.name}</SectionTitle>

      <div style={{ margin: "0 0 var(--space-4)", maxWidth: "78ch" }}>
        <Note>{t("isolationNote").replace("Acme Tanzania Ltd", company?.name ?? "this company")}</Note>
      </div>

      <div style={{ display: "grid", gap: "var(--space-3)" }}>
        {steps.map((step, index) => (
          <div key={step.id ?? `new-${index}`} style={{
            border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-4)",
            display: "grid", gap: "var(--space-3)",
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", flexWrap: "wrap" }}>
              <div style={{
                width: 30, height: 30, flex: "none", display: "grid", placeItems: "center",
                background: "var(--color-text)", color: "var(--color-bg)", borderRadius: "var(--radius-md)",
                fontFamily: "var(--font-heading)", fontWeight: 600,
              }}>{index + 1}</div>
              <input className="input" value={step.name} onChange={(e) => patch(index, { name: e.target.value })}
                style={{ maxWidth: 260 }} aria-label={`Step ${index + 1} name`} />
              <select className="input" value={step.role} disabled={index === 0}
                onChange={(e) => patch(index, { role: e.target.value as WorkflowStep["role"] })}
                style={{ maxWidth: 180 }} aria-label={`Step ${index + 1} role`}>
                {ROLE_OPTIONS.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
              <div style={{ flex: 1 }} />
              <button className="btn btn-ghost btn-sm" onClick={() => move(index, -1)} disabled={index <= 1} title={t("moveEarlier")}>
                <Icon name="ph-arrow-up" size={14} />
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => move(index, 1)} disabled={index === 0 || index >= steps.length - 1} title={t("moveLater")}>
                <Icon name="ph-arrow-down" size={14} />
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => setSteps((l) => l.filter((_, i) => i !== index))}
                disabled={index === 0} title={t("removeStep")} style={{ color: "var(--color-accent-2-700)" }}>
                <Icon name="ph-trash" size={14} />
              </button>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
              <Field label={t("whoActs")} htmlFor={`step-user-${index}`}>
                <select id={`step-user-${index}`} className="input" value={step.assigned_user_id ?? ""}
                  onChange={(e) => patch(index, { assigned_user_id: e.target.value ? Number(e.target.value) : null })}>
                  <option value="">By role ({ROLE_OPTIONS.find((r) => r.value === step.role)?.label})</option>
                  {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </Field>
              <Field label="Applies from" htmlFor={`step-min-${index}`} hint={t("amountThresholds")}>
                <input id={`step-min-${index}`} className="input" inputMode="decimal" value={step.min_amount ?? ""}
                  placeholder="Any amount"
                  onChange={(e) => patch(index, { min_amount: e.target.value ? Number(e.target.value) : null })} />
              </Field>
              <Field label="Applies up to" htmlFor={`step-max-${index}`}>
                <input id={`step-max-${index}`} className="input" inputMode="decimal" value={step.max_amount ?? ""}
                  placeholder="No ceiling"
                  onChange={(e) => patch(index, { max_amount: e.target.value ? Number(e.target.value) : null })} />
              </Field>
            </div>

            <div>
              <div style={{ fontSize: 12, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 8 }}>
                {t("permittedHere")}
              </div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {CAPS.map((cap) => {
                  const on = Boolean(step[cap.key]);
                  const locked = index === 0 && cap.key !== "can_print";
                  return (
                    <button key={String(cap.key)} type="button" disabled={locked}
                      onClick={() => patch(index, { [cap.key]: !on } as Partial<WorkflowStep>)}
                      aria-pressed={on}
                      style={{
                        display: "inline-flex", alignItems: "center", gap: 6, cursor: locked ? "not-allowed" : "pointer",
                        border: `1px solid ${on ? "var(--color-accent-500)" : "var(--color-neutral-300)"}`,
                        background: on ? "var(--color-accent-100)" : "transparent",
                        color: on ? "var(--color-accent-800)" : "var(--color-neutral-600)",
                        borderRadius: "var(--radius-md)", padding: "6px 11px", fontSize: 13.5,
                        fontFamily: "var(--font-body)", opacity: locked ? .5 : 1,
                      }}>
                      <Icon name={on ? "ph-check-circle" : "ph-circle"} size={15} />
                      {cap.label}
                    </button>
                  );
                })}
              </div>
              {step.can_sign && !step.can_approve && index > 0 && (
                <div style={{ fontSize: 13, color: "var(--color-neutral-700)", marginTop: 8, borderLeft: "2px solid var(--color-accent-300)", paddingLeft: 10 }}>
                  This step signs only. After signing, its holder submits the voucher onward — the approve or reject decision belongs to a later step.
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      <button className="btn btn-secondary" onClick={addStep} style={{ marginTop: "var(--space-3)" }}>
        <Icon name="ph-plus" size={15} /> {t("addStep")}
      </button>

      <Dialog open={presetDialog} title={t("presets")} onClose={() => setPresetDialog(false)}>
        <div style={{ display: "grid", gap: "var(--space-2)" }}>
          {presets.map((preset) => (
            <button key={preset.key} onClick={() => applyPreset(preset.key)} disabled={busy}
              style={{
                textAlign: "left", cursor: "pointer", border: "1px solid var(--color-divider)",
                borderRadius: "var(--radius-md)", padding: "var(--space-3)", background: "transparent",
                fontFamily: "var(--font-body)", color: "var(--color-text)",
              }}>
              <div style={{ fontWeight: 600 }}>{preset.name}</div>
              <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)" }}>{preset.description}</div>
            </button>
          ))}
        </div>
        <div style={{ fontSize: 13, color: "var(--color-neutral-600)", marginTop: "var(--space-2)" }}>
          Applying a preset replaces the current default route. Vouchers already in flight keep the route they started on.
        </div>
      </Dialog>
    </div>
  );
}

/* ──────────────────────────────────────────────── voucher types ─────────── */

function VoucherTypes() {
  const { t, toast, reportError } = useApp();
  const [types, setTypes] = useState<VoucherType[] | null>(null);
  const [dialog, setDialog] = useState(false);
  const [editing, setEditing] = useState<VoucherType | null>(null);
  const [form, setForm] = useState({ name: "", name_sw: "", code: "", prefix: "", seq_padding: 6, next_number: 1, reset_yearly: true });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: VoucherType[] }>("/voucher-types", { include_inactive: true })
      .then((r) => setTypes(r.data)).catch(() => setTypes([]));
  }, []);

  useEffect(load, [load]);

  function openCreate() {
    setEditing(null);
    setForm({ name: "", name_sw: "", code: "", prefix: "", seq_padding: 6, next_number: 1, reset_yearly: true });
    setFormError(null); setDialog(true);
  }

  function openEdit(type: VoucherType) {
    setEditing(type);
    setForm({
      name: type.name, name_sw: type.name_sw ?? "", code: type.code, prefix: type.prefix,
      seq_padding: type.seq_padding, next_number: type.next_number, reset_yearly: type.reset_yearly,
    });
    setFormError(null); setDialog(true);
  }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      if (editing) await api.put(`/voucher-types/${editing.id}`, form);
      else await api.post("/voucher-types", form);
      toast(editing ? "Voucher type updated" : "Voucher type created", form.name, "ok");
      setDialog(false); load();
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the voucher type");
    } finally { setBusy(false); }
  }

  if (!types) return <LoadingBlock rows={4} />;

  return (
    <div>
      <SectionTitle actions={<button className="btn btn-primary btn-sm" onClick={openCreate}><Icon name="ph-plus" size={14} /> {t("add")}</button>}>
        {t("voucherSettings")}
      </SectionTitle>

      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr><th>Type</th><th>Code</th><th>Prefix</th><th>Next number</th><th style={{ textAlign: "right" }}>{t("vouchers")}</th><th>{t("status")}</th><th /></tr>
          </thead>
          <tbody>
            {types.map((type) => (
              <tr key={type.id}>
                <td style={{ fontWeight: 500 }}>{type.name}</td>
                <td style={{ color: "var(--color-neutral-700)" }}>{type.code}</td>
                <td>{type.prefix}</td>
                <td style={{ fontVariantNumeric: "tabular-nums" }}>{type.next_number_preview}</td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{type.vouchers_count ?? 0}</td>
                <td><span className={`tag ${type.is_active ? "tag-accent" : "tag-neutral"}`}>{type.is_active ? t("active") : "Inactive"}</span></td>
                <td style={{ textAlign: "right" }}>
                  <button className="btn btn-ghost btn-sm" onClick={() => openEdit(type)} aria-label={`Edit ${type.name}`}>
                    <Icon name="ph-pencil-simple" size={14} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Dialog open={dialog} title={editing ? t("edit") : t("add")} onClose={() => setDialog(false)}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || !form.code || !form.prefix}>
            {busy ? <Spinner /> : t("save")}
          </button>
        </>}>
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <Field label="Name (English)" htmlFor="vt-name" error={formError?.field("name")} required>
            <input id="vt-name" className="input" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} required />
          </Field>
          <Field label="Name (Swahili)" htmlFor="vt-name-sw">
            <input id="vt-name-sw" className="input" value={form.name_sw} onChange={(e) => setForm((f) => ({ ...f, name_sw: e.target.value }))} />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Code" htmlFor="vt-code" error={formError?.field("code")} required>
              <input id="vt-code" className="input" value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value }))} required />
            </Field>
            <Field label="Prefix" htmlFor="vt-prefix" error={formError?.field("prefix")} hint="e.g. PV → PV-2026-000001" required>
              <input id="vt-prefix" className="input" value={form.prefix} onChange={(e) => setForm((f) => ({ ...f, prefix: e.target.value.toUpperCase() }))} required />
            </Field>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Digits" htmlFor="vt-pad">
              <input id="vt-pad" className="input" type="number" min={1} max={10} value={form.seq_padding}
                onChange={(e) => setForm((f) => ({ ...f, seq_padding: Number(e.target.value) }))} />
            </Field>
            <Field label="Next number" htmlFor="vt-next">
              <input id="vt-next" className="input" type="number" min={1} value={form.next_number}
                onChange={(e) => setForm((f) => ({ ...f, next_number: Number(e.target.value) }))} />
            </Field>
          </div>
          <label className="radio">
            <input type="checkbox" checked={form.reset_yearly} onChange={(e) => setForm((f) => ({ ...f, reset_yearly: e.target.checked }))} />
            <span className="dot" />
            Reset the sequence each year
          </label>
        </div>
      </Dialog>
    </div>
  );
}

/* ─────────────────────────────────────────────── company profile ────────── */

function CompanyProfile() {
  const { t, company, refresh, toast, reportError } = useApp();
  const [form, setForm] = useState({ name: "", legal_name: "", email: "", phone: "", address: "", website: "", currency: "TZS", locale: "en", timezone: "" });
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!company) return;
    setForm({
      name: company.name, legal_name: company.legal_name ?? "", email: company.email,
      phone: company.phone ?? "", address: company.address ?? "", website: company.website ?? "",
      currency: company.currency, locale: company.locale, timezone: company.timezone,
    });
  }, [company]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api.put<{ data: Company }>("/company", form);
      await refresh();
      toast("Company updated", form.name, "ok");
    } catch (err) { reportError(err, "Could not save the company profile"); }
    finally { setBusy(false); }
  }

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  if (!company) return <LoadingBlock rows={4} />;

  return (
    <form onSubmit={save} style={{ display: "grid", gap: "var(--space-3)", maxWidth: 620 }}>
      <Field label={t("companyName")} htmlFor="c-name" required>
        <input id="c-name" className="input" value={form.name} onChange={set("name")} required />
      </Field>
      <Field label="Legal name" htmlFor="c-legal"><input id="c-legal" className="input" value={form.legal_name} onChange={set("legal_name")} /></Field>
      <Field label={t("businessEmail")} htmlFor="c-email" required>
        <input id="c-email" className="input" type="email" value={form.email} onChange={set("email")} required />
      </Field>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)" }}>
        <Field label={t("phone")} htmlFor="c-phone"><input id="c-phone" className="input" value={form.phone} onChange={set("phone")} /></Field>
        <Field label={t("website")} htmlFor="c-web"><input id="c-web" className="input" value={form.website} onChange={set("website")} /></Field>
      </div>
      <Field label={t("address")} htmlFor="c-address"><input id="c-address" className="input" value={form.address} onChange={set("address")} /></Field>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "var(--space-3)" }}>
        <Field label={t("currency")} htmlFor="c-currency">
          <select id="c-currency" className="input" value={form.currency} onChange={set("currency")}>
            <option>TZS</option><option>KES</option><option>USD</option><option>EUR</option>
          </select>
        </Field>
        <Field label={t("language")} htmlFor="c-locale">
          <select id="c-locale" className="input" value={form.locale} onChange={set("locale")}>
            <option value="en">English</option><option value="sw">Kiswahili</option>
          </select>
        </Field>
      </div>
      <div><button className="btn btn-primary" disabled={busy}>{busy ? <Spinner /> : t("saveChanges")}</button></div>
    </form>
  );
}
