"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import {
  Choice, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, Note, Spinner,
} from "@/components/ui";
import { FormSection, SettingsLayout } from "@/components/app-ui";
import { invalidateWorkflows } from "@/lib/use-workflows";
import { workflowPayload } from "@/lib/workflow-payload";
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

export default function SettingsPage() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("workflow");

  // The section lives in the address (#workflow, #types, #company), so the
  // settings menu can link straight to it and a refresh keeps your place.
  useEffect(() => {
    const read = () => {
      const hash = window.location.hash.replace("#", "");
      setTab(hash === "types" || hash === "company" ? hash : "workflow");
    };
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, []);

  const heading = tab === "workflow" ? t("approvalWorkflow") : tab === "types" ? t("voucherSettings") : t("companyProfile");

  return (
    <SettingsLayout title={heading} sub={tab === "workflow" ? t("wfIntro") : undefined}>
      {tab === "workflow" && <WorkflowBuilder />}
      {tab === "types" && <VoucherTypes />}
      {tab === "company" && <CompanyProfile />}
    </SettingsLayout>
  );
}

/* ─────────────────────────────────────────────── workflow builder ───────── */

/*
 * What a step may do. Every flag the backend stores is listed — and, just as
 * important, every flag is SENT on save. The previous builder omitted can_pay
 * from its payload; the API defaults a missing flag to false, so saving any
 * workflow silently removed the payment capability from every step and left
 * the company with nobody able to pay a voucher.
 */
const CAPS: { key: CapKey; label: string; icon: string }[] = [
  { key: "can_sign", label: "Sign", icon: "ph-signature" },
  { key: "can_approve", label: "Approve", icon: "ph-seal-check" },
  { key: "can_reject", label: "Reject", icon: "ph-x-circle" },
  { key: "can_request_changes", label: "Request changes", icon: "ph-arrow-u-up-left" },
  { key: "can_pay", label: "Pay", icon: "ph-wallet" },
  { key: "can_print", label: "Print", icon: "ph-printer" },
  { key: "can_download", label: "Download", icon: "ph-download-simple" },
];

