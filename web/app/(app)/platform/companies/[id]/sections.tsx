"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate, formatDateTime, money, relativeTime } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, Meter, Pagination } from "@/components/ui";
import type {
  AuditEntry, ColorTheme, Company, Invoice, Paginated, Subscription, Usage, UsageMetric, User, Voucher, Workflow,
} from "@/lib/types";

/*
 * The tabs of the platform's company view. Every number and row here comes
 * from the API for this one company (Platform\CompanyInsightController and
 * the existing company, audit and plan endpoints) — nothing is invented.
 */

export interface Overview {
  vouchers: Record<"total" | "draft" | "in_review" | "changes_requested" | "approved" | "rejected" | "cancelled" | "paid", number>;
  values: Record<"total" | "in_review" | "approved_unpaid" | "approved_including_paid" | "paid" | "rejected", number>;
  stages: { position: number; name: string; role: string | null; count: number; value: number }[];
  payments: {
    paid_count: number; paid_value: number; pending_count: number; pending_value: number;
    recent: {
      id: number; number: string; payee: string; purpose: string; amount: number; currency: string; kind: string;
      payment_method: string | null; payment_reference: string | null; payment_date: string | null;
      paid_at: string | null; paid_by: string | null; department: string | null;
    }[];
  };
  people: { total: number; active: number; by_role: Record<string, number>; departments: number };
  monthly: { month: string; count: number; value: number }[];
  currency: string;
}

export interface Detail {
  data: Company;
  usage: Usage;
  subscription: Subscription | null;
  invoices: Invoice[];
  admins: User[];
}

export interface DepartmentRow {
  id: number; name: string; code: string | null; cost_centre: string | null; is_active: boolean;
  hod: { id: number; name: string; email: string } | null;
  manager: { id: number; name: string; email: string } | null;
  users_count: number; vouchers_count: number; approved_value: number;
}

interface Routing {
  workflow_id: number;
  steps: { id: number; position: number; name: string; role: string; role_label: string; is_request_step: boolean; min_amount: number | null; max_amount: number | null }[];
  departments: { id: number; name: string; hod: { name: string } | null; manager: { name: string } | null; cells: { step_id: number; people: { id: number; name: string; role: string }[]; gap: string | null }[]; gaps: number }[];
  gaps: number;
}

/** The interface palettes a company can choose (companies.color_theme), as styles/app.css paints them. */
export const PALETTES: Record<ColorTheme, { label: string; primary: string; hover: string; soft: string; text: string }> = {
  blue: { label: "Blue", primary: "#2563eb", hover: "#1d4ed8", soft: "#dbeafe", text: "#1d4ed8" },
  emerald: { label: "Emerald", primary: "#047857", hover: "#065f46", soft: "#d1fae5", text: "#047857" },
  violet: { label: "Violet", primary: "#6d28d9", hover: "#5b21b6", soft: "#ede9fe", text: "#6d28d9" },
  rose: { label: "Rose", primary: "#be123c", hover: "#9f1239", soft: "#ffe4e6", text: "#be123c" },
};

const ROLE_LABEL: Record<string, string> = {
  employee: "Employee", hod: "Head of department", manager: "Manager", ceo: "CEO", cashier: "Cashier",
  finance: "Finance", director: "Director", company_admin: "Company admin", custom: "Named person",
};

const STATUS_OPTIONS = [
  ["", "All statuses"], ["draft", "Draft"], ["in_review", "In review"], ["changes_requested", "Changes requested"],
  ["awaiting_payment", "Approved — awaiting payment"], ["paid", "Paid"], ["rejected", "Rejected"], ["cancelled", "Cancelled"],
] as const;

/* ───────────────────────────────────────────────────────────── helpers ── */

export function Card({ title, sub, actions, children, pad = true }: { title?: ReactNode; sub?: ReactNode; actions?: ReactNode; children: ReactNode; pad?: boolean }) {
  return (
    <section className="vf-panel">
      {(title || actions) && (
        <div className="vf-panel-head">
          <div className="vf-panel-head-main">
            {title && <h2>{title}</h2>}
            {sub && <div className="vf-panel-sub">{sub}</div>}
          </div>
          {actions && <div className="vf-panel-actions">{actions}</div>}
        </div>
      )}
      <div className={pad ? "vf-panel-pad" : undefined}>{children}</div>
    </section>
  );
}

function Facts({ rows }: { rows: [string, ReactNode][] }) {
  return (
    <dl className="app-co-facts">
      {rows.map(([label, value]) => (
        <div key={label}><dt>{label}</dt><dd>{value === null || value === undefined || value === "" ? <span className="text-muted">Not set</span> : value}</dd></div>
      ))}
    </dl>
  );
}

