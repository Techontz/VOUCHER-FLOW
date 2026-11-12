"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { MODULE_LOOK, fill } from "@/lib/platform";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Spinner, StatPills } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator } from "@/components/app-ui";
import { AppStrip, planApps } from "@/components/app-picker";
import type { Plan } from "@/lib/types";

/*
 * The plans the platform sells. Each card is one plan in the order the
 * public pricing page shows them; drag a card by its handle (or use the up
 * and down buttons, the keyboard route) to reorder, and the order is saved
 * at once. A plan is edited in a dialog; one nobody has ever been on can be
 * deleted, any other is archived instead.
 */

const MODULES = Object.keys(MODULE_LOOK);
const CURRENCIES = ["TZS", "KES", "UGX", "RWF", "USD", "EUR"];

interface Form {
  code: string; name: string; name_sw: string; blurb: string; blurb_sw: string;
  price: string; price_yearly: string; currency: string; billing_cycle: "monthly" | "annual"; trial_days: string;
  max_users: string; max_vouchers_per_month: string; max_departments: string; max_approval_levels: string; storage_mb: string;
  features: string[]; modules: string[];
  /** Every app, including apps added to the catalogue later: sent as no list at all. */
  all_apps: boolean;
  allows_module_choice: boolean; price_per_module: string;
  is_active: boolean; is_public: boolean; is_featured: boolean;
}

const BLANK: Form = {
  code: "", name: "", name_sw: "", blurb: "", blurb_sw: "",
  price: "", price_yearly: "", currency: "TZS", billing_cycle: "monthly", trial_days: "",
  max_users: "", max_vouchers_per_month: "", max_departments: "", max_approval_levels: "", storage_mb: "",
  features: [""], modules: [...MODULES], all_apps: true, allows_module_choice: false, price_per_module: "",
  is_active: true, is_public: true, is_featured: false,
};

const str = (v: number | null | undefined) => (v === null || v === undefined ? "" : String(v));

function toForm(p: Plan): Form {
  return {
    code: p.code, name: p.name, name_sw: p.name_sw ?? "", blurb: p.blurb ?? "", blurb_sw: p.blurb_sw ?? "",
    price: String(p.price), price_yearly: str(p.price_yearly), currency: p.currency, billing_cycle: p.billing_cycle,
    trial_days: String(p.trial_days ?? ""), max_users: str(p.max_users), max_vouchers_per_month: str(p.max_vouchers_per_month),
    max_departments: str(p.max_departments), max_approval_levels: str(p.max_approval_levels), storage_mb: str(p.storage_mb),
    features: p.features.length ? [...p.features] : [""], modules: p.modules?.length ? [...p.modules] : [...MODULES],
    all_apps: !p.modules?.length, allows_module_choice: !!p.allows_module_choice, price_per_module: p.price_per_module ? String(p.price_per_module) : "",
    is_active: p.is_active, is_public: p.is_public, is_featured: !!p.is_featured,
  };
}

/** The whole plan as the API takes it, so a one-flag change can be sent as an edit. */
function payloadOf(f: Form) {
  const num = (v: string) => (v.trim() === "" ? null : Number(v));
  return {
    code: f.code.trim(), name: f.name.trim(), blurb: f.blurb.trim() || null,
    ...(f.name_sw.trim() ? { name_sw: f.name_sw.trim() } : {}),
    ...(f.blurb_sw.trim() ? { blurb_sw: f.blurb_sw.trim() } : {}),
    price: Number(f.price || 0), price_yearly: num(f.price_yearly), currency: f.currency, billing_cycle: f.billing_cycle,
    trial_days: num(f.trial_days), max_users: num(f.max_users), max_vouchers_per_month: num(f.max_vouchers_per_month),
    max_departments: num(f.max_departments), max_approval_levels: num(f.max_approval_levels), storage_mb: num(f.storage_mb),
    features: f.features.map((x) => x.trim()).filter(Boolean), modules: f.all_apps ? null : f.modules,
    allows_module_choice: f.allows_module_choice, price_per_module: f.allows_module_choice ? Number(f.price_per_module || 0) : 0,
    is_active: f.is_active, is_public: f.is_public, is_featured: f.is_featured,
  };
}

