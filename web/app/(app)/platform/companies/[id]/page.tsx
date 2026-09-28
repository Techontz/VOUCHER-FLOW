"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { Dialog, ErrorState, Field, Icon, LoadingBlock, Spinner } from "@/components/ui";
import type { ColorTheme, Company, Plan } from "@/lib/types";
import {
  ActivityTab, BrandingTab, DepartmentsTab, OverviewTab, PALETTES, PaymentsTab, SubscriptionTab, UsersTab, VouchersTab, WorkflowTab,
  type DepartmentRow, type Detail, type Overview,
} from "./sections";
import { useTemplatePreviews } from "@/components/voucher-templates";
import { VoucherTemplatePanel } from "@/components/voucher-template-panel";

/*
 * One company, as the platform super admin sees it: its profile, branding,
 * people, departments, approval route, vouchers, money, subscription and
 * activity — each tab reading that company's own data through the platform
 * API, inside that company's tenant scope.
 */

const TABS = [
  { key: "overview", label: "Overview", icon: "ph-squares-four" },
  { key: "branding", label: "Branding & voucher design", icon: "ph-palette" },
  { key: "users", label: "Users", icon: "ph-users-three" },
  { key: "departments", label: "Departments", icon: "ph-tree-structure" },
  { key: "workflow", label: "Workflow", icon: "ph-flow-arrow" },
  { key: "vouchers", label: "Vouchers", icon: "ph-receipt" },
  { key: "payments", label: "Payments", icon: "ph-hand-coins" },
  { key: "subscription", label: "Subscription", icon: "ph-crown-simple" },
  { key: "activity", label: "Activity", icon: "ph-clock-counter-clockwise" },
] as const;
type TabKey = (typeof TABS)[number]["key"];

const STATUS_TAG: Record<string, string> = {
  active: "tag-accent", trial: "tag-outline", past_due: "tag-accent-2", suspended: "tag-accent-2", cancelled: "tag-neutral",
};

