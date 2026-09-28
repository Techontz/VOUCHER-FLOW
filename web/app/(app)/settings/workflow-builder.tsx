"use client";

/*
 * The approval workflow builder: which workflows the company runs, which
 * voucher types each one routes, and — level by level — who acts, in what
 * order, for which amounts and with which permissions. Below the route sits a
 * read-only matrix of who that resolves to in every department, which is how
 * an administrator sees the person responsible for each approval stage.
 */

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { Choice, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, Note, Spinner } from "@/components/ui";
import { invalidateWorkflows } from "@/lib/use-workflows";
import { workflowPayload } from "@/lib/workflow-payload";
import type { RoutingGap, VoucherType, Workflow, WorkflowRouting, WorkflowStep } from "@/lib/types";

interface DirectoryUser { id: number; name: string; role: string; job_title?: string | null; department_id?: number | null }
interface DepartmentRef { id: number; name: string }
interface Preset { key: string; name: string; description: string }

type Role = WorkflowStep["role"];

/** Roles a non-request level may be given. "custom" is reached through "Specific person". */
const LEVEL_ROLES: Role[] = ["hod", "manager", "ceo", "finance", "director", "cashier"];

const ROLE_KEYS: Record<string, MessageKey> = {
  employee: "wfcRoleEmployee", hod: "wfcRoleHod", manager: "wfcRoleManager", finance: "wfcRoleFinance",
  ceo: "wfcRoleCeo", cashier: "wfcRoleCashier", director: "wfcRoleDirector",
  company_admin: "wfcRoleAdmin", custom: "wfcSpecificPerson",
};

const GAP_KEYS: Record<RoutingGap, MessageKey> = {
  no_hod: "wfcGapNoHod", inactive_hod: "wfcGapInactiveHod",
  no_manager: "wfcGapNoManager", inactive_manager: "wfcGapInactiveManager",
  inactive_person: "wfcGapInactivePerson", missing_person: "wfcGapMissingPerson",
  no_person_named: "wfcGapNoPerson", no_one_with_role: "wfcGapNoRole",
};

/** Gaps an administrator fixes on the Departments page rather than here. */
const DEPARTMENT_GAPS: RoutingGap[] = ["no_hod", "inactive_hod", "no_manager", "inactive_manager"];

/*
 * What a step may do. Every flag the backend stores is listed — and, just as
 * important, every flag is SENT on save. The previous builder omitted can_pay
 * from its payload; the API defaults a missing flag to false, so saving any
 * workflow silently removed the payment capability from every step and left
 * the company with nobody able to pay a voucher.
 */
type CapKey = "can_sign" | "can_approve" | "can_reject" | "can_request_changes" | "can_pay" | "can_print" | "can_download";

const CAPS: { key: CapKey; label: string; icon: string }[] = [
  { key: "can_sign", label: "Sign", icon: "ph-signature" },
  { key: "can_approve", label: "Approve", icon: "ph-seal-check" },
  { key: "can_reject", label: "Reject", icon: "ph-x-circle" },
  { key: "can_request_changes", label: "Request changes", icon: "ph-arrow-u-up-left" },
  { key: "can_pay", label: "Pay", icon: "ph-wallet" },
  { key: "can_print", label: "Print", icon: "ph-printer" },
  { key: "can_download", label: "Download", icon: "ph-download-simple" },
];

/** A step chooses its person by name when it is a "custom" step or names someone. */
const isPersonMode = (step: WorkflowStep) => step.role === "custom" || step.assigned_user_id != null;

interface DetailsForm { name: string; name_sw: string; description: string; voucher_type_id: string }
interface CreateForm extends DetailsForm { source: string }

const blankCreate: CreateForm = { name: "", name_sw: "", description: "", voucher_type_id: "", source: "copy" };