function Stat({ label, value, sub, icon, tone = "info" }: { label: string; value: string; sub?: string; icon: string; tone?: "info" | "ok" | "warn" | "bad" | "neutral" }) {
  return (
    <div className="vf-kpi" data-long={value.length > 9 ? "" : undefined}>
      <div className="vf-kpi-top">
        <span className="vf-kpi-label">{label}</span>
        <span className={`vf-kpi-icon tone-${tone}`}><Icon name={icon} /></span>
      </div>
      <div className="vf-kpi-value tnum">{value}</div>
      {sub && <div className="vf-kpi-foot"><span className="vf-kpi-sub">{sub}</span></div>}
    </div>
  );
}

function StatusBadge({ v }: { v: Voucher }) {
  return <span className={`badge ${v.status_tag}`}>{v.status_label_en || v.status_label}</span>;
}

function PersonCell({ name, sub, initials }: { name: string; sub?: string | null; initials?: string }) {
  return (
    <div className="app-person">
      <span className="app-avatar" aria-hidden="true">{initials ?? name.split(" ").map((p) => p[0]).slice(0, 2).join("").toUpperCase()}</span>
      <span className="app-person-text"><strong>{name}</strong>{sub && <span>{sub}</span>}</span>
    </div>
  );
}

function usageLine(m: UsageMetric) {
  if (m.unlimited) return `${m.used.toLocaleString()} ${m.unit} · unlimited`;
  return `${m.used.toLocaleString()} of ${(m.limit ?? 0).toLocaleString()} ${m.unit}`;
}

/* ───────────────────────────────────────────────────────────── overview ── */