export default function PlatformCompanyPage() {
  const params = useParams<{ id: string }>();
  const { t, locale, toast, reportError } = useApp();
  const [detail, setDetail] = useState<Detail | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [departments, setDepartments] = useState<DepartmentRow[] | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<TabKey>("overview");
  const [tabFilter, setTabFilter] = useState<Record<string, string> | undefined>(undefined);
  const [filterKey, setFilterKey] = useState(0);

  const [planDialog, setPlanDialog] = useState(false);
  const [planId, setPlanId] = useState<number | null>(null);
  const [statusDialog, setStatusDialog] = useState<"suspend" | "activate" | null>(null);
  const [brandDialog, setBrandDialog] = useState(false);
  const [brand, setBrand] = useState({ color_theme: "blue" as ColorTheme, primary_color: "", secondary_color: "", accent_color: "", voucher_header_text: "", voucher_footer_text: "" });
  const [brandErrors, setBrandErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  // The sample voucher in every design, in this company's own letterhead.
  const templatePreviews = useTemplatePreviews(`/platform/companies/${params.id}/voucher-template/preview`, {});

  const id = params.id;

  const load = useCallback(() => {
    setError(null);
    api.get<Detail>(`/platform/companies/${id}`)
      .then((d) => { setDetail(d); setPlanId(d.data.plan_id); })
      .catch((err) => setError(err.message));
    api.get<{ data: Overview }>(`/platform/companies/${id}/overview`).then((r) => setOverview(r.data)).catch((err) => setError(err.message));
    api.get<{ data: DepartmentRow[] }>(`/platform/companies/${id}/departments`).then((r) => setDepartments(r.data)).catch(() => setDepartments([]));
  }, [id]);

  useEffect(() => {
    load();
    api.get<{ data: Plan[] }>("/platform/plans").then((r) => setPlans(r.data)).catch(() => undefined);
  }, [load, locale]);

  // The open tab lives in the address (#users …), so a view can be linked to.
  useEffect(() => {
    const read = () => {
      const key = window.location.hash.replace("#", "") as TabKey;
      // Read from the address bar (an external source) after hydration.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (TABS.some((x) => x.key === key)) setTab(key);
    };
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, []);

  const open = (key: string, filter?: Record<string, string>) => {
    setTabFilter(filter);
    setFilterKey((k) => k + 1);
    setTab(key as TabKey);
    window.history.replaceState(null, "", `#${key}`);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  async function changePlan() {
    if (!planId || !detail) return;
    setBusy(true);
    try {
      const res = await api.post<{ message: string }>(`/platform/companies/${detail.data.id}/change-plan`, { plan_id: planId });
      toast("Plan changed", res.message, "ok");
      setPlanDialog(false);
      load();
    } catch (err) { reportError(err, "Could not change the plan"); }
    finally { setBusy(false); }
  }

  async function setStatus() {
    if (!detail || !statusDialog) return;
    setBusy(true);
    try {
      await api.post(`/platform/companies/${detail.data.id}/${statusDialog}`);
      toast(statusDialog === "suspend" ? "Company suspended" : "Company activated", detail.data.name, statusDialog === "suspend" ? "warn" : "ok");
      setStatusDialog(null);
      load();
    } catch (err) { reportError(err); }
    finally { setBusy(false); }
  }

  function openBranding(c: Company) {
    setBrand({
      color_theme: c.color_theme ?? "blue", primary_color: c.primary_color ?? "", secondary_color: c.secondary_color ?? "",
      accent_color: c.accent_color ?? "", voucher_header_text: c.voucher_header_text ?? "", voucher_footer_text: c.voucher_footer_text ?? "",
    });
    setBrandErrors({});
    setBrandDialog(true);
  }

  async function saveBranding() {
    if (!detail) return;
    setBusy(true); setBrandErrors({});
    try {
      // Blank fields are left as they are, exactly as the endpoint treats nulls.
      const payload = Object.fromEntries(Object.entries(brand).map(([k, v]) => [k, v === "" ? null : v]));
      await api.post(`/platform/companies/${detail.data.id}/branding`, payload);
      toast("Branding saved", detail.data.name, "ok");
      setBrandDialog(false);
      load();
    } catch (err) {
      const errors = (err as { errors?: Record<string, string[]> }).errors;
      if (errors && Object.keys(errors).length) setBrandErrors(Object.fromEntries(Object.entries(errors).map(([k, v]) => [k, v[0]])));
      else reportError(err, "Could not save the branding");
    } finally { setBusy(false); }
  }

  if (error && !detail) return <ErrorState message={error} onRetry={load} />;
  if (!detail || !overview) return <LoadingBlock rows={6} />;

  const c = detail.data;
  const palette = PALETTES[c.color_theme ?? "blue"] ?? PALETTES.blue;
  const initials = c.initials ?? c.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase();
  const roles = Object.keys(overview.people.by_role);
  const setB = (k: keyof typeof brand) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setBrand((b) => ({ ...b, [k]: e.target.value }));

  return (
    <div className="app-page">
      <Link className="vf-back" href="/platform/companies"><Icon name="ph-arrow-left" size={14} /> {t("companies")}</Link>

      <header className="app-co-head">
        <div className="app-co-identity">
          <span className="app-co-logo-tile" style={{ background: c.logo_mark_url ? "#fff" : palette.primary }}>
            {c.logo_mark_url ? <img src={c.logo_mark_url} alt="" /> : initials}
          </span>
          <div className="app-co-identity-text">
            <div className="app-co-kicker">
              <span className={`badge ${STATUS_TAG[c.status] ?? "tag-neutral"}`}>{c.status}</span>
              <span>{c.plan?.name ?? "No plan"}</span>
              <span className="app-co-dot" aria-hidden="true" />
              <span className="app-co-palette"><span style={{ background: palette.primary }} aria-hidden="true" /> {palette.label} palette</span>
            </div>
            <h1 className="vf-pagehead-title">{c.name}</h1>
            <p className="vf-pagehead-sub">{[c.email, c.phone, [c.city, c.region, c.country].filter(Boolean).join(", ")].filter(Boolean).join(" · ")}</p>
          </div>
        </div>
        <div className="vf-pagehead-actions">
          <button type="button" className="btn btn-secondary" onClick={() => openBranding(c)}><Icon name="ph-paint-brush" size={16} /> Edit branding</button>
          <button type="button" className="btn btn-secondary" onClick={() => setPlanDialog(true)}><Icon name="ph-crown-simple" size={16} /> {t("changePlan")}</button>
          {c.status === "suspended"
            ? <button type="button" className="btn btn-primary" onClick={() => setStatusDialog("activate")}><Icon name="ph-check-circle" size={16} /> {t("activate")}</button>
            : <button type="button" className="btn btn-danger" onClick={() => setStatusDialog("suspend")}><Icon name="ph-prohibit" size={16} /> {t("suspend")}</button>}
        </div>
      </header>

      <div className="app-tabs app-co-tabs" role="tablist" aria-label="Company views">
        {TABS.map((x) => (
          <button key={x.key} type="button" role="tab" aria-selected={tab === x.key} onClick={() => open(x.key)}>
            <Icon name={x.icon} size={17} /> {x.label}
          </button>
        ))}
      </div>

      <div role="tabpanel" aria-label={TABS.find((x) => x.key === tab)?.label}>
        {tab === "overview" && <OverviewTab detail={detail} overview={overview} onOpen={open} />}
        {tab === "branding" && (
          <BrandingTab company={c} onEdit={() => openBranding(c)} voucherDesign={
            <VoucherTemplatePanel
              mode="platform"
              companyId={c.id}
              previews={templatePreviews.previews}
              previewsLoading={templatePreviews.loading}
              onChanged={load}
            />
          } />
        )}
        {tab === "users" && <UsersTab key={filterKey} companyId={c.id} departments={departments ?? []} roles={roles} initial={tabFilter} />}
        {tab === "departments" && <DepartmentsTab departments={departments} currency={overview.currency} onOpen={open} />}
        {tab === "workflow" && <WorkflowTab companyId={c.id} />}
        {tab === "vouchers" && <VouchersTab key={filterKey} companyId={c.id} departments={departments ?? []} currency={overview.currency} initial={tabFilter} />}
        {tab === "payments" && <PaymentsTab overview={overview} />}
        {tab === "subscription" && <SubscriptionTab detail={detail} onChangePlan={() => setPlanDialog(true)} />}
        {tab === "activity" && <ActivityTab companyId={c.id} />}
      </div>

      <Dialog open={planDialog} title={t("changePlan")} onClose={() => setPlanDialog(false)} busy={busy}
        sub="The tenant is moved immediately and a new billing period starts. No payment is taken here."
        actions={<>
          <button className="btn btn-secondary" onClick={() => setPlanDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={changePlan} disabled={busy || !planId}>{busy ? <Spinner /> : t("confirm")}</button>
        </>}>
        <Field label={t("plan")} htmlFor="pc-plan">
          <select id="pc-plan" className="input" value={planId ?? ""} onChange={(e) => setPlanId(Number(e.target.value))}>
            {plans.map((plan) => (
              <option key={plan.id} value={plan.id}>{plan.name} — {plan.price > 0 ? money(plan.price, plan.currency) : "Custom"}</option>
            ))}
          </select>
        </Field>
      </Dialog>

      <Dialog open={statusDialog !== null} busy={busy} onClose={() => setStatusDialog(null)}
        icon={statusDialog === "suspend" ? "ph-prohibit" : "ph-check-circle"} tone={statusDialog === "suspend" ? "warn" : "ok"}
        title={statusDialog === "suspend" ? `Suspend ${c.name}?` : `Reactivate ${c.name}?`}
        sub={statusDialog === "suspend"
          ? "Everyone in the company is signed out immediately and cannot use VouchFlow until you reactivate it. Nothing is deleted."
          : "Its people can sign in again straight away."}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setStatusDialog(null)} disabled={busy}>{t("cancel")}</button>
          <button className={statusDialog === "suspend" ? "btn btn-danger-solid" : "btn btn-primary"} onClick={() => void setStatus()} disabled={busy}>
            {statusDialog === "suspend" ? t("suspend") : t("activate")}
          </button>
        </>} />

      <Dialog open={brandDialog} wide busy={busy} onClose={() => setBrandDialog(false)} icon="ph-paint-brush"
        title="Edit branding" sub={`Changes ${c.name}'s interface palette and the branding printed on its vouchers. Logos are uploaded by the company under Branding.`}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setBrandDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={() => void saveBranding()} disabled={busy}>{busy ? <Spinner /> : "Save branding"}</button>
        </>}>
        <div className="app-stack">
          <div>
            <div className="vf-label" style={{ marginBottom: 8 }}>Interface palette</div>
            <div className="app-theme-picker" role="radiogroup" aria-label="Interface palette">
              {(Object.keys(PALETTES) as ColorTheme[]).map((key) => (
                <button key={key} type="button" role="radio" aria-checked={brand.color_theme === key} className="app-theme-option"
                  onClick={() => setBrand((b) => ({ ...b, color_theme: key }))}>
                  <span className="app-theme-swatch" style={{ background: PALETTES[key].primary }} aria-hidden="true">
                    {brand.color_theme === key && <Icon name="ph-check" size={14} color="#fff" />}
                  </span>
                  {PALETTES[key].label}
                </button>
              ))}
            </div>
          </div>
          <div className="app-form-row app-form-row-3">
            {(["primary_color", "secondary_color", "accent_color"] as const).map((k) => (
              <Field key={k} label={k === "primary_color" ? "Primary colour" : k === "secondary_color" ? "Secondary colour" : "Accent colour"} htmlFor={`b-${k}`} error={brandErrors[k]}>
                <div className="app-co-colorfield">
                  <input type="color" aria-label={`${k} picker`} value={/^#[0-9a-fA-F]{6}$/.test(brand[k]) ? brand[k] : "#2e3192"} onChange={setB(k)} />
                  <input id={`b-${k}`} className="input tnum" value={brand[k]} onChange={setB(k)} placeholder="#1D4ED8" />
                </div>
              </Field>
            ))}
          </div>
          <Field label="Voucher header text" htmlFor="b-head" error={brandErrors.voucher_header_text}>
            <input id="b-head" className="input" value={brand.voucher_header_text} onChange={setB("voucher_header_text")} maxLength={255} />
          </Field>
          <Field label="Voucher footer text" htmlFor="b-foot" error={brandErrors.voucher_footer_text}>
            <textarea id="b-foot" className="input" value={brand.voucher_footer_text} onChange={setB("voucher_footer_text")} maxLength={500} />
          </Field>
        </div>
      </Dialog>
    </div>
  );
}
