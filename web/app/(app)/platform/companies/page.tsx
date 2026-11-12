"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator, SearchInput, Toolbar } from "@/components/app-ui";
import { COMPANY_STATUS, fill } from "@/lib/platform";
import { AppPicker, planApps } from "@/components/app-picker";
import type { Company, Paginated, Plan } from "@/lib/types";

type PlanOption = Plan;

const BLANK = {
  name: "", email: "", phone: "", plan_id: "",
  admin_name: "", admin_email: "", admin_job_title: "", admin_password: "",
};

/** What the super admin is about to do to a company, and to which one. */
type Pending = { kind: "suspend" | "activate" | "delete" | "approve"; company: Company } | null;

export default function PlatformCompaniesPage() {
  const { t, locale, toast, reportError } = useApp();
  const router = useRouter();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", status: "", plan_id: "", sort: "" });
  const [result, setResult] = useState<Paginated<Company> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [plans, setPlans] = useState<PlanOption[]>([]);

  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ ...BLANK });
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  // The apps the new company's subscription includes; null follows the plan.
  const [createApps, setCreateApps] = useState<string[] | null>(null);
  const [pending, setPending] = useState<Pending>(null);
  const [approveApps, setApproveApps] = useState<string[]>([]);
  const [confirmName, setConfirmName] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<Company>>("/platform/companies", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q, locale]);

  // A link from the overview may carry ?status=pending or ?sort=newest.
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const status = q.get("status") ?? "";
    const sort = q.get("sort") ?? "";
    // Read once from the address bar, an external source, after hydration.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (status || sort) setFilters((f) => ({ ...f, status, sort }));
  }, []);

  const filter = (key: keyof typeof filters) => (value: string) => { setPage(1); setFilters((f) => ({ ...f, [key]: value })); };

  useEffect(() => {
    api.get<{ data: PlanOption[] }>("/platform/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  const set = (key: keyof typeof BLANK) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  // Without a choice the API starts the first active plan, so the picker shows that one's apps.
  const createPlan = plans.find((p) => String(p.id) === form.plan_id)
    ?? [...plans].filter((p) => p.is_active).sort((a, b) => a.sort_order - b.sort_order)[0] ?? null;
  const createAppList = createApps ?? planApps(createPlan);

  function openCreate() {
    setForm({ ...BLANK }); setCreateApps(null); setFieldErrors({}); setFormError(null); setCreating(true);
  }

  /** Approving confirms the apps first: those chosen at registration, else the plan's. */
  function openApprove(company: Company) {
    setApproveApps(company.licensed_modules ?? planApps(company.plan));
    setPending({ kind: "approve", company });
  }

  async function createCompany() {
    setBusy(true); setFieldErrors({}); setFormError(null);
    try {
      const res = await api.post<{ data: Company }>("/platform/companies", {
        company: { name: form.name.trim(), email: form.email.trim(), phone: form.phone.trim() || undefined },
        admin: {
          name: form.admin_name.trim(), email: form.admin_email.trim(),
          job_title: form.admin_job_title.trim() || undefined, password: form.admin_password,
        },
        plan_id: form.plan_id ? Number(form.plan_id) : undefined,
        modules: createAppList,
      });
      setCreating(false);
      toast("Company created", `${res.data?.name ?? form.name} is on a trial. ${form.admin_email} can sign in now.`, "ok");
      load();
    } catch (err) {
      if (err instanceof ApiError && Object.keys(err.errors).length) {
        setFieldErrors(Object.fromEntries(Object.entries(err.errors).map(([k, v]) => [k, v[0]])));
      } else {
        setFormError(err instanceof Error ? err.message : "Could not create the company.");
      }
    } finally { setBusy(false); }
  }

  async function confirmPending() {
    if (!pending) return;
    const { kind, company } = pending;
    setBusy(true);
    try {
      if (kind === "delete") {
        await api.delete(`/platform/companies/${company.id}`);
        toast("Company deleted", company.name, "warn");
      } else if (kind === "approve") {
        await api.post(`/platform/companies/${company.id}/approve`, { modules: approveApps });
        toast(t("companyApproved"), company.name, "ok");
      } else {
        await api.post(`/platform/companies/${company.id}/${kind}`);
        toast(kind === "suspend" ? "Company suspended" : "Company activated", company.name, kind === "suspend" ? "warn" : "ok");
      }
      setPending(null);
      load();
    } catch (err) { reportError(err, kind === "approve" ? t("approveCompanyFailed") : "Could not update the company"); }
    finally { setBusy(false); }
  }

  const rows = result?.data ?? [];
  const canCreate = form.name.trim() && form.email.trim() && form.admin_name.trim() && form.admin_email.trim() && form.admin_password.length >= 8;
  const err = (key: string) => fieldErrors[key];

  return (
    <div className="app-page">
      <PageHeader kicker={t("pfPlatform")} title={t("companies")}
        sub={t("pfCompaniesSub")}
        actions={<button type="button" className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={17} /> New company</button>} />

      <section className="vf-panel">
      <Toolbar end={result?.meta && <span className="pf-muted pf-nowrap">{fill(t("pfResults"), { n: result.meta.total })}</span>}>
        <SearchInput value={filters.q} onChange={filter("q")} placeholder={t("pfSearchCompanies")} />
        <select className="input" value={filters.status} onChange={(e) => filter("status")(e.target.value)} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          {["pending", "trial", "active", "past_due", "suspended", "expired", "cancelled"].map((k) => (
            <option key={k} value={k}>{t(COMPANY_STATUS[k].label)}</option>
          ))}
        </select>
        <select className="input" value={filters.plan_id} onChange={(e) => filter("plan_id")(e.target.value)} aria-label={t("plan")}>
          <option value="">{t("pfAllPlans")}</option>
          {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <select className="input" value={filters.sort} onChange={(e) => filter("sort")(e.target.value)} aria-label={t("pfSort")}>
          <option value="">{t("pfSortName")}</option>
          <option value="newest">{t("pfSortNewest")}</option>
          <option value="oldest">{t("pfSortOldest")}</option>
          <option value="users">{t("pfSortUsers")}</option>
          <option value="vouchers">{t("pfSortVouchers")}</option>
          <option value="renewal">{t("pfSortRenewal")}</option>
        </select>
      </Toolbar>

      {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
      {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
      {result && rows.length === 0 && (
        <EmptyState icon="ph-buildings" title={t("noResults")}
          action={<button type="button" className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={17} /> New company</button>} />
      )}

      {rows.length > 0 && (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead>
                <tr><th>{t("companyName")}</th><th>{t("plan")}</th><th style={{ textAlign: "right" }}>{t("users")}</th>
                  <th style={{ textAlign: "right" }}>{t("vouchers")}</th><th>{t("status")}</th><th>{t("pfRenews")}</th><th>{t("joined")}</th>
                  <th><span className="sr-only">Actions</span></th></tr>
              </thead>
              <tbody>
                {rows.map((company) => (
                  <tr key={company.id}>
                    <td>
                      <Link href={`/platform/companies/${company.id}`} style={{ fontWeight: 600 }}>{company.name}</Link>
                      <div className="app-cell-sub">{company.email}</div>
                    </td>
                    <td>{company.plan?.name ?? "-"}</td>
                    <td className="num">{company.users_count ?? 0}</td>
                    <td className="num">{company.vouchers_count ?? 0}</td>
                    <td>
                      {(() => {
                        const key = company.is_expired && ["trial", "active", "past_due"].includes(company.status) ? "expired" : company.status;
                        const st = COMPANY_STATUS[key];
                        return <Badge tone={st?.tone ?? "neutral"} dot>{st ? t(st.label) : company.status}</Badge>;
                      })()}
                    </td>
                    <td className="app-vt-date">
                      {formatDate(company.status === "trial" ? company.trial_ends_at : company.current_period_end, locale)}
                    </td>
                    <td className="app-vt-date">{formatDate(company.created_at, locale)}</td>
                    <td className="app-row-actions">
                      {company.status === "pending" && (
                        <button type="button" className="btn btn-primary btn-sm" style={{ marginRight: 6 }} onClick={() => openApprove(company)}>
                          <Icon name="ph-check-circle" size={15} /> {t("approve")}
                        </button>
                      )}
                      <Dropdown floating label={`Actions for ${company.name}`}
                        trigger={({ open, toggle, id }) => (
                          <button type="button" className="btn btn-icon btn-sm" onClick={toggle} aria-expanded={open} aria-controls={id}
                            aria-haspopup="menu" aria-label={`Actions for ${company.name}`}>
                            <Icon name="ph-dots-three-outline" size={18} />
                          </button>
                        )}>
                        {(close) => (
                          <>
                            <MenuItem icon="ph-arrow-square-out" onSelect={() => { close(); router.push(`/platform/companies/${company.id}`); }}>{t("pfViewDetails")}</MenuItem>
                            <MenuItem icon="ph-puzzle-piece" onSelect={() => { close(); router.push(`/platform/companies/${company.id}#modules`); }}>{t("pfModules")}</MenuItem>
                            <MenuItem icon="ph-crown-simple" onSelect={() => { close(); router.push(`/platform/companies/${company.id}#subscription`); }}>{t("pfSubscription")}</MenuItem>
                            {company.status === "pending" ? (
                              <MenuItem icon="ph-check-circle" onSelect={() => { close(); openApprove(company); }}>{t("approveCompany")}</MenuItem>
                            ) : company.status === "suspended" ? (
                              <MenuItem icon="ph-check-circle" onSelect={() => { close(); setPending({ kind: "activate", company }); }}>{t("activate")}</MenuItem>
                            ) : (
                              <MenuItem icon="ph-prohibit" onSelect={() => { close(); setPending({ kind: "suspend", company }); }}>{t("suspend")}</MenuItem>
                            )}
                            <MenuSeparator />
                            <MenuItem icon="ph-trash" tone="danger" onSelect={() => { close(); setConfirmName(""); setPending({ kind: "delete", company }); }}>Delete company</MenuItem>
                          </>
                        )}
                      </Dropdown>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1}
            total={result?.meta?.total ?? rows.length} onChange={setPage} />
        </>
      )}
      </section>

      <Dialog open={creating} wide busy={busy} onClose={() => setCreating(false)} icon="ph-buildings"
        title="New company" sub="Creates the workspace on a trial of the chosen plan, with its default voucher types and approval workflow, and its first administrator."
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setCreating(false)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className="btn btn-primary" onClick={() => void createCompany()} disabled={busy || !canCreate}>
            <Icon name="ph-plus" size={16} /> {busy ? "Creating…" : "Create company"}
          </button>
        </>}>
        <div className="app-stack">
          {formError && <ErrorState message={formError} />}
          <div className="vf-eyebrow">Company</div>
          <Field label={t("companyName")} htmlFor="nc-name" required error={err("company.name")}>
            <input id="nc-name" className="input" value={form.name} onChange={set("name")} placeholder="Kilimanjaro Logistics Ltd" aria-invalid={Boolean(err("company.name"))} />
          </Field>
          <div className="app-form-row">
            <Field label="Company email" htmlFor="nc-email" required error={err("company.email")}>
              <input id="nc-email" type="email" className="input" value={form.email} onChange={set("email")} placeholder="finance@company.co.tz" aria-invalid={Boolean(err("company.email"))} />
            </Field>
            <Field label="Phone" htmlFor="nc-phone" error={err("company.phone")}>
              <input id="nc-phone" className="input" value={form.phone} onChange={set("phone")} placeholder="+255 7…" />
            </Field>
          </div>
          <Field label={t("plan")} htmlFor="nc-plan" hint="Leave on the default to start on the first active plan." error={err("plan_id")}>
            <select id="nc-plan" className="input" value={form.plan_id} onChange={(e) => { set("plan_id")(e); setCreateApps(null); }}>
              <option value="">Default plan</option>
              {plans.map((p) => <option key={p.id} value={p.id}>{p.name}{p.trial_days ? ` · ${p.trial_days}-day trial` : ""}</option>)}
            </select>
          </Field>

          <div className="vf-eyebrow" style={{ marginTop: 8 }}>{t("pfAppsTitle")}</div>
          <p className="field-hint" style={{ margin: 0 }}>{t("pfAppsCreateHint")}</p>
          <AppPicker operator plan={createPlan} value={createAppList} onChange={setCreateApps} disabled={busy} />
          {err("modules") && <p className="field-error">{err("modules")}</p>}

          <div className="vf-eyebrow" style={{ marginTop: 8 }}>First administrator</div>
          <div className="app-form-row">
            <Field label="Full name" htmlFor="nc-admin" required error={err("admin.name")}>
              <input id="nc-admin" className="input" value={form.admin_name} onChange={set("admin_name")} aria-invalid={Boolean(err("admin.name"))} />
            </Field>
            <Field label="Job title" htmlFor="nc-title" error={err("admin.job_title")}>
              <input id="nc-title" className="input" value={form.admin_job_title} onChange={set("admin_job_title")} placeholder="Company Administrator" />
            </Field>
          </div>
          <div className="app-form-row">
            <Field label="Sign-in email" htmlFor="nc-admin-email" required error={err("admin.email")}>
              <input id="nc-admin-email" type="email" className="input" value={form.admin_email} onChange={set("admin_email")} autoComplete="off" aria-invalid={Boolean(err("admin.email"))} />
            </Field>
            <Field label="Temporary password" htmlFor="nc-admin-pass" required hint="At least 8 characters. Share it privately; they can change it from their profile." error={err("admin.password")}>
              <input id="nc-admin-pass" type="password" className="input" value={form.admin_password} onChange={set("admin_password")} autoComplete="new-password" aria-invalid={Boolean(err("admin.password"))} />
            </Field>
          </div>
        </div>
      </Dialog>

      <Dialog open={pending !== null} busy={busy} onClose={() => setPending(null)} wide={pending?.kind === "approve"}
        icon={pending?.kind === "delete" ? "ph-trash" : pending?.kind === "suspend" ? "ph-prohibit" : "ph-check-circle"}
        tone={pending?.kind === "activate" || pending?.kind === "approve" ? "ok" : pending?.kind === "suspend" ? "warn" : "bad"}
        title={pending?.kind === "approve" ? t("approveCompanyQ").replace("{name}", pending.company.name)
          : pending?.kind === "delete" ? "Delete this company?" : pending?.kind === "suspend" ? "Suspend this company?" : "Reactivate this company?"}
        sub={pending?.kind === "approve" ? t("approveCompanySub") : pending?.kind === "delete"
          ? "The company disappears from the platform, and every one of its people is signed out and deleted. Its records are kept in the database, not erased."
          : pending?.kind === "suspend"
            ? "Everyone in the company is signed out immediately and cannot use VouchFlow until you reactivate it. Nothing is deleted."
            : "Its people can sign in again straight away."}
        summary={pending ? [
          { label: t("companyName"), value: pending.company.name },
          ...(pending.kind === "approve" ? [{ label: t("plan"), value: pending.company.plan?.name ?? "-" }] : []),
          { label: t("users"), value: String(pending.company.users_count ?? 0) },
          { label: t("vouchers"), value: String(pending.company.vouchers_count ?? 0) },
        ] : undefined}
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setPending(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button"
            className={pending?.kind === "activate" || pending?.kind === "approve" ? "btn btn-primary" : "btn btn-danger-solid"}
            disabled={busy || (pending?.kind === "delete" && confirmName.trim() !== pending.company.name)}
            onClick={() => void confirmPending()}>
            {pending?.kind === "approve" ? t("approve") : pending?.kind === "delete" ? "Delete company" : pending?.kind === "suspend" ? t("suspend") : t("activate")}
          </button>
        </>}>
        {pending?.kind === "approve" && (
          <div className="app-stack">
            <div className="vf-eyebrow">{t("pfAppsTitle")}</div>
            <p className="field-hint" style={{ margin: 0 }}>{t("pfAppsApproveHint")}</p>
            <AppPicker operator plan={pending.company.plan} value={approveApps} onChange={setApproveApps} disabled={busy} />
          </div>
        )}
        {pending?.kind === "delete" && (
          <Field label={`Type ${pending.company.name} to confirm`} htmlFor="nc-confirm">
            <input id="nc-confirm" className="input" value={confirmName} onChange={(e) => setConfirmName(e.target.value)} autoComplete="off" />
          </Field>
        )}
      </Dialog>
    </div>
  );
}