export function WorkflowBuilder() {
  const { t, locale, company, toast, reportError } = useApp();
  const [workflows, setWorkflows] = useState<Workflow[] | null>(null);
  const [steps, setSteps] = useState<WorkflowStep[]>([]);
  const [current, setCurrent] = useState<Workflow | null>(null);
  const [people, setPeople] = useState<DirectoryUser[]>([]);
  const [departments, setDepartments] = useState<DepartmentRef[]>([]);
  const [types, setTypes] = useState<VoucherType[]>([]);
  const [presets, setPresets] = useState<Preset[]>([]);
  const [routing, setRouting] = useState<WorkflowRouting | null>(null);
  const [routingFor, setRoutingFor] = useState<{ id: number; version: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<number | null>(null);
  const [dirty, setDirty] = useState(false);
  const [pendingSwitch, setPendingSwitch] = useState<Workflow | null>(null);
  const [presetDialog, setPresetDialog] = useState(false);
  const [chosenPreset, setChosenPreset] = useState<string | null>(null);
  const [detailsDialog, setDetailsDialog] = useState(false);
  const [details, setDetails] = useState<DetailsForm>({ name: "", name_sw: "", description: "", voucher_type_id: "" });
  const [createDialog, setCreateDialog] = useState(false);
  const [createForm, setCreateForm] = useState<CreateForm>(blankCreate);
  const [deleteDialog, setDeleteDialog] = useState(false);

  const roleName = useCallback((role: string) => (ROLE_KEYS[role] ? t(ROLE_KEYS[role]) : role), [t]);
  const typeName = useCallback((type: { name: string; name_sw: string | null }) =>
    (locale === "sw" && type.name_sw ? type.name_sw : type.name), [locale]);

  const pick = useCallback((wf: Workflow | null) => {
    setCurrent(wf ? { ...wf } : null);
    setSteps(wf ? wf.steps.map((s) => ({ ...s })) : []);
    setDirty(false);
    setOpen(null);
  }, []);

  const load = useCallback((keepId?: number) => {
    api.get<{ data: Workflow[] }>("/workflows")
      .then((r) => {
        setError(null);
        setWorkflows(r.data);
        const keep = keepId ? r.data.find((w) => w.id === keepId) : null;
        pick(keep ?? r.data.find((w) => w.is_default) ?? r.data[0] ?? null);
      })
      .catch((err) => setError(err.message));
  }, [pick]);

  useEffect(() => {
    load();
    api.get<{ data: DirectoryUser[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
    api.get<{ data: DepartmentRef[] }>("/departments").then((r) => setDepartments(r.data)).catch(() => undefined);
    api.get<{ data: VoucherType[] }>("/voucher-types").then((r) => setTypes(r.data)).catch(() => undefined);
    api.get<{ data: Preset[] }>("/workflows/presets").then((r) => setPresets(r.data)).catch(() => undefined);
  }, [load]);

  // The matrix reflects the saved workflow, so it reloads per workflow version.
  const savedId = current?.id;
  const savedVersion = current?.version;
  useEffect(() => {
    if (!savedId || savedVersion === undefined) return;
    let live = true;
    api.get<{ data: WorkflowRouting }>(`/workflows/${savedId}/routing`)
      .then((r) => { if (live) { setRouting(r.data); setRoutingFor({ id: savedId, version: savedVersion }); } })
      .catch(() => { if (live) { setRouting(null); setRoutingFor({ id: savedId, version: savedVersion }); } });
    return () => { live = false; };
  }, [savedId, savedVersion]);

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
      position: list.length + 1, name: "New level", name_sw: null, label: "New level",
      role: "finance", role_label: "Finance", assigned_user_id: null, assignee_hint: null,
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
      toast(t("wfcSaved"), t("wfcSavedSub"), "ok");
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

  async function create() {
    const base = workflows?.find((w) => w.is_default);
    setBusy(true);
    try {
      const fields = {
        name: createForm.name.trim(),
        name_sw: createForm.name_sw.trim() || null,
        description: createForm.description.trim() || null,
        voucher_type_id: createForm.voucher_type_id ? Number(createForm.voucher_type_id) : null,
        is_default: false,
        is_active: true,
      };
      const body = createForm.source === "copy" && base
        ? workflowPayload(fields, base.steps.map((s) => ({ ...s, id: undefined })))
        : { ...fields, from_preset: createForm.source === "copy" ? "default" : createForm.source };
      const res = await api.post<{ data: Workflow }>("/workflows", body);
      invalidateWorkflows(company?.id);
      toast(t("wfcCreated"), res.data.name, "ok");
      setCreateDialog(false);
      setCreateForm(blankCreate);
      load(res.data.id);
    } catch (err) {
      reportError(err, "Could not create the workflow");
    } finally { setBusy(false); }
  }

  async function makeDefault() {
    if (!current) return;
    setBusy(true);
    try {
      const res = await api.post<{ data: Workflow }>(`/workflows/${current.id}/make-default`);
      invalidateWorkflows(company?.id);
      toast(t("wfcMadeDefault"), res.data.name, "ok");
      load(res.data.id);
    } catch (err) {
      reportError(err, "Could not change the default workflow");
    } finally { setBusy(false); }
  }

  async function remove() {
    if (!current) return;
    setBusy(true);
    try {
      await api.delete(`/workflows/${current.id}`);
      invalidateWorkflows(company?.id);
      toast(t("wfcDeleted"), current.name, "warn");
      setDeleteDialog(false);
      load();
    } catch (err) {
      reportError(err, "Could not delete the workflow");
    } finally { setBusy(false); }
  }

  function openDetails() {
    if (!current) return;
    setDetails({
      name: current.name, name_sw: current.name_sw ?? "", description: current.description ?? "",
      voucher_type_id: current.voucher_type_id ? String(current.voucher_type_id) : "",
    });
    setDetailsDialog(true);
  }

  function applyDetails() {
    if (!current) return;
    const typeId = details.voucher_type_id ? Number(details.voucher_type_id) : null;
    const type = types.find((x) => x.id === typeId);
    setCurrent({
      ...current,
      name: details.name.trim() || current.name,
      name_sw: details.name_sw.trim() || null,
      description: details.description.trim() || null,
      voucher_type_id: typeId,
      voucher_type: type ? { id: type.id, name: type.name, name_sw: type.name_sw } : null,
    });
    setDirty(true);
    setDetailsDialog(false);
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

  const noPayer = steps.length > 1 && !steps.slice(1).some((s) => s.can_pay);
  const noDecider = steps.length > 1 && !steps.slice(1).some((s) => s.can_approve);
  const deptName = (id?: number | null) => departments.find((d) => d.id === id)?.name;
  const personLabel = (p: DirectoryUser) => [p.name, roleName(p.role), deptName(p.department_id)].filter(Boolean).join(" · ");

  /** What is wrong with the person side of a level, if anything. */
  const personIssue = (step: WorkflowStep): string | null => {
    if (step.assigned_user_id != null) {
      if (people.some((p) => p.id === step.assigned_user_id)) return null;
      const known = step.assigned_user?.id === step.assigned_user_id ? step.assigned_user : null;
      // /directory lists active users only; a named person missing from it is inactive or gone.
      if (known) return t("wfcPersonInactive").replace("{name}", known.name);
      return people.length ? t("wfcPersonMissing") : null;
    }
    return step.role === "custom" ? t("wfcNoPersonChosen") : null;
  };

  const whoSummary = (step: WorkflowStep, index: number): string => {
    if (index === 0) return t("wfcRequester");
    if (step.assigned_user_id != null) {
      return people.find((p) => p.id === step.assigned_user_id)?.name ?? step.assigned_user?.name ?? t("wfcSpecificPerson");
    }
    if (step.role === "hod") return t("wfcEachHod");
    if (step.role === "manager") return t("wfcEachManager");
    if (step.role === "custom") return t("wfcNoPersonChosen");
    return t("wfcEveryoneWithRole").replace("{role}", roleName(step.role));
  };

  const issues = steps.map((step, index) => (index === 0 ? null : personIssue(step)));
  const bandIssues = steps.map((s) => s.min_amount != null && s.max_amount != null && Number(s.min_amount) > Number(s.max_amount));
  const others = workflows.filter((w) => w.id !== current.id);
  const deleteBlock = workflows.length <= 1 ? t("wfcCannotDeleteOnly")
    : current.is_default ? t("wfcCannotDeleteDefault")
    : (current.in_flight_count ?? 0) > 0 ? t("wfcCannotDeleteInFlight").replace("{count}", String(current.in_flight_count))
    : (current.vouchers_count ?? 0) > 0 ? t("wfcCannotDeleteUsed")
    : null;
  const appliesTo = current.voucher_type ? typeName(current.voucher_type) : t("wfcAllTypes");
  const routingStale = dirty || !routingFor || routingFor.id !== current.id;
  const levelSteps = routing?.steps.filter((s) => !s.is_request_step) ?? [];

  return (
    <div className="vf-wf">
      {/* ── which workflow, where it applies, and its state ── */}
      <div className="vf-panel vf-wf-head">
        <div className="vf-wf-head-main">
          {workflows.length > 1 ? (
            <select className="input vf-wf-select" value={current.id} aria-label="Workflow"
              onChange={(e) => {
                const next = workflows.find((w) => w.id === Number(e.target.value)) ?? null;
                if (dirty) setPendingSwitch(next);
                else pick(next);
              }}>
              {workflows.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.name}{w.is_default ? ` — ${t("wfcDefault")}` : ""}{w.voucher_type ? ` — ${typeName(w.voucher_type)}` : ""}
                </option>
              ))}
            </select>
          ) : (
            <h2 className="vf-wf-name">{current.name}</h2>
          )}
          <div className="vf-wf-badges">
            {current.is_default && <span className="badge tone-info">{t("wfcDefault")}</span>}
            <span className={`badge ${current.is_active ? "tone-ok" : "tone-neutral"}`}>{current.is_active ? t("wfcActive") : t("wfcInactive")}</span>
            <span className="badge tone-neutral">{t("wfcAppliesTo")}: {appliesTo}</span>
            {dirty && <span className="badge tone-warn">{t("wfcUnsaved")}</span>}
          </div>
        </div>
        <div className="vf-wf-head-actions">
          <label className="switch" title={current.is_default ? t("wfcDefaultAllTypes") : undefined}>
            <input type="checkbox" checked={current.is_active} disabled={current.is_default}
              onChange={(e) => { setCurrent({ ...current, is_active: e.target.checked }); setDirty(true); }} />
            <span className="track" />
            {t("wfcActive")}
          </label>
          <button className="btn btn-secondary btn-sm" onClick={openDetails}>
            <Icon name="ph-pencil-simple" size={15} /> {t("wfcDetails")}
          </button>
          <button className="btn btn-secondary btn-sm" onClick={() => { setCreateForm(blankCreate); setCreateDialog(true); }}>
            <Icon name="ph-plus" size={15} /> {t("wfcNewWorkflow")}
          </button>
          <button className="btn btn-secondary btn-sm" onClick={() => setPresetDialog(true)}>
            <Icon name="ph-magic-wand" size={15} /> {t("presets")}
          </button>
          {!current.is_default && (
            <button className="btn btn-secondary btn-sm" onClick={makeDefault} disabled={busy || dirty || current.voucher_type_id != null}
              title={current.voucher_type_id != null ? t("wfcDefaultAllTypes") : undefined}>
              <Icon name="ph-star" size={15} /> {t("wfcMakeDefault")}
            </button>
          )}
          {!current.is_default && (
            <button className="btn btn-ghost btn-sm vf-text-bad" onClick={() => setDeleteDialog(true)} aria-label={t("delete")} title={t("delete")}>
              <Icon name="ph-trash" size={15} />
            </button>
          )}
          <button className="btn btn-primary btn-sm" onClick={save} disabled={busy || !dirty}>
            {busy ? <Spinner /> : <><Icon name="ph-floppy-disk" size={15} /> {t("saveWorkflow")}</>}
          </button>
        </div>
      </div>

      {(noPayer || noDecider) && (
        <div className="vf-alert tone-warn" style={{ marginTop: 12 }}>
          <Icon name="ph-warning" size={18} style={{ flex: "none", marginTop: 1 }} />
          <div className="vf-alert-text">
            {noDecider && <div>{t("wfcNoApprover")}</div>}
            {noPayer && <div>{t("wfcNoPayer")}</div>}
          </div>
        </div>
      )}

      {/* ── the route, drawn as numbered approval levels ── */}
      <ol className="vf-flow">
        <li className="vf-flow-node vf-flow-start">
          <span className="vf-flow-node-icon"><Icon name="ph-file-plus" size={16} /></span>
          Voucher raised
        </li>

        {steps.map((step, index) => {
          const request = index === 0;
          const expanded = open === index;
          const caps = CAPS.filter((c) => step[c.key]);
          const threshold = step.min_amount != null || step.max_amount != null;
          const personMode = isPersonMode(step);
          const issue = issues[index];
          const assignedMissing = step.assigned_user_id != null && !people.some((p) => p.id === step.assigned_user_id);

          return (
            <li key={step.id ?? `new-${index}`} className="vf-flow-step" data-open={expanded ? "true" : "false"}>
              <div className="vf-flow-card">
                <button type="button" className="vf-flow-card-head" onClick={() => setOpen(expanded ? null : index)} aria-expanded={expanded}>
                  <span className="vf-flow-num">{request ? <Icon name="ph-user" size={13} /> : index}</span>
                  <span className="vf-flow-card-text">
                    <span className="vf-flow-card-name">
                      {request
                        ? t("wfcRequest")
                        : <><span className="wfc-level">{t("wfcLevel")} {index}</span> · {step.name}</>}
                    </span>
                    <span className="vf-flow-card-sub">
                      {t("wfcWhoActs")}: {whoSummary(step, index)}
                      {threshold && ` · ${step.min_amount != null ? `from ${Number(step.min_amount).toLocaleString()}` : ""}${step.min_amount != null && step.max_amount != null ? " " : ""}${step.max_amount != null ? `up to ${Number(step.max_amount).toLocaleString()}` : ""}`}
                    </span>
                  </span>
                  {(issue || bandIssues[index]) && <span className="wfc-warn-icon"><Icon name="ph-warning" size={16} /></span>}
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
                      <Field label={t("wfcNameSw")} htmlFor={`step-name-sw-${index}`}>
                        <input id={`step-name-sw-${index}`} className="input" value={step.name_sw ?? ""} onChange={(e) => patch(index, { name_sw: e.target.value || null })} />
                      </Field>
                    </div>

                    {!request && (
                      <div className="field">
                        <span className="vf-label">{t("wfcWhoActs")}</span>
                        <div className="wfc-seg" role="radiogroup" aria-label={t("wfcWhoActs")}>
                          <button type="button" role="radio" aria-checked={!personMode}
                            onClick={() => patch(index, { assigned_user_id: null, role: step.role === "custom" ? "ceo" : step.role })}>
                            <Icon name="ph-users-three" size={15} /> {t("wfcRoleBased")}
                          </button>
                          <button type="button" role="radio" aria-checked={personMode}
                            onClick={() => { if (!personMode) patch(index, { role: "custom" }); }}>
                            <Icon name="ph-user-focus" size={15} /> {t("wfcSpecificPerson")}
                          </button>
                        </div>

                        {personMode ? (
                          <Field label={t("wfcChoosePerson")} htmlFor={`step-user-${index}`} hint={t("wfcPersonHint")}>
                            <select id={`step-user-${index}`} className="input" value={step.assigned_user_id ?? ""}
                              onChange={(e) => patch(index, { assigned_user_id: e.target.value ? Number(e.target.value) : null })}>
                              <option value="">{t("wfcChoosePerson")}…</option>
                              {assignedMissing && step.assigned_user_id != null && (
                                <option value={step.assigned_user_id} disabled>
                                  {(step.assigned_user?.name ?? "—")} ({t("wfcInactive")})
                                </option>
                              )}
                              {people.map((p) => <option key={p.id} value={p.id}>{personLabel(p)}</option>)}
                            </select>
                          </Field>
                        ) : (
                          <Field label={t("role")} htmlFor={`step-role-${index}`}
                            hint={step.role === "hod" || step.role === "manager" ? t("wfcDeptHint") : t("wfcRoleHint")}>
                            <select id={`step-role-${index}`} className="input" value={step.role}
                              onChange={(e) => patch(index, { role: e.target.value as Role })}>
                              {LEVEL_ROLES.map((r) => (
                                <option key={r} value={r}>
                                  {r === "hod" ? t("wfcEachHod") : r === "manager" ? t("wfcEachManager") : roleName(r)}
                                </option>
                              ))}
                            </select>
                          </Field>
                        )}
                        {issue && <p className="field-error wfc-issue"><Icon name="ph-warning" size={14} /> {issue}</p>}
                      </div>
                    )}

                    {!request && (
                      <div className="vf-form-row">
                        <Field label="Applies from (amount)" htmlFor={`step-min-${index}`} hint={t("amountThresholds")}>
                          <input id={`step-min-${index}`} className="input tnum" inputMode="decimal" value={step.min_amount ?? ""} placeholder="Any amount"
                            onChange={(e) => patch(index, { min_amount: e.target.value ? Number(e.target.value) : null })} />
                        </Field>
                        <Field label="Applies up to (amount)" htmlFor={`step-max-${index}`}
                          error={bandIssues[index] ? t("wfcBandInvalid") : undefined}>
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
          <button className="btn btn-secondary btn-sm" onClick={addStep} disabled={steps.length >= 12}>
            <Icon name="ph-plus" size={15} /> {t("addStep")}
          </button>
        </li>

        <li className="vf-flow-node vf-flow-end">
          <span className="vf-flow-node-icon"><Icon name="ph-check" size={16} /></span>
          {t("completed")}
        </li>
      </ol>

      {/* ── who that resolves to, department by department ── */}
      <section className="vf-panel wfc-routing">
        <div className="vf-panel-head">
          <div className="vf-panel-head-main">
            <h2>{t("wfcRoutingTitle")}</h2>
            <div className="vf-panel-sub">{t("wfcRoutingSub")}{routingStale && dirty ? ` ${t("wfcRoutingStale")}` : ""}</div>
          </div>
          <Link className="btn btn-secondary btn-sm" href="/departments">
            <Icon name="ph-tree-structure" size={15} /> {t("departments")}
          </Link>
        </div>

        {!routing && !routingFor && <div className="vf-panel-pad"><LoadingBlock rows={3} /></div>}
        {routing && routing.departments.length === 0 && (
          <div className="vf-panel-pad"><Note>{t("wfcNoDepartments")}</Note></div>
        )}
        {routing && routing.departments.length > 0 && (
          <>
            <div className="vf-panel-pad wfc-routing-summary">
              {routing.gaps > 0 ? (
                <Note tone="warn">{t("wfcRoutingGaps").replace("{count}", String(routing.gaps))}</Note>
              ) : (
                <Note>{t("wfcRoutingNoGaps")}</Note>
              )}
            </div>
            <div className="table-wrap">
              <table className="table wfc-routing-table">
                <thead>
                  <tr>
                    <th>{t("department")}</th>
                    {levelSteps.map((s, i) => (
                      <th key={s.id}>
                        <span className="wfc-level">{t("wfcLevel")} {i + 1}</span>
                        <span className="wfc-routing-step">{locale === "sw" && s.name_sw ? s.name_sw : s.name}</span>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {routing.departments.map((dept) => (
                    <tr key={dept.id}>
                      <td style={{ fontWeight: 500 }}>{dept.name}</td>
                      {levelSteps.map((s) => {
                        const cell = dept.cells.find((c) => c.step_id === s.id);
                        if (!cell) return <td key={s.id}>—</td>;
                        if (cell.gap) {
                          return (
                            <td key={s.id}>
                              <span className="badge tone-warn">{t(GAP_KEYS[cell.gap])}</span>
                              {DEPARTMENT_GAPS.includes(cell.gap) && (
                                <Link className="wfc-fix-link" href="/departments">{t("wfcFixInDepartments")}</Link>
                              )}
                            </td>
                          );
                        }
                        const shown = cell.people.slice(0, 2).map((p) => p.name).join(", ");
                        const more = cell.people.length - 2;
                        return (
                          <td key={s.id} title={cell.people.map((p) => p.name).join(", ")}>
                            {shown}{more > 0 ? ` +${more}` : ""}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </section>

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
                      <div className="app-wf-step">
                        <span className="vf-flow-num">{request ? <Icon name="ph-user" size={13} /> : index}</span>
                        <span>{request ? t("wfcRequest") : step.name}</span>
                      </div>
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

      {/* Details are applied to the draft; they are saved with the route. */}
      <Dialog
        open={detailsDialog}
        icon="ph-pencil-simple"
        title={t("wfcDetailsTitle")}
        onClose={() => setDetailsDialog(false)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDetailsDialog(false)}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={applyDetails} disabled={!details.name.trim()}>{t("confirm")}</button>
          </>
        }
      >
        <WorkflowFields form={details} onChange={(next) => setDetails((f) => ({ ...f, ...next }))}
          types={types} typeName={typeName} lockType={current.is_default}
          clashes={others.filter((w) => w.is_active && w.voucher_type_id != null).map((w) => w.voucher_type_id!)} />
      </Dialog>

      <Dialog
        open={createDialog}
        icon="ph-flow-arrow"
        title={t("wfcNewWorkflow")}
        onClose={() => setCreateDialog(false)}
        busy={busy}
        wide
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setCreateDialog(false)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={create} disabled={busy || !createForm.name.trim()}>
              {busy ? <Spinner /> : t("wfcCreate")}
            </button>
          </>
        }
      >
        <div className="vf-stack" style={{ gap: 12 }}>
          <WorkflowFields form={createForm} onChange={(next) => setCreateForm((f) => ({ ...f, ...next }))}
            types={types} typeName={typeName} lockType={false}
            clashes={workflows.filter((w) => w.is_active && w.voucher_type_id != null).map((w) => w.voucher_type_id!)} />
          <div className="field">
            <span className="vf-label">{t("wfcStartFrom")}</span>
            <div className="vf-stack" style={{ gap: 8 }}>
              <Choice selected={createForm.source === "copy"} onSelect={() => setCreateForm((f) => ({ ...f, source: "copy" }))}
                icon="ph-copy" label={t("wfcCopyDefault")} sub={t("wfcCopyDefaultSub")} />
              {presets.map((preset) => (
                <Choice key={preset.key} selected={createForm.source === preset.key}
                  onSelect={() => setCreateForm((f) => ({ ...f, source: preset.key }))}
                  icon="ph-flow-arrow" label={preset.name} sub={preset.description} />
              ))}
            </div>
          </div>
        </div>
      </Dialog>

      <Dialog
        open={deleteDialog}
        icon="ph-trash"
        tone="bad"
        title={t("wfcDeleteTitle")}
        sub={deleteBlock ? undefined : t("wfcDeleteSub")}
        onClose={() => setDeleteDialog(false)}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDeleteDialog(false)} disabled={busy}>{t("cancel")}</button>
            {!deleteBlock && (
              <button className="btn btn-danger-solid" onClick={remove} disabled={busy}>
                {busy ? <Spinner /> : <><Icon name="ph-trash" size={15} /> {t("delete")}</>}
              </button>
            )}
          </>
        }
      >
        {deleteBlock && <Note tone="warn">{deleteBlock}</Note>}
      </Dialog>

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

/** Name, Swahili name, description and voucher-type binding — shared by create and edit. */
function WorkflowFields({
  form, onChange, types, typeName, lockType, clashes,
}: {
  form: DetailsForm;
  onChange: (next: Partial<DetailsForm>) => void;
  types: VoucherType[];
  typeName: (type: { name: string; name_sw: string | null }) => string;
  lockType: boolean;
  /** Voucher types another active workflow already routes. */
  clashes: number[];
}) {
  const { t } = useApp();
  return (
    <div style={{ display: "grid", gap: "var(--space-3)" }}>
      <div className="vf-form-row">
        <Field label={t("wfcNameEn")} htmlFor="wf-name" required>
          <input id="wf-name" className="input" value={form.name} onChange={(e) => onChange({ name: e.target.value })} required />
        </Field>
        <Field label={t("wfcNameSw")} htmlFor="wf-name-sw">
          <input id="wf-name-sw" className="input" value={form.name_sw} onChange={(e) => onChange({ name_sw: e.target.value })} />
        </Field>
      </div>
      <Field label={t("wfcDescription")} htmlFor="wf-desc">
        <input id="wf-desc" className="input" value={form.description} maxLength={255} onChange={(e) => onChange({ description: e.target.value })} />
      </Field>
      <Field label={t("wfcAppliesTo")} htmlFor="wf-type" hint={lockType ? t("wfcDefaultAllTypes") : t("wfcAppliesToHint")}>
        <select id="wf-type" className="input" value={form.voucher_type_id} disabled={lockType}
          onChange={(e) => onChange({ voucher_type_id: e.target.value })}>
          <option value="">{t("wfcAllTypes")}</option>
          {types.filter((type) => type.is_active).map((type) => (
            <option key={type.id} value={type.id} disabled={clashes.includes(type.id) && String(type.id) !== form.voucher_type_id}>
              {typeName(type)}
            </option>
          ))}
        </select>
      </Field>
    </div>
  );
}