export default function PlatformPlansPage() {
  const { t, toast, reportError } = useApp();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Plan | "new" | null>(null);
  const [form, setForm] = useState<Form>(BLANK);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const [deleting, setDeleting] = useState<Plan | null>(null);
  const [busy, setBusy] = useState(false);
  const [dragId, setDragId] = useState<number | null>(null);
  const [overId, setOverId] = useState<number | null>(null);
  const [announce, setAnnounce] = useState("");
  const saving = useRef(false);

  const load = useCallback(() => {
    api.get<{ data: Plan[] }>("/platform/plans")
      .then((r) => { setError(null); setPlans(r.data); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  function openCreate() { setForm(BLANK); setFormError(null); setEditing("new"); }
  function openEdit(p: Plan) { setForm(toForm(p)); setFormError(null); setEditing(p); }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const body = payloadOf(form);
      if (editing && editing !== "new") await api.put(`/platform/plans/${editing.id}`, body);
      else await api.post("/platform/plans", body);
      toast(editing === "new" ? t("pfPlanCreated") : t("pfPlanSaved"), form.name, "ok");
      setEditing(null);
      load();
    } catch (err) {
      if (err instanceof ApiError && Object.keys(err.errors).length) setFormError(err);
      else reportError(err, t("pfPlanSaveFailed"));
    } finally { setBusy(false); }
  }

  async function flag(p: Plan, change: Partial<Pick<Form, "is_active" | "is_public" | "is_featured">>, message: string) {
    try {
      await api.put(`/platform/plans/${p.id}`, { ...payloadOf(toForm(p)), ...change });
      toast(message, p.name, "ok");
      load();
    } catch (err) { reportError(err, t("pfPlanSaveFailed")); }
  }

  async function remove() {
    if (!deleting) return;
    setBusy(true);
    try {
      await api.delete(`/platform/plans/${deleting.id}`);
      toast(t("pfPlanDeleted"), deleting.name, "warn");
      setDeleting(null);
      load();
    } catch (err) { reportError(err, t("pfPlanDeleteFailed")); }
    finally { setBusy(false); }
  }

  /** Saves a new order; the list moves at once and rolls back if the save fails. */
  async function reorder(next: Plan[], moved?: Plan) {
    if (!plans || saving.current) return;
    const before = plans;
    setPlans(next);
    saving.current = true;
    try {
      const res = await api.post<{ data: Plan[] }>("/platform/plans/reorder", { ids: next.map((p) => p.id) });
      setPlans(res.data);
      if (moved) setAnnounce(fill(t("pfMovedTo"), { name: moved.name, n: next.indexOf(moved) + 1, total: next.length }));
      toast(t("pfOrderSaved"), undefined, "ok");
    } catch (err) {
      setPlans(before);
      reportError(err, t("pfOrderFailed"));
    } finally { saving.current = false; }
  }

  function move(p: Plan, by: -1 | 1) {
    if (!plans) return;
    const i = plans.indexOf(p);
    const j = i + by;
    if (j < 0 || j >= plans.length) return;
    const next = [...plans];
    [next[i], next[j]] = [next[j], next[i]];
    void reorder(next, p);
  }

  function drop(targetId: number) {
    if (!plans || dragId === null || dragId === targetId) return;
    const from = plans.findIndex((p) => p.id === dragId);
    const to = plans.findIndex((p) => p.id === targetId);
    const next = [...plans];
    const [item] = next.splice(from, 1);
    next.splice(to, 0, item);
    void reorder(next, item);
  }

  const set = <K extends keyof Form>(key: K, value: Form[K]) => setForm((f) => ({ ...f, [key]: value }));
  const input = (key: keyof Form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    set(key, e.target.value as never);
  const fieldError = (key: string) => formError?.field(key);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!plans) return <LoadingBlock rows={5} />;

  const live = plans.filter((p) => p.is_active);
  const onPricing = live.filter((p) => p.is_public);
  const companiesOnPlans = plans.reduce((n, p) => n + (p.companies_count ?? 0), 0);
  const unlimited = t("pfUnlimited");
  const appsLabel = (p: Plan) => p.allows_module_choice
    ? fill(t("pfPickApps"), { base: money(p.price, p.currency), each: money(p.price_per_module ?? 0, p.currency) })
    : p.all_apps || !p.modules?.length ? t("pfAllApps") : fill(t("pfAppsCount"), { n: p.apps_count ?? planApps(p).length });
  const limit = (v: number | null, key: "pfLimitUsers" | "pfLimitVouchers" | "pfLimitDepartments" | "pfLimitLevels") =>
    fill(t(key), { n: v === null ? unlimited : v.toLocaleString("en-US") });

  return (
    <div className="app-page pf-page">
      <PageHeader kicker={t("pfPlatform")} title={t("pfPlans")} subtitle={t("pfPlansSub")}
        actions={<button type="button" className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={16} /> {t("pfNewPlan")}</button>} />

      <StatPills label={t("pfKeyFigures")} items={[
        { label: t("pfPlansLive"), value: live.length, hint: fill(t("pfPlansArchived"), { n: plans.length - live.length }), icon: "ph-crown-simple" },
        { label: t("pfOnPricing"), value: onPricing.length, hint: t("pfOnPricingHint"), icon: "ph-storefront", tone: "info" },
        { label: t("pfCompaniesOnPlans"), value: companiesOnPlans, icon: "ph-buildings", tone: "ok" },
      ]} />

      <p className="sr-only" aria-live="polite">{announce}</p>

      {plans.length === 0 ? (
        <section className="vf-panel">
          <EmptyState icon="ph-crown-simple" title={t("pfNoPlans")} body={t("pfNoPlansBody")}
            action={<button type="button" className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={16} /> {t("pfNewPlan")}</button>} />
        </section>
      ) : (
        <ol className="pf-plans" aria-label={t("pfPlanOrder")} style={{ listStyle: "none", margin: 0, padding: 0 }}>
          {plans.map((p, i) => {
            const used = (p.companies_count ?? 0) + (p.subscriptions_count ?? 0) > 0;
            return (
              <li key={p.id} className="pf-plan"
                data-dragging={dragId === p.id ? "" : undefined}
                data-over={overId === p.id && dragId !== p.id ? "" : undefined}
                data-archived={p.is_active ? undefined : ""}
                onDragOver={(e) => { if (dragId !== null) { e.preventDefault(); setOverId(p.id); } }}
                onDragLeave={() => setOverId((o) => (o === p.id ? null : o))}
                onDrop={(e) => { e.preventDefault(); drop(p.id); setDragId(null); setOverId(null); }}>
                <div className="pf-plan-handle">
                  <span className="pf-plan-grip" draggable title={t("pfDragToReorder")}
                    onDragStart={(e) => { setDragId(p.id); e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", String(p.id)); }}
                    onDragEnd={() => { setDragId(null); setOverId(null); }}>
                    <Icon name="ph-dots-six-vertical" size={20} />
                  </span>
                  <button type="button" className="btn btn-icon btn-sm" disabled={i === 0} onClick={() => move(p, -1)}
                    aria-label={fill(t("pfMoveUp"), { name: p.name })}><Icon name="ph-caret-up" size={14} /></button>
                  <button type="button" className="btn btn-icon btn-sm" disabled={i === plans.length - 1} onClick={() => move(p, 1)}
                    aria-label={fill(t("pfMoveDown"), { name: p.name })}><Icon name="ph-caret-down" size={14} /></button>
                </div>

                <div className="pf-plan-main">
                  <div className="pf-plan-title">
                    <strong>{p.name}</strong>
                    <code>{p.code}</code>
                    {p.is_featured && <span className="pf-chip" data-tone="accent"><Icon name="ph-star" size={12} weight="fill" /> {t("pfFeatured")}</span>}
                    {!p.is_active && <span className="pf-chip"><Icon name="ph-archive" size={12} /> {t("pfArchived")}</span>}
                    {p.is_active && !p.is_public && <span className="pf-chip"><Icon name="ph-eye-slash" size={12} /> {t("pfHidden")}</span>}
                  </div>
                  <div className="pf-plan-price">
                    {p.price > 0
                      ? <><b className="tnum">{money(p.price, p.currency)}</b> {t("pfPerMonth")} · <span className="tnum">{money(p.yearly_price ?? p.price * 10, p.currency)}</span> {t("pfPerYear")}</>
                      : <b>{t("pfCustomPrice")}</b>}
                    {p.trial_days > 0 && <> · {fill(t("pfTrialDays"), { n: p.trial_days })}</>}
                  </div>
                  <div className="pf-chips">
                    <span className="pf-chip"><Icon name="ph-users" size={12} /> {limit(p.max_users, "pfLimitUsers")}</span>
                    <span className="pf-chip"><Icon name="ph-receipt" size={12} /> {limit(p.max_vouchers_per_month, "pfLimitVouchers")}</span>
                    <span className="pf-chip"><Icon name="ph-tree-structure" size={12} /> {limit(p.max_departments, "pfLimitDepartments")}</span>
                    <span className="pf-chip"><Icon name="ph-stairs" size={12} /> {limit(p.max_approval_levels, "pfLimitLevels")}</span>
                    <span className="pf-chip" data-tone="accent"><Icon name="ph-squares-four" size={12} /> {appsLabel(p)}</span>
                    <AppStrip apps={planApps(p)} max={6} size={22} />
                  </div>
                </div>

                <div className="pf-plan-end">
                  <span className="pf-chip"><Icon name="ph-buildings" size={12} /> {fill(t("pfCompaniesCount"), { n: p.companies_count ?? 0 })}</span>
                  <button type="button" className="btn btn-secondary btn-sm" onClick={() => openEdit(p)}><Icon name="ph-pencil-simple" size={14} /> {t("edit")}</button>
                  <Dropdown floating label={fill(t("pfActionsFor"), { name: p.name })}
                    trigger={({ open, toggle, id }) => (
                      <button type="button" className="btn btn-icon btn-sm" onClick={toggle} aria-expanded={open} aria-controls={id}
                        aria-haspopup="menu" aria-label={fill(t("pfActionsFor"), { name: p.name })}>
                        <Icon name="ph-dots-three-outline" size={18} />
                      </button>
                    )}>
                    {(close) => (
                      <>
                        <MenuItem icon={p.is_featured ? "ph-star" : "ph-star"} onSelect={() => { close(); void flag(p, { is_featured: !p.is_featured }, p.is_featured ? t("pfUnfeatured") : t("pfFeaturedDone")); }}>
                          {p.is_featured ? t("pfUnfeature") : t("pfFeature")}
                        </MenuItem>
                        <MenuItem icon={p.is_public ? "ph-eye-slash" : "ph-eye"} onSelect={() => { close(); void flag(p, { is_public: !p.is_public }, p.is_public ? t("pfHiddenDone") : t("pfShownDone")); }}>
                          {p.is_public ? t("pfHideFromPricing") : t("pfShowOnPricing")}
                        </MenuItem>
                        <MenuItem icon={p.is_active ? "ph-archive" : "ph-arrow-counter-clockwise"} onSelect={() => { close(); void flag(p, { is_active: !p.is_active }, p.is_active ? t("pfArchivedDone") : t("pfRestoredDone")); }}>
                          {p.is_active ? t("pfArchive") : t("pfRestore")}
                        </MenuItem>
                        {!used && (
                          <>
                            <MenuSeparator />
                            <MenuItem icon="ph-trash" tone="danger" onSelect={() => { close(); setDeleting(p); }}>{t("delete")}</MenuItem>
                          </>
                        )}
                      </>
                    )}
                  </Dropdown>
                </div>
              </li>
            );
          })}
        </ol>
      )}

      <Dialog open={editing !== null} wide busy={busy} onClose={() => setEditing(null)} icon="ph-crown-simple"
        title={editing === "new" ? t("pfNewPlan") : fill(t("pfEditPlan"), { name: typeof editing === "object" && editing ? editing.name : "" })}
        sub={t("pfPlanEditorSub")}
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className="btn btn-primary" onClick={() => void save()} disabled={busy || !form.name.trim() || !form.code.trim() || form.price === ""}>
            {busy ? <Spinner /> : <><Icon name="ph-check" size={16} /> {t("save")}</>}
          </button>
        </>}>
        <div className="pf-form">
          <div className="pf-form-row">
            <Field label={t("pfPlanName")} htmlFor="pl-name" required error={fieldError("name")}>
              <input id="pl-name" className="input" value={form.name} onChange={input("name")} maxLength={80} />
            </Field>
            <Field label={t("pfPlanCode")} htmlFor="pl-code" required hint={t("pfPlanCodeHint")} error={fieldError("code")}>
              <input id="pl-code" className="input" value={form.code} onChange={input("code")} maxLength={40} />
            </Field>
          </div>
          <div className="pf-form-row">
            <Field label={t("pfPlanNameSw")} htmlFor="pl-name-sw" error={fieldError("name_sw")}>
              <input id="pl-name-sw" className="input" value={form.name_sw} onChange={input("name_sw")} maxLength={80} />
            </Field>
            <Field label={t("pfPlanBlurb")} htmlFor="pl-blurb" error={fieldError("blurb")}>
              <input id="pl-blurb" className="input" value={form.blurb} onChange={input("blurb")} maxLength={255} />
            </Field>
            <Field label={t("pfPlanBlurbSw")} htmlFor="pl-blurb-sw" error={fieldError("blurb_sw")}>
              <input id="pl-blurb-sw" className="input" value={form.blurb_sw} onChange={input("blurb_sw")} maxLength={255} />
            </Field>
          </div>

          <div className="pf-form-section">{t("pfPricing")}</div>
          <div className="pf-form-row">
            <Field label={t("pfPriceMonthly")} htmlFor="pl-price" required error={fieldError("price")}>
              <input id="pl-price" className="input tnum" type="number" min={0} inputMode="decimal" value={form.price} onChange={input("price")} />
            </Field>
            <Field label={t("pfPriceYearly")} htmlFor="pl-yearly" hint={t("pfPriceYearlyHint")} error={fieldError("price_yearly")}>
              <input id="pl-yearly" className="input tnum" type="number" min={0} inputMode="decimal" value={form.price_yearly} onChange={input("price_yearly")}
                placeholder={form.price ? String(Number(form.price) * 10) : ""} />
            </Field>
            <Field label={t("currency")} htmlFor="pl-currency" error={fieldError("currency")}>
              <select id="pl-currency" className="input" value={form.currency} onChange={input("currency")}>
                {[...new Set([form.currency, ...CURRENCIES])].map((c) => <option key={c}>{c}</option>)}
              </select>
            </Field>
            <Field label={t("pfDefaultCycle")} htmlFor="pl-cycle" error={fieldError("billing_cycle")}>
              <select id="pl-cycle" className="input" value={form.billing_cycle} onChange={input("billing_cycle")}>
                <option value="monthly">{t("pfMonthly")}</option>
                <option value="annual">{t("pfYearly")}</option>
              </select>
            </Field>
            <Field label={t("pfTrialLength")} htmlFor="pl-trial" hint={t("pfTrialLengthHint")} error={fieldError("trial_days")}>
              <input id="pl-trial" className="input tnum" type="number" min={0} max={365} value={form.trial_days} onChange={input("trial_days")} />
            </Field>
          </div>

          <div className="pf-form-section">{t("pfLimits")}</div>
          <div className="pf-form-row">
            {([
              ["max_users", "pfMaxUsers"], ["max_vouchers_per_month", "pfMaxVouchers"],
              ["max_departments", "pfMaxDepartments"], ["max_approval_levels", "pfMaxLevels"], ["storage_mb", "pfStorage"],
            ] as const).map(([key, label]) => (
              <Field key={key} label={t(label)} htmlFor={`pl-${key}`} error={fieldError(key)}>
                <input id={`pl-${key}`} className="input tnum" type="number" min={1} value={form[key]} onChange={input(key)} placeholder={unlimited} />
              </Field>
            ))}
          </div>

          <div className="pf-form-section">{t("pfFeatures")}</div>
          <div className="pf-features">
            {form.features.map((f, i) => (
              <div key={i} className="pf-feature">
                <input className="input" value={f} maxLength={120} aria-label={fill(t("pfFeatureN"), { n: i + 1 })}
                  placeholder={t("pfFeaturePh")}
                  onChange={(e) => set("features", form.features.map((x, j) => (j === i ? e.target.value : x)))} />
                <button type="button" className="btn btn-icon" aria-label={fill(t("pfRemoveFeature"), { n: i + 1 })}
                  onClick={() => set("features", form.features.length > 1 ? form.features.filter((_, j) => j !== i) : [""])}>
                  <Icon name="ph-x" size={15} />
                </button>
              </div>
            ))}
            {fieldError("features") && <div className="field-error" role="alert">{fieldError("features")}</div>}
            <div>
              <button type="button" className="btn btn-ghost btn-sm" disabled={form.features.length >= 20}
                onClick={() => set("features", [...form.features, ""])}><Icon name="ph-plus" size={14} /> {t("pfAddFeature")}</button>
            </div>
          </div>

          <div className="pf-form-section">{t("pfIncludedModules")}</div>
          <Field label={t("pfPlanType")} htmlFor="pl-type" hint={form.allows_module_choice ? t("pfPlanPickHint") : t("pfPlanBundleHint")}>
            <select id="pl-type" className="input" value={form.allows_module_choice ? "pick" : "bundle"}
              onChange={(e) => set("allows_module_choice", e.target.value === "pick")}>
              <option value="bundle">{t("pfPlanBundle")}</option>
              <option value="pick">{t("pfPlanPick")}</option>
            </select>
          </Field>
          {form.allows_module_choice && (
            <Field label={t("pfPricePerApp")} htmlFor="pl-per-app" hint={t("pfPricePerAppHint")} error={fieldError("price_per_module")}>
              <input id="pl-per-app" className="input tnum" type="number" min={0} inputMode="decimal" value={form.price_per_module} onChange={input("price_per_module")} />
            </Field>
          )}
          <label className="pf-switch">
            <input type="checkbox" checked={form.all_apps}
              onChange={(e) => setForm((f) => ({ ...f, all_apps: e.target.checked, modules: e.target.checked ? [...MODULES] : f.modules }))} />
            {t("pfAllAppsToggle")}
          </label>
          <div className="pf-checks">
            {MODULES.map((m) => (
              <label key={m} className="pf-check">
                <input type="checkbox" checked={m === "vouchflow" || form.all_apps || form.modules.includes(m)} disabled={m === "vouchflow"}
                  onChange={(e) => {
                    const base = form.all_apps ? [...MODULES] : form.modules;
                    const next = e.target.checked ? [...new Set([...base, m])] : base.filter((x) => x !== m);
                    setForm((f) => ({ ...f, modules: next, all_apps: MODULES.every((k) => k === "vouchflow" || next.includes(k)) }));
                  }} />
                <Icon name={MODULE_LOOK[m].icon} size={17} />
                <span>{t(MODULE_LOOK[m].label)}{m === "vouchflow" && <small>{t("pfAlwaysIncluded")}</small>}</span>
              </label>
            ))}
          </div>

          <div className="pf-form-section">{t("pfVisibility")}</div>
          <div className="pf-switches">
            <label className="pf-switch"><input type="checkbox" checked={form.is_active} onChange={(e) => set("is_active", e.target.checked)} /> {t("pfAvailable")}</label>
            <label className="pf-switch"><input type="checkbox" checked={form.is_public} onChange={(e) => set("is_public", e.target.checked)} /> {t("pfShowOnPricing")}</label>
            <label className="pf-switch"><input type="checkbox" checked={form.is_featured} onChange={(e) => set("is_featured", e.target.checked)} /> {t("pfFeatured")}</label>
          </div>
        </div>
      </Dialog>

      <Dialog open={deleting !== null} busy={busy} onClose={() => setDeleting(null)} icon="ph-trash" tone="bad"
        title={fill(t("pfDeletePlanQ"), { name: deleting?.name ?? "" })} sub={t("pfDeletePlanSub")}
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setDeleting(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className="btn btn-danger-solid" onClick={() => void remove()} disabled={busy}><Icon name="ph-trash" size={15} /> {t("delete")}</button>
        </>} />
    </div>
  );
}