type CapKey = "can_sign" | "can_approve" | "can_reject" | "can_request_changes" | "can_pay" | "can_print" | "can_download";

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
  const [chosenPreset, setChosenPreset] = useState<string | null>(null);
  const [open, setOpen] = useState<number | null>(null);
  const [dirty, setDirty] = useState(false);
  const [pendingSwitch, setPendingSwitch] = useState<Workflow | null>(null);

  const pick = useCallback((wf: Workflow | null) => {
    setCurrent(wf);
    setSteps(wf ? wf.steps.map((s) => ({ ...s })) : []);
    setDirty(false);
    setOpen(null);
  }, []);

  const load = useCallback((keepId?: number) => {
    setError(null);
    api.get<{ data: Workflow[] }>("/workflows")
      .then((r) => {
        setWorkflows(r.data);
        const keep = keepId ? r.data.find((w) => w.id === keepId) : null;
        pick(keep ?? r.data.find((w) => w.is_default) ?? r.data[0] ?? null);
      })
      .catch((err) => setError(err.message));
  }, [pick]);

  useEffect(() => {
    load();
    api.get<{ data: DirectoryUser[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
    api.get<{ data: typeof presets }>("/workflows/presets").then((r) => setPresets(r.data)).catch(() => undefined);
  }, [load]);

  function patch(index: number, changes: Partial<WorkflowStep>) {
    setSteps((list) => list.map((step, i) => (i === index ? { ...step, ...changes } : step)));
    setDirty(true);
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
    setOpen(target);
    setDirty(true);
  }

  function addStep() {
    setSteps((list) => [...list, {
      position: list.length + 1, name: "New step", name_sw: null, label: "New step",
      role: "finance", role_label: "Finance", assigned_user_id: null, assignee_hint: "Assign a person or role",
      can_sign: false, can_approve: true, can_reject: true, can_request_changes: true, can_pay: false,
      can_print: true, can_download: true, requires_signature: false,
      min_amount: null, max_amount: null, is_request_step: false,
    }]);
    setOpen(steps.length);
    setDirty(true);
  }

  function removeStep(index: number) {
    setSteps((l) => l.filter((_, i) => i !== index));
    setOpen(null);
    setDirty(true);
  }

  async function save() {
    if (!current) return;
    setBusy(true);
    try {
      const res = await api.put<{ data: Workflow }>(`/workflows/${current.id}`, workflowPayload(current, steps));
      invalidateWorkflows(company?.id);
      toast("Workflow saved", `${res.data.steps.length} steps · applies to vouchers created from now on.`, "ok");
      load(res.data.id);
    } catch (err) {
      reportError(err, "Could not save the workflow");
    } finally { setBusy(false); }
  }

  async function applyPreset(key: string) {
    setBusy(true);
    try {
      const res = await api.post<{ data: Workflow }>("/workflows/apply-preset", { preset: key });
      invalidateWorkflows(company?.id);
      toast("Workflow applied", res.data.route_summary ?? res.data.name, "ok");
      setPresetDialog(false);
      setChosenPreset(null);
      load(res.data.id);
    } catch (err) {
      reportError(err, "Could not apply the preset");
    } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={() => load()} />;
  if (!workflows) return <LoadingBlock rows={5} />;
  if (!current) {
    return (
      <div className="vf-panel">
        <EmptyState icon="ph-flow-arrow" title="No workflow configured" body="Start from a preset, then adjust each step."
          action={<button className="btn btn-primary" onClick={() => setPresetDialog(true)}>{t("presets")}</button>} />
      </div>
    );
  }

  const noPayer = steps.length > 1 && !steps.some((s) => s.can_pay);
  const noDecider = steps.length > 1 && !steps.slice(1).some((s) => s.can_approve);

  return (
    <div className="vf-wf">
      {/* ── which workflow, and its state ── */}
      <div className="vf-panel vf-wf-head">
        <div className="vf-wf-head-main">
          {workflows.length > 1 ? (
            <select className="input vf-wf-select" value={current.id} aria-label="Workflow"
              onChange={(e) => {
                const next = workflows.find((w) => w.id === Number(e.target.value)) ?? null;
                if (dirty) setPendingSwitch(next);
                else pick(next);
              }}>
              {workflows.map((w) => <option key={w.id} value={w.id}>{w.name}{w.is_default ? " — default" : ""}</option>)}
            </select>
          ) : (
            <h2 className="vf-wf-name">{current.name}</h2>
          )}
          <div className="vf-wf-badges">
            {current.is_default && <span className="badge tone-info">Default</span>}
            <span className={`badge ${current.is_active ? "tone-ok" : "tone-neutral"}`}>{current.is_active ? "Active" : "Inactive"}</span>
            {dirty && <span className="badge tone-warn">Unsaved changes</span>}
          </div>
        </div>
        <div className="vf-wf-head-actions">
          <label className="switch">
            <input type="checkbox" checked={current.is_active}
              onChange={(e) => { setCurrent({ ...current, is_active: e.target.checked }); setDirty(true); }} />
            <span className="track" />
            Active
          </label>
          <button className="btn btn-secondary btn-sm" onClick={() => setPresetDialog(true)}>
            <Icon name="ph-magic-wand" size={15} /> {t("presets")}
          </button>
          <button className="btn btn-primary btn-sm" onClick={save} disabled={busy || !dirty}>
            {busy ? <Spinner /> : <><Icon name="ph-floppy-disk" size={15} /> {t("saveWorkflow")}</>}
          </button>
        </div>
      </div>

      {(noPayer || noDecider) && (
        <div className="vf-alert tone-warn" style={{ marginTop: 12 }}>
          <Icon name="ph-warning" size={18} style={{ flex: "none", marginTop: 1 }} />
          <div className="vf-alert-text">
            {noDecider && <div><strong>No step can approve.</strong> Vouchers on this route can never be approved.</div>}
            {noPayer && <div><strong>No step can pay.</strong> Approved vouchers on this route can never be paid.</div>}
          </div>
        </div>
      )}

      {/* ── the route, drawn ── */}
      <ol className="vf-flow">
        <li className="vf-flow-node vf-flow-start">
          <span className="vf-flow-node-icon"><Icon name="ph-file-plus" size={16} /></span>
          Voucher raised
        </li>

        {steps.map((step, index) => {
          const request = index === 0;
          const expanded = open === index;
          const caps = CAPS.filter((c) => step[c.key]);
          const assignee = step.assigned_user_id ? people.find((p) => p.id === step.assigned_user_id)?.name : null;
          const threshold = step.min_amount != null || step.max_amount != null;

          return (
            <li key={step.id ?? `new-${index}`} className="vf-flow-step" data-open={expanded ? "true" : "false"}>
              <div className="vf-flow-card">
                <button type="button" className="vf-flow-card-head" onClick={() => setOpen(expanded ? null : index)} aria-expanded={expanded}>
                  <span className="vf-flow-num">{index + 1}</span>
                  <span className="vf-flow-card-text">
                    <span className="vf-flow-card-name">{step.name}</span>
                    <span className="vf-flow-card-sub">
                      {request ? "Requester" : assignee ?? ROLE_OPTIONS.find((r) => r.value === step.role)?.label}
                      {threshold && ` · ${step.min_amount != null ? `from ${Number(step.min_amount).toLocaleString()}` : ""}${step.min_amount != null && step.max_amount != null ? " " : ""}${step.max_amount != null ? `up to ${Number(step.max_amount).toLocaleString()}` : ""}`}
                    </span>
                  </span>
                  <span className="vf-flow-caps">
                    {caps.filter((c) => c.key !== "can_print" && c.key !== "can_download").map((c) => (
                      <span key={c.key} className="vf-flow-cap" title={c.label}><Icon name={c.icon} size={14} /><span>{c.label}</span></span>
                    ))}
                  </span>
                  <Icon name="ph-caret-down" size={16} style={{ color: "var(--color-neutral-500)", transform: expanded ? "rotate(180deg)" : "none", transition: "transform var(--dur) var(--ease-out)", flex: "none" }} />
                </button>

                {expanded && (
                  <div className="vf-flow-card-body vf-rise">
                    <div className="vf-form-row">
                      <Field label="Step name" htmlFor={`step-name-${index}`}>
                        <input id={`step-name-${index}`} className="input" value={step.name} onChange={(e) => patch(index, { name: e.target.value })} />
                      </Field>
                      <Field label="Role" htmlFor={`step-role-${index}`}>
                        <select id={`step-role-${index}`} className="input" value={step.role} disabled={request}
                          onChange={(e) => patch(index, { role: e.target.value as WorkflowStep["role"] })}>
                          {ROLE_OPTIONS.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
                        </select>
                      </Field>
                    </div>

                    {!request && (
                      <div className="vf-form-row">
                        <Field label={t("whoActs")} htmlFor={`step-user-${index}`} hint="A named person overrides the role.">
                          <select id={`step-user-${index}`} className="input" value={step.assigned_user_id ?? ""}
                            onChange={(e) => patch(index, { assigned_user_id: e.target.value ? Number(e.target.value) : null })}>
                            <option value="">Anyone with the {ROLE_OPTIONS.find((r) => r.value === step.role)?.label} role</option>
                            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                          </select>
                        </Field>
                        <Field label="Applies from (amount)" htmlFor={`step-min-${index}`} hint={t("amountThresholds")}>
                          <input id={`step-min-${index}`} className="input tnum" inputMode="decimal" value={step.min_amount ?? ""} placeholder="Any amount"
                            onChange={(e) => patch(index, { min_amount: e.target.value ? Number(e.target.value) : null })} />
                        </Field>
                        <Field label="Applies up to (amount)" htmlFor={`step-max-${index}`}>
                          <input id={`step-max-${index}`} className="input tnum" inputMode="decimal" value={step.max_amount ?? ""} placeholder="No ceiling"
                            onChange={(e) => patch(index, { max_amount: e.target.value ? Number(e.target.value) : null })} />
                        </Field>
                      </div>
                    )}

                    <div className="field">
                      <span className="vf-label">{t("permittedHere")}</span>
                      <div className="vf-caps">
                        {CAPS.map((cap) => {
                          const on = Boolean(step[cap.key]);
                          const locked = request && cap.key !== "can_print" && cap.key !== "can_download";
                          return (
                            <button key={cap.key} type="button" className="vf-cap" disabled={locked} aria-pressed={on}
                              onClick={() => patch(index, { [cap.key]: !on } as Partial<WorkflowStep>)}>
                              <Icon name={cap.icon} size={15} /> {cap.label}
                            </button>
                          );
                        })}
                      </div>
                      {step.can_sign && step.can_approve && !request && (
                        <label className="radio" style={{ marginTop: 10 }}>
                          <input type="checkbox" checked={step.requires_signature}
                            onChange={(e) => patch(index, { requires_signature: e.target.checked })} />
                          <span className="dot" />
                          Signature required before approving
                        </label>
                      )}
                      {step.can_sign && !step.can_approve && !request && (
                        <p className="field-hint">This step signs only. Its holder signs, then submits onward — the approve or reject decision belongs to a later step.</p>
                      )}
                      {step.can_request_changes && !request && (
                        <p className="field-hint">Requesting changes returns the voucher to the requester to revise and resubmit.</p>
                      )}
                    </div>

                    {!request && (
                      <div className="vf-flow-card-tools">
                        <button className="btn btn-ghost btn-sm" onClick={() => move(index, -1)} disabled={index <= 1}>
                          <Icon name="ph-arrow-up" size={15} /> {t("moveEarlier")}
                        </button>
                        <button className="btn btn-ghost btn-sm" onClick={() => move(index, 1)} disabled={index >= steps.length - 1}>
                          <Icon name="ph-arrow-down" size={15} /> {t("moveLater")}
                        </button>
                        <div style={{ flex: 1 }} />
                        <button className="btn btn-ghost btn-sm vf-text-bad" onClick={() => removeStep(index)}>
                          <Icon name="ph-trash" size={15} /> {t("removeStep")}
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </li>
          );
        })}

        <li className="vf-flow-add">
          <button className="btn btn-secondary btn-sm" onClick={addStep}>
            <Icon name="ph-plus" size={15} /> {t("addStep")}
          </button>
        </li>

        <li className="vf-flow-node vf-flow-end">
          <span className="vf-flow-node-icon"><Icon name="ph-check" size={16} /></span>
          {t("completed")}
        </li>
      </ol>

      {/* ── the same permissions, as a matrix: every step against every capability ── */}
      <section className="vf-panel app-wf-matrix">
        <div className="vf-panel-head">
          <div className="vf-panel-head-main">
            <h2>{t("permittedHere")}</h2>
            <div className="vf-panel-sub">Sign and approve are separate permissions. Pay releases money and never approves.</div>
          </div>
        </div>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Step</th>
                {CAPS.map((cap) => <th key={cap.key} className="app-wf-cap-col"><Icon name={cap.icon} size={14} /> {cap.label}</th>)}
              </tr>
            </thead>
            <tbody>
              {steps.map((step, index) => {
                const request = index === 0;
                return (
                  <tr key={step.id ?? `m-${index}`}>
                    <td>
                      <div className="app-wf-step"><span className="vf-flow-num">{index + 1}</span><span>{step.name}</span></div>
                    </td>
                    {CAPS.map((cap) => {
                      const on = Boolean(step[cap.key]);
                      const locked = request && cap.key !== "can_print" && cap.key !== "can_download";
                      return (
                        <td key={cap.key} className="app-wf-cap-col">
                          <input type="checkbox" checked={on} disabled={locked}
                            aria-label={`${step.name}: ${cap.label}`}
                            onChange={() => patch(index, { [cap.key]: !on } as Partial<WorkflowStep>)} />
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <div style={{ marginTop: 16 }}>
        <Note>{t("isolationNote").replace("this company", company?.name ?? "this company")}</Note>
      </div>

      <Dialog
        open={!!pendingSwitch}
        icon="ph-warning"
        tone="warn"
        title="Discard unsaved changes?"
        sub={`Your edits to ${current.name} have not been saved.`}
        onClose={() => setPendingSwitch(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setPendingSwitch(null)}>Keep editing</button>
            <button className="btn btn-danger-solid" onClick={() => { pick(pendingSwitch); setPendingSwitch(null); }}>Discard changes</button>
          </>
        }
      />

      {/* Presets replace the company's default route, so choosing one is not the same as applying it. */}
      <Dialog
        open={presetDialog}
        icon="ph-magic-wand"
        title={t("presets")}
        sub="Applying a preset replaces the current default route. Vouchers already in flight keep the route they started on."
        onClose={() => { setPresetDialog(false); setChosenPreset(null); }}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => { setPresetDialog(false); setChosenPreset(null); }} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" disabled={busy || !chosenPreset} onClick={() => chosenPreset && applyPreset(chosenPreset)}>
              {busy ? <Spinner /> : "Apply preset"}
            </button>
          </>
        }
      >
        <div className="vf-stack" style={{ gap: 8 }}>
          {presets.map((preset) => (
            <Choice key={preset.key} selected={chosenPreset === preset.key} onSelect={() => setChosenPreset(preset.key)}
              icon="ph-flow-arrow" label={preset.name} sub={preset.description} />
          ))}
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
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main app-panel-title"><h2>{t("voucherSettings")}</h2><span className="vf-count">{types.length}</span></div>
        <button className="btn btn-primary btn-sm" onClick={openCreate}><Icon name="ph-plus" size={14} /> {t("add")}</button>
      </div>

      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr><th>Type</th><th>Code</th><th>Prefix</th><th>Next number</th><th className="num">{t("vouchers")}</th><th>{t("status")}</th><th /></tr>
          </thead>
          <tbody>
            {types.map((type) => (
              <tr key={type.id}>
                <td style={{ fontWeight: 500 }}>{type.name}</td>
                <td style={{ color: "var(--color-neutral-700)" }}>{type.code}</td>
                <td>{type.prefix}</td>
                <td style={{ fontVariantNumeric: "tabular-nums" }}>{type.next_number_preview}</td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{type.vouchers_count ?? 0}</td>
                <td><span className={`badge ${type.is_active ? "tone-ok" : "tone-neutral"}`}>{type.is_active ? t("active") : "Inactive"}</span></td>
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
    </section>
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
    <form onSubmit={save} className="vf-panel">
      <div className="vf-panel-pad">
        <FormSection title={t("companyProfile")} description="The name and legal identity printed on every voucher.">
          <Field label={t("companyName")} htmlFor="c-name" required>
            <input id="c-name" className="input" value={form.name} onChange={set("name")} required />
          </Field>
          <Field label="Legal name" htmlFor="c-legal"><input id="c-legal" className="input" value={form.legal_name} onChange={set("legal_name")} /></Field>
        </FormSection>
        <FormSection title={t("phone")} description="How people reach the company.">
          <Field label={t("businessEmail")} htmlFor="c-email" required>
            <input id="c-email" className="input" type="email" value={form.email} onChange={set("email")} required />
          </Field>
          <div className="vf-form-row">
            <Field label={t("phone")} htmlFor="c-phone"><input id="c-phone" className="input" value={form.phone} onChange={set("phone")} /></Field>
            <Field label={t("website")} htmlFor="c-web"><input id="c-web" className="input" value={form.website} onChange={set("website")} /></Field>
          </div>
          <Field label={t("address")} htmlFor="c-address"><input id="c-address" className="input" value={form.address} onChange={set("address")} /></Field>
        </FormSection>
        <FormSection title={t("currency")} description="Defaults for new vouchers.">
          <div className="vf-form-row">
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
        </FormSection>
      </div>
      <div className="app-form-foot">
        <span className="field-hint">{company.name}</span>
        <div className="app-form-foot-end"><button className="btn btn-primary" disabled={busy}>{busy ? <Spinner /> : t("saveChanges")}</button></div>
      </div>
    </form>
  );
}