export function OverviewTab({ detail, overview, onOpen }: { detail: Detail; overview: Overview; onOpen: (tab: string, filter?: Record<string, string>) => void }) {
  const { locale } = useApp();
  const c = detail.data;
  const cur = overview.currency;
  const v = overview.vouchers;
  const maxMonth = Math.max(1, ...overview.monthly.map((m) => m.value));
  const pipeline: [string, number, string][] = [
    ["Draft", v.draft, "neutral"], ["In review", v.in_review, "info"], ["Changes requested", v.changes_requested, "warn"],
    ["Approved — awaiting payment", v.approved, "ok"], ["Paid", v.paid, "ok"], ["Rejected", v.rejected, "bad"], ["Cancelled", v.cancelled, "neutral"],
  ];

  return (
    <div className="app-stack app-co-stack">
      <div className="vf-kpis">
        <Stat label="People" value={String(overview.people.total)} sub={`${overview.people.active} active · ${usageLine(detail.usage.users)}`} icon="ph-users-three" />
        <Stat label="Departments" value={String(overview.people.departments)} sub={usageLine(detail.usage.departments)} icon="ph-tree-structure" />
        <Stat label="Vouchers" value={String(v.total)} sub={`${v.in_review} in review · ${v.paid} paid`} icon="ph-receipt" />
        <Stat label="Total voucher value" value={money(overview.values.total, cur)} sub="Every status, all time" icon="ph-coins" />
        <Stat label="Approved value" value={money(overview.values.approved_including_paid, cur)} sub={`${v.approved + v.paid} approved (including paid)`} icon="ph-seal-check" tone="ok" />
        <Stat label="Paid out" value={money(overview.values.paid, cur)} sub={`${v.paid} vouchers paid`} icon="ph-hand-coins" tone="ok" />
        <Stat label="Pending payment" value={money(overview.payments.pending_value, cur)} sub={`${overview.payments.pending_count} approved, not yet paid`} icon="ph-hourglass" tone="warn" />
        <Stat label="In review" value={money(overview.values.in_review, cur)} sub={`${v.in_review} waiting on an approver`} icon="ph-clock-countdown" tone="info" />
      </div>

      <div className="app-co-grid">
        <Card title="Voucher pipeline" sub="Where every voucher of this company stands"
          actions={<button type="button" className="btn btn-ghost btn-sm" onClick={() => onOpen("vouchers")}>Open vouchers <Icon name="ph-arrow-right" size={14} /></button>}>
          <div className="app-co-bars">
            {pipeline.map(([label, count, tone]) => (
              <div key={label} className="app-co-bar">
                <div className="app-co-bar-top"><span>{label}</span><strong className="tnum">{count}</strong></div>
                <div className="app-co-bar-track"><span data-tone={tone} style={{ width: `${v.total ? Math.max(count ? 3 : 0, (count / v.total) * 100) : 0}%` }} /></div>
              </div>
            ))}
          </div>
          {overview.stages.length > 0 && (
            <>
              <div className="vf-eyebrow app-co-subhead">In review, by approval step</div>
              <ul className="app-co-stagelist">
                {overview.stages.map((s) => (
                  <li key={`${s.position}-${s.name}`}>
                    <span className="app-co-stagenum tnum">{s.position || "—"}</span>
                    <span className="app-co-stagename">{s.name}{s.role && <small>{ROLE_LABEL[s.role] ?? s.role}</small>}</span>
                    <span className="tnum">{s.count} · {money(s.value, cur)}</span>
                  </li>
                ))}
              </ul>
            </>
          )}
        </Card>

        <Card title="Submitted per month" sub="Value of vouchers submitted, last six months">
          <div className="app-co-columns">
            {overview.monthly.map((m) => {
              const d = new Date(`${m.month}-01T00:00:00`);
              return (
                <div key={m.month} className="app-co-column" title={`${m.count} vouchers · ${money(m.value, cur)}`}>
                  <span className="app-co-column-value tnum">{m.value ? compactMoney(m.value, "") : ""}</span>
                  <span className="app-co-column-bar" style={{ height: `${Math.max(m.value ? 4 : 1, (m.value / maxMonth) * 100)}%` }} />
                  <span className="app-co-column-label">{d.toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { month: "short" })}</span>
                </div>
              );
            })}
          </div>
        </Card>
      </div>

      <div className="app-co-grid">
        <Card title="Company information">
          <Facts rows={[
            ["Legal name", c.legal_name], ["Trading name", c.trading_name], ["Email", c.email], ["Phone", c.phone],
            ["Alternative phone", c.alternative_phone], ["Website", c.website], ["Address", c.address], ["Postal address", c.postal_address],
            ["City", c.city], ["Region", c.region], ["Country", c.country], ["TIN", c.tin],
            ["Registration number", c.registration_number], ["Business licence", c.business_license_number],
            ["Contact person", [c.contact_person, c.contact_email, c.contact_phone].filter(Boolean).join(" · ")],
            ["Currency · locale · timezone", [c.currency, c.locale?.toUpperCase(), c.timezone].filter(Boolean).join(" · ")],
            ["Joined the platform", formatDate(c.created_at, locale)],
          ]} />
        </Card>
        <div className="app-stack">
          <Card title="Account owners" sub="Company administrators" pad={false}>
            {detail.admins.length === 0 ? <p className="app-dash-empty">No company administrator.</p> : (
              <ul className="app-co-people">
                {detail.admins.map((a) => (
                  <li key={a.id}>
                    <PersonCell name={a.name} sub={a.email} initials={a.initials} />
                    <span className={`badge ${a.status === "active" ? "tag-accent" : "tag-neutral"}`}>{a.status}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Card title="People by role" pad={false}>
            <ul className="app-co-people">
              {Object.entries(overview.people.by_role).sort((a, b) => b[1] - a[1]).map(([role, count]) => (
                <li key={role}>
                  <button type="button" className="app-co-linkrow" onClick={() => onOpen("users", { role })}>{ROLE_LABEL[role] ?? role}</button>
                  <strong className="tnum">{count}</strong>
                </li>
              ))}
            </ul>
          </Card>
          <Card title="Bank account on vouchers">
            <Facts rows={[["Bank", c.bank_name], ["Branch", c.bank_branch], ["Account name", c.bank_account_name], ["Account number", c.bank_account_number], ["SWIFT", c.swift_code]]} />
          </Card>
        </div>
      </div>
    </div>
  );
}

/* ───────────────────────────────────────────────────── branding & palette ── */

function Swatch({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div className="app-co-swatch">
      <span style={{ background: value ?? "transparent" }} data-empty={value ? undefined : ""} aria-hidden="true" />
      <div><strong>{label}</strong><code>{value ?? "Not set"}</code></div>
    </div>
  );
}

export function BrandingTab({ company, onEdit, voucherDesign }: { company: Company; onEdit: () => void; voucherDesign?: React.ReactNode }) {
  const palette = PALETTES[company.color_theme ?? "blue"] ?? PALETTES.blue;
  const customPalette = (company.color_theme ?? "blue") !== "blue";
  const hasDocBranding = Boolean(company.logo_url || company.logo_mark_url || company.voucher_header_text || company.secondary_color || company.accent_color);
  const initials = company.initials ?? company.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase();

  return (
    <div className="app-stack app-co-stack">
      <div className="app-co-template">
        <div className="app-co-template-main">
          <div className="vf-eyebrow">Selected interface palette</div>
          <h2>{palette.label}{!customPalette && <span className="badge tag-neutral">VouchFlow default</span>}</h2>
          <p>
            A company chooses its <strong>voucher design</strong> (one of ten payment voucher templates), its <strong>interface
            palette</strong> (the colour of buttons, links, tabs and the current menu item), its default <strong>appearance</strong>,
            and the <strong>document branding</strong> — logo, colours and footer — carried into that design. These are
            {" "}{company.name}&apos;s saved settings.
          </p>
          {!customPalette && !hasDocBranding && (
            <p className="app-co-note"><Icon name="ph-info" size={16} /> No custom branding selected — this company uses the VouchFlow defaults.</p>
          )}
        </div>
        <button type="button" className="btn btn-secondary" onClick={onEdit}><Icon name="ph-paint-brush" size={16} /> Edit branding</button>
      </div>

      {/* The real document: the company's chosen design, rendered by the
          server exactly as its vouchers print. */}
      {voucherDesign}

      <div>
        <Card title="Interface preview" sub={`How ${company.name}'s workspace is painted, in its ${company.theme} appearance`}>
          <div className="app-co-preview" data-theme={company.theme}
            style={{ "--pv-primary": palette.primary, "--pv-hover": palette.hover, "--pv-soft": palette.soft, "--pv-text": palette.text } as React.CSSProperties}>
            <aside className="app-co-preview-side">
              <div className="app-co-preview-brand">
                <span className="app-co-preview-mark">
                  {company.logo_mark_url ? <img src={company.logo_mark_url} alt="" /> : initials}
                </span>
                <span>{company.name}</span>
              </div>
              {[["ph-squares-four", "Dashboard", true], ["ph-receipt", "Vouchers", false], ["ph-list-checks", "Approvals", false], ["ph-chart-line", "Reports", false]].map(([icon, label, active]) => (
                <span key={label as string} className="app-co-preview-nav" data-active={active ? "" : undefined}>
                  <Icon name={icon as string} size={14} /> {label as string}
                </span>
              ))}
            </aside>
            <div className="app-co-preview-main">
              <div className="app-co-preview-top">
                <strong>Voucher register</strong>
                <span className="app-co-preview-btn"><Icon name="ph-plus" size={11} /> New voucher</span>
              </div>
              <div className="app-co-preview-pills">
                <span data-active="">All</span><span>Pending</span><span>Paid</span>
              </div>
              <div className="app-co-preview-card">
                <div className="app-co-preview-row"><span>PV-000142</span><span className="app-co-preview-badge" data-tone="info">In review</span></div>
                <div className="app-co-preview-row"><span>PV-000141</span><span className="app-co-preview-badge" data-tone="ok">Paid</span></div>
                <div className="app-co-preview-row"><span>PC-000087</span><span className="app-co-preview-badge" data-tone="warn">Changes requested</span></div>
              </div>
              <span className="app-co-preview-link">View all vouchers →</span>
            </div>
          </div>
          <p className="app-co-caption">A schematic of the interface in this company&apos;s palette. The rows are illustrative; status colours are the same for every company.</p>
        </Card>
      </div>

      <Card title="Saved branding settings">
        <div className="app-co-swatches">
          <div className="app-co-swatch">
            <span style={{ background: palette.primary }} aria-hidden="true" />
            <div><strong>Interface palette</strong><code>{company.color_theme ?? "blue"} · {palette.primary}</code></div>
          </div>
          <Swatch label="Primary colour (documents)" value={company.primary_color} />
          <Swatch label="Secondary colour" value={company.secondary_color} />
          <Swatch label="Accent colour" value={company.accent_color} />
        </div>
        <Facts rows={[
          ["Default appearance", company.theme === "dark" ? "Dark" : "Light"],
          ["Name shown in the interface", company.name],
          ["Name printed on documents", company.legal_name || company.name],
          ["Voucher header text", company.voucher_header_text],
          ["Voucher footer text", company.voucher_footer_text],
          ["Full logo", company.logo_url ? <img className="app-co-logo" src={company.logo_url} alt="Full logo" /> : null],
          ["Logo mark", company.logo_mark_url ? <img className="app-co-logo app-co-logo-mark" src={company.logo_mark_url} alt="Logo mark" /> : null],
        ]} />
      </Card>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────── users ── */

export function UsersTab({ companyId, departments, roles, initial }: { companyId: number; departments: DepartmentRow[]; roles: string[]; initial?: Record<string, string> }) {
  const { locale } = useApp();
  const [filters, setFilters] = useState({ q: "", role: "", status: "", department_id: "", ...initial });
  const [page, setPage] = useState(1);
  const [result, setResult] = useState<Paginated<User> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<User>>(`/platform/companies/${companyId}/users`, { ...filters, page, per_page: 25 })
      .then(setResult).catch((e) => setError(e.message));
  }, [companyId, filters, page]);
  useEffect(() => { const t = window.setTimeout(load, filters.q ? 250 : 0); return () => window.clearTimeout(t); }, [load, filters.q]);

  const set = (k: keyof typeof filters) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => { setPage(1); setFilters((f) => ({ ...f, [k]: e.target.value })); };
  const rows = result?.data ?? [];

  return (
    <section className="vf-panel">
      <div className="app-toolbar">
        <div className="app-toolbar-main">
          <input className="input app-toolbar-search" placeholder="Search name, email or employee ID" value={filters.q} onChange={set("q")} aria-label="Search people" />
          <select className="input" value={filters.role} onChange={set("role")} aria-label="Role">
            <option value="">All roles</option>
            {roles.map((r) => <option key={r} value={r}>{ROLE_LABEL[r] ?? r}</option>)}
          </select>
          <select className="input" value={filters.status} onChange={set("status")} aria-label="Status">
            <option value="">All statuses</option><option value="active">Active</option><option value="invited">Invited</option><option value="suspended">Suspended</option>
          </select>
          <select className="input" value={filters.department_id} onChange={set("department_id")} aria-label="Department">
            <option value="">All departments</option>
            {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </select>
        </div>
        <div className="app-toolbar-end"><span className="app-result-count tnum">{result?.meta?.total ?? 0} people</span></div>
      </div>
      {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
      {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={5} /></div>}
      {result && rows.length === 0 && <EmptyState icon="ph-users-three" title="No people match these filters" />}
      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Name</th><th>Phone</th><th>Role</th><th>Department</th><th>Status</th><th className="num">Vouchers</th><th>Last sign-in</th><th>Joined</th></tr></thead>
              <tbody>
                {rows.map((u) => (
                  <tr key={u.id}>
                    <td><PersonCell name={u.name} sub={u.email} initials={u.initials} /></td>
                    <td className="app-vt-date">{u.phone ?? "—"}</td>
                    <td>{u.role_label}{u.job_title && <div className="app-cell-sub">{u.job_title}</div>}</td>
                    <td>{u.department?.name ?? "—"}</td>
                    <td><span className={`badge ${u.status === "active" ? "tag-accent" : u.status === "suspended" ? "tag-accent-2" : "tag-neutral"}`}>{u.status}</span></td>
                    <td className="num">{u.voucher_count ?? 0}</td>
                    <td className="app-vt-date">{u.last_login_at ? relativeTime(u.last_login_at, locale) : "Never"}</td>
                    <td className="app-vt-date">{formatDate(u.joined_at, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1} total={result?.meta?.total ?? rows.length} onChange={setPage} />
        </>
      )}
    </section>
  );
}

/* ───────────────────────────────────────────────────────── departments ── */

export function DepartmentsTab({ departments, currency, onOpen }: { departments: DepartmentRow[] | null; currency: string; onOpen: (tab: string, filter?: Record<string, string>) => void }) {
  if (!departments) return <LoadingBlock rows={5} />;
  if (departments.length === 0) return <section className="vf-panel"><EmptyState icon="ph-tree-structure" title="This company has no departments yet" /></section>;
  return (
    <section className="vf-panel">
      <div className="table-wrap">
        <table className="table">
          <thead><tr><th>Department</th><th>Head of department</th><th>Manager</th><th className="num">People</th><th className="num">Vouchers</th><th className="num">Approved value</th><th>Status</th><th><span className="sr-only">Inspect</span></th></tr></thead>
          <tbody>
            {departments.map((d) => (
              <tr key={d.id}>
                <td><strong>{d.name}</strong><div className="app-cell-sub">{[d.code, d.cost_centre].filter(Boolean).join(" · ") || "—"}</div></td>
                <td>{d.hod ? <PersonCell name={d.hod.name} sub={d.hod.email} /> : <span className="badge tag-accent-2">No HOD</span>}</td>
                <td>{d.manager?.name ?? "—"}</td>
                <td className="num">{d.users_count}</td>
                <td className="num">{d.vouchers_count}</td>
                <td className="num">{money(d.approved_value, currency)}</td>
                <td><span className={`badge ${d.is_active ? "tag-accent" : "tag-neutral"}`}>{d.is_active ? "active" : "inactive"}</span></td>
                <td className="app-row-actions">
                  <button type="button" className="btn btn-ghost btn-sm" onClick={() => onOpen("users", { department_id: String(d.id) })}>People</button>
                  <button type="button" className="btn btn-ghost btn-sm" onClick={() => onOpen("vouchers", { department_id: String(d.id) })}>Vouchers</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/* ───────────────────────────────────────────────────────────── workflow ── */

export function WorkflowTab({ companyId }: { companyId: number }) {
  const [data, setData] = useState<{ workflows: Workflow[]; default_id: number | null; routing: Routing | null } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.get<{ data: { workflows: Workflow[]; default_id: number | null; routing: Routing | null } }>(`/platform/companies/${companyId}/workflows`)
      .then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, [companyId]);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={5} />;
  if (data.workflows.length === 0) return <section className="vf-panel"><EmptyState icon="ph-flow-arrow" title="No approval workflow configured" /></section>;

  const caps = (s: Workflow["steps"][number]) => [
    s.can_sign && "Sign", s.can_approve && "Approve", s.can_reject && "Reject",
    s.can_request_changes && "Request changes", s.can_pay && "Pay",
  ].filter(Boolean) as string[];

  return (
    <div className="app-stack app-co-stack">
      {data.workflows.map((wf) => (
        <Card key={wf.id} title={<>{wf.label ?? wf.name} {wf.is_default && <span className="badge tag-info">Default</span>} <span className={`badge ${wf.is_active ? "tag-accent" : "tag-neutral"}`}>{wf.is_active ? "Active" : "Inactive"}</span></>}
          sub={`${wf.voucher_type ? `Applies to ${wf.voucher_type.name}` : "Applies to all voucher types"} · version ${wf.version} · ${wf.vouchers_count ?? 0} vouchers routed`}>
          {wf.description && <p className="app-co-desc">{wf.description}</p>}
          <ol className="app-co-route">
            {wf.steps.map((s, i) => (
              <li key={s.id ?? i}>
                <span className="app-co-route-num tnum">{s.position}</span>
                <div className="app-co-route-body">
                  <strong>{s.label || s.name}</strong>
                  <span>
                    {s.is_request_step ? "The employee who raises the voucher"
                      : s.assigned_user ? `${s.assigned_user.name} (named approver)`
                      : s.role === "hod" ? "Each department's head of department"
                      : s.role === "manager" ? "Each department's manager"
                      : `Everyone with the ${s.role_label} role`}
                  </span>
                  <div className="app-co-route-caps">
                    {caps(s).map((c) => <span key={c} className="badge tag-neutral">{c}</span>)}
                    {s.requires_signature && <span className="badge tag-info">Signature required</span>}
                    {(s.min_amount !== null || s.max_amount !== null) && (
                      <span className="badge tag-outline">
                        {s.min_amount !== null ? `from ${compactMoney(s.min_amount, "")}` : ""}{s.min_amount !== null && s.max_amount !== null ? " " : ""}{s.max_amount !== null ? `up to ${compactMoney(s.max_amount, "")}` : ""}
                      </span>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ol>
        </Card>
      ))}

      {data.routing && (
        <Card title="Who approves in each department" pad={false}
          sub={data.routing.gaps ? `${data.routing.gaps} step(s) resolve to nobody — vouchers would stall there` : "Every step resolves to someone in every department"}>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>Department</th>{data.routing.steps.filter((s) => !s.is_request_step).map((s) => <th key={s.id}>{s.position}. {s.name}</th>)}</tr>
              </thead>
              <tbody>
                {data.routing.departments.map((d) => (
                  <tr key={d.id}>
                    <td><strong>{d.name}</strong></td>
                    {d.cells.map((cell) => (
                      <td key={cell.step_id}>
                        {cell.people.length
                          ? cell.people.map((p) => <div key={p.id}>{p.name}</div>)
                          : <span className="badge tag-accent-2">Nobody — {cell.gap?.replaceAll("_", " ")}</span>}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}

/* ───────────────────────────────────────────────────────────── vouchers ── */

export function VouchersTab({ companyId, departments, currency, initial }: { companyId: number; departments: DepartmentRow[]; currency: string; initial?: Record<string, string> }) {
  const { locale } = useApp();
  const blank = { q: "", status: "", department_id: "", requester_id: "", from: "", to: "", min_amount: "", max_amount: "" };
  const [filters, setFilters] = useState({ ...blank, ...initial });
  const [page, setPage] = useState(1);
  const [result, setResult] = useState<Paginated<Voucher> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [people, setPeople] = useState<User[]>([]);

  useEffect(() => {
    api.get<Paginated<User>>(`/platform/companies/${companyId}/users`, { per_page: 100 }).then((r) => setPeople(r.data)).catch(() => setPeople([]));
  }, [companyId]);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<Voucher>>(`/platform/companies/${companyId}/vouchers`, { ...filters, page, per_page: 20 })
      .then(setResult).catch((e) => setError(e.message));
  }, [companyId, filters, page]);
  useEffect(() => { const t = window.setTimeout(load, filters.q || filters.min_amount || filters.max_amount ? 300 : 0); return () => window.clearTimeout(t); }, [load, filters.q, filters.min_amount, filters.max_amount]);

  const set = (k: keyof typeof blank) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => { setPage(1); setFilters((f) => ({ ...f, [k]: e.target.value })); };
  const rows = result?.data ?? [];
  const active = Object.values(filters).some(Boolean);

  return (
    <div className="app-stack app-co-stack">
      <section className="vf-panel app-filter-card">
        <div className="app-filter-card-top">
          <label className="app-search app-search-lg">
            <Icon name="ph-magnifying-glass" size={18} />
            <input className="input" placeholder="Search number, purpose or payee" value={filters.q} onChange={set("q")} aria-label="Search vouchers" />
          </label>
          <div className="app-filter-card-end">
            <span className="app-result-count tnum">{result?.meta?.total ?? 0} vouchers · <strong>{money(result?.meta?.total_amount ?? 0, currency)}</strong></span>
            {active && <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setPage(1); setFilters({ ...blank }); }}><Icon name="ph-x" size={14} /> Clear filters</button>}
          </div>
        </div>
        <div className="app-co-filters">
          <label><span>Status</span>
            <select className="input" value={filters.status} onChange={set("status")}>{STATUS_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          </label>
          <label><span>Department</span>
            <select className="input" value={filters.department_id} onChange={set("department_id")}>
              <option value="">All departments</option>{departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </label>
          <label><span>Employee</span>
            <select className="input" value={filters.requester_id} onChange={set("requester_id")}>
              <option value="">Everyone</option>{people.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
            </select>
          </label>
          <label><span>From</span><input type="date" className="input" value={filters.from} onChange={set("from")} /></label>
          <label><span>To</span><input type="date" className="input" value={filters.to} onChange={set("to")} /></label>
          <label><span>Min amount</span><input type="number" min="0" inputMode="numeric" className="input" value={filters.min_amount} onChange={set("min_amount")} placeholder="0" /></label>
          <label><span>Max amount</span><input type="number" min="0" inputMode="numeric" className="input" value={filters.max_amount} onChange={set("max_amount")} placeholder="Any" /></label>
        </div>
      </section>

      <section className="vf-panel">
        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
        {result && rows.length === 0 && <EmptyState icon="ph-receipt" title={active ? "No vouchers match these filters" : "This company has no vouchers yet"} />}
        {rows.length > 0 && (
          <>
            <div className="table-wrap">
              <table className="table app-voucher-table">
                <thead><tr><th>Voucher</th><th>Purpose</th><th>Employee</th><th>Department</th><th className="num">Amount</th><th>Status</th><th>Current stage</th><th>Created · updated</th></tr></thead>
                <tbody>
                  {rows.map((v) => (
                    <tr key={v.id}>
                      <td className="app-vt-number"><strong>{v.number}</strong><div><span className="vf-kind">{v.voucher_type?.label ?? v.kind}</span></div></td>
                      <td className="app-vt-purpose"><div className="app-vt-title">{v.purpose}</div><div className="app-vt-meta">{v.payee}</div></td>
                      <td>{v.requester?.name ?? "—"}</td>
                      <td>{v.department?.name ?? "—"}</td>
                      <td className="num app-vt-amount">{v.amount_text || money(v.amount, v.currency)}</td>
                      <td><StatusBadge v={v} /></td>
                      <td>{v.status === "in_review" ? (v.current_step?.name ?? `Step ${v.current_step_position ?? "—"}`) : <span className="text-muted">—</span>}</td>
                      <td className="app-vt-date">{formatDate(v.created_at ?? v.voucher_date, locale)}<div className="app-cell-sub">Updated {formatDate(v.updated_at ?? null, locale)}</div></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1} total={result?.meta?.total ?? rows.length} onChange={setPage} />
          </>
        )}
      </section>
    </div>
  );
}

/* ───────────────────────────────────────────────────────────── payments ── */

export function PaymentsTab({ overview }: { overview: Overview }) {
  const { locale } = useApp();
  const p = overview.payments;
  const cur = overview.currency;
  return (
    <div className="app-stack app-co-stack">
      <div className="vf-kpis">
        <Stat label="Total paid" value={money(p.paid_value, cur)} sub={`${p.paid_count} payments`} icon="ph-hand-coins" tone="ok" />
        <Stat label="Pending payment" value={money(p.pending_value, cur)} sub={`${p.pending_count} approved, awaiting the cashier`} icon="ph-hourglass" tone="warn" />
        <Stat label="Payments made" value={String(p.paid_count)} sub="Vouchers marked paid" icon="ph-receipt" />
      </div>
      <Card title="Recent payments" sub="The latest vouchers paid by this company" pad={false}>
        {p.recent.length === 0 ? <EmptyState icon="ph-hand-coins" title="No payments recorded yet" /> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Voucher</th><th>Payee</th><th>Department</th><th className="num">Amount</th><th>Method</th><th>Reference</th><th>Paid by</th><th>Date</th></tr></thead>
              <tbody>
                {p.recent.map((r) => (
                  <tr key={r.id}>
                    <td><strong>{r.number}</strong><div className="app-cell-sub">{r.kind === "cash" ? "Cash" : "Bank"}</div></td>
                    <td>{r.payee}<div className="app-cell-sub">{r.purpose}</div></td>
                    <td>{r.department ?? "—"}</td>
                    <td className="num app-vt-amount">{money(r.amount, r.currency || cur)}</td>
                    <td>{r.payment_method ?? "—"}</td>
                    <td className="tnum">{r.payment_reference ?? "—"}</td>
                    <td>{r.paid_by ?? "—"}</td>
                    <td className="app-vt-date">{formatDate(r.payment_date ?? r.paid_at, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

/* ───────────────────────────────────────────────────────── subscription ── */

export function SubscriptionTab({ detail, onChangePlan }: { detail: Detail; onChangePlan: () => void }) {
  const { locale, t } = useApp();
  const c = detail.data;
  const s = detail.subscription;
  const metrics: UsageMetric[] = [detail.usage.users, detail.usage.vouchers_this_month, detail.usage.departments, detail.usage.storage];
  return (
    <div className="app-stack app-co-stack">
      <div className="app-co-grid">
        <Card title={c.plan?.name ?? "No plan"} sub={c.plan?.blurb ?? undefined}
          actions={<button type="button" className="btn btn-secondary btn-sm" onClick={onChangePlan}>Change plan</button>}>
          <Facts rows={[
            ["Company status", <span key="s" className={`badge ${c.status === "pending" ? "tone-warn" : "tag-neutral"}`}>{c.status === "pending" ? t("pendingApproval") : c.status}</span>],
            ["Subscription status", s ? s.status : "No active subscription"],
            ["Price", c.plan ? (c.plan.price > 0 ? `${money(c.plan.price, c.plan.currency)} / ${c.plan.billing_cycle === "annual" ? "year" : "month"}` : "Custom") : null],
            ["Billing cycle", s?.billing_cycle ?? c.plan?.billing_cycle],
            ["Started", formatDate(s?.starts_at ?? c.current_period_start, locale)],
            [c.status === "trial" ? "Trial ends" : "Renews", formatDate(c.status === "trial" ? c.trial_ends_at : c.current_period_end, locale)],
            ["Days remaining", c.days_remaining !== null ? String(c.days_remaining) : null],
            ["Auto-renew", c.auto_renew ? "On" : "Off"],
            ["Approval levels allowed", detail.usage.approval_levels.limit === null ? "Unlimited" : String(detail.usage.approval_levels.limit)],
          ]} />
        </Card>
        <Card title="Usage against the plan">
          <div className="app-co-usage">
            {metrics.map((m) => (
              <div key={m.label}>
                <div className="app-co-bar-top"><span>{m.label}</span><strong className="tnum">{usageLine(m)}</strong></div>
                {!m.unlimited && <Meter percent={m.percent} exceeded={m.exceeded} />}
              </div>
            ))}
          </div>
        </Card>
      </div>
      <Card title="Billing history" pad={false}>
        {detail.invoices.length === 0 ? <EmptyState icon="ph-file-text" title="No invoices yet" /> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Invoice</th><th>Description</th><th className="num">Amount</th><th>Status</th><th>Date</th></tr></thead>
              <tbody>
                {detail.invoices.map((inv) => (
                  <tr key={inv.id}>
                    <td className="tnum"><strong>{inv.number}</strong></td>
                    <td>{inv.description}</td>
                    <td className="num">{inv.amount_text}</td>
                    <td><span className={`badge ${inv.status_tag}`}>{inv.status}</span></td>
                    <td className="app-vt-date">{formatDate(inv.paid_at ?? inv.issued_at, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

/* ───────────────────────────────────────────────────────────── activity ── */

const ACTIVITY_ICON: [string, string][] = [
  ["company", "ph-buildings"], ["user", "ph-user-plus"], ["employee", "ph-user-plus"], ["voucher.paid", "ph-hand-coins"],
  ["voucher.approved", "ph-seal-check"], ["voucher.rejected", "ph-x-circle"], ["voucher", "ph-receipt"],
  ["subscription", "ph-crown-simple"], ["billing", "ph-crown-simple"], ["branding", "ph-palette"], ["workflow", "ph-flow-arrow"],
  ["department", "ph-tree-structure"], ["auth", "ph-sign-in"], ["platform", "ph-shield-check"],
];

export function ActivityTab({ companyId }: { companyId: number }) {
  const { locale } = useApp();
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [result, setResult] = useState<Paginated<AuditEntry> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    // The audit log already lets the platform super admin filter by company.
    api.get<Paginated<AuditEntry>>("/audit-logs", { company_id: companyId, q, page, per_page: 30 })
      .then(setResult).catch((e) => setError(e.message));
  }, [companyId, q, page]);
  useEffect(() => { const t = window.setTimeout(load, q ? 250 : 0); return () => window.clearTimeout(t); }, [load, q]);

  const iconFor = useMemo(() => (action: string) => ACTIVITY_ICON.find(([k]) => action.startsWith(k))?.[1] ?? "ph-clock-counter-clockwise", []);
  const rows = result?.data ?? [];

  return (
    <section className="vf-panel">
      <div className="app-toolbar">
        <div className="app-toolbar-main">
          <input className="input app-toolbar-search" placeholder="Search activity or person" value={q} onChange={(e) => { setPage(1); setQ(e.target.value); }} aria-label="Search activity" />
        </div>
        <div className="app-toolbar-end"><span className="app-result-count tnum">{result?.meta?.total ?? 0} entries</span></div>
      </div>
      {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
      {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
      {result && rows.length === 0 && <EmptyState icon="ph-clock-counter-clockwise" title="No recorded activity" />}
      {rows.length > 0 && (
        <>
          <ol className="app-co-timeline">
            {rows.map((a) => (
              <li key={a.id}>
                <span className="app-co-timeline-icon"><Icon name={iconFor(a.action)} size={16} /></span>
                <div className="app-co-timeline-body">
                  <strong>{a.description}</strong>
                  {a.change_summary && <span className="app-co-timeline-change">{a.change_summary}</span>}
                  <span className="app-co-timeline-meta">
                    {a.actor.name}{a.actor.role ? ` · ${ROLE_LABEL[a.actor.role] ?? a.actor.role}` : ""} · <code>{a.action}</code>
                    {a.entity_type ? ` · ${a.entity_type.split("\\").pop()} #${a.entity_id}` : ""}
                  </span>
                </div>
                <time className="app-co-timeline-when" dateTime={a.created_at ?? undefined} title={formatDateTime(a.created_at, locale)}>{relativeTime(a.created_at, locale)}</time>
              </li>
            ))}
          </ol>
          <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1} total={result?.meta?.total ?? rows.length} onChange={setPage} />
        </>
      )}
    </section>
  );
}
