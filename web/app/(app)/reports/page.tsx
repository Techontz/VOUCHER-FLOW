"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, API_MODE } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import { useReportExport } from "@/components/voucher-bits";
import type { Department, VoucherType } from "@/lib/types";

interface ReportKind {
  key: string; icon: string; title: string; title_sw: string; body: string; body_sw: string;
}

interface ReportSummary {
  count: number; total_text: string; approved_total_text: string;
  /* Payment and cash reports only. */
  paid_total_text?: string; paid_count?: number;
  bank_total_text?: string; bank_count?: number;
  cash_total_text?: string; cash_count?: number;
  outstanding_total_text?: string; outstanding_count?: number;
}

interface ReportResult {
  kind: string;
  headings: string[];
  rows: (string | number | null)[][];
  summary: ReportSummary;
  generated_at: string;
}

/**
 * What this caller is allowed to look back over — ReportController::scopeDescriptor.
 * A department picker may narrow this ceiling and can never widen it.
 */
interface ReportScope { level: "own" | "departments" | "company"; label: string; department_ids: number[] | null }

interface Person { id: number; name: string; department_id: number | null }

type FilterKey = "q" | "from" | "to" | "department_id" | "requester_id" | "voucher_type_id" | "status" | "kind";
type StatusSet = "full" | "payment" | null;

/**
 * Which filters make sense for each report. A control that cannot change the
 * result is not offered: the department report already lists every department,
 * the employee report already groups by person, and the money reports only
 * ever hold approved vouchers, so they get a payment status instead.
 */
const FILTERS: Record<string, { keys: FilterKey[]; status: StatusSet; money?: boolean }> = {
  vouchers: { keys: ["q", "from", "to", "department_id", "requester_id", "voucher_type_id", "kind", "status"], status: "full" },
  expenses: { keys: ["from", "to", "department_id", "requester_id", "voucher_type_id", "kind", "status"], status: "payment" },
  payments: { keys: ["q", "from", "to", "department_id", "requester_id", "voucher_type_id", "kind", "status"], status: "payment", money: true },
  cash: { keys: ["q", "from", "to", "department_id", "requester_id", "voucher_type_id", "status"], status: "payment", money: true },
  departments: { keys: ["from", "to", "voucher_type_id", "kind"], status: null },
  employees: { keys: ["from", "to", "department_id", "voucher_type_id", "kind"], status: null },
  approvals: { keys: ["from", "to", "department_id", "requester_id", "voucher_type_id", "kind", "status"], status: "full" },
  monthly: { keys: ["from", "to", "department_id", "requester_id", "voucher_type_id", "kind"], status: null },
};
const DEFAULT_FILTERS = { keys: ["from", "to", "department_id", "voucher_type_id", "kind"] as FilterKey[], status: null as StatusSet };

const FULL_STATUSES: { value: string; key: MessageKey }[] = [
  { value: "drafts", key: "statusDraft" },
  { value: "pending", key: "statusInReview" },
  { value: "changes_requested", key: "changesRequestedTab" },
  { value: "awaiting_payment", key: "awaitingPayment" },
  { value: "paid", key: "paidAct" },
  { value: "rejected", key: "rejected" },
  { value: "cancelled", key: "stageCancelled" },
];
const PAYMENT_STATUSES: { value: string; key: MessageKey }[] = [
  { value: "awaiting_payment", key: "awaitingPayment" },
  { value: "paid", key: "paidAct" },
];

const BLANK: Record<FilterKey, string> = { q: "", from: "", to: "", department_id: "", requester_id: "", voucher_type_id: "", status: "", kind: "" };

export default function ReportsPage() {
  const { t, locale } = useApp();
  const [kinds, setKinds] = useState<ReportKind[]>([]);
  const [scope, setScope] = useState<ReportScope | null>(null);
  const [active, setActive] = useState("vouchers");
  const [filters, setFilters] = useState({ ...BLANK });
  const [result, setResult] = useState<ReportResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [types, setTypes] = useState<VoucherType[]>([]);
  const [people, setPeople] = useState<Person[]>([]);
  const { run: runExport, busy: exporting } = useReportExport();

  useEffect(() => {
    api.get<{ data: ReportKind[]; scope: ReportScope }>("/reports")
      .then((r) => {
        setKinds(r.data);
        setScope(r.scope);
        // Land on a report this role can actually run.
        if (r.data.length && !r.data.some((k) => k.key === "vouchers")) setActive(r.data[0].key);
      })
      .catch(() => undefined);
    api.get<{ data: Department[] }>("/departments").then((r) => setDepartments(r.data)).catch(() => undefined);
    api.get<{ data: VoucherType[] }>("/voucher-types").then((r) => setTypes(r.data)).catch(() => undefined);
  }, []);

  // People to filter by — only for a caller who can see anyone but themselves.
  useEffect(() => {
    if (!scope || scope.level === "own") return;
    api.get<{ data: Person[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
  }, [scope]);

  const config = FILTERS[active] ?? DEFAULT_FILTERS;
  const statusOptions = config.status === "full" ? FULL_STATUSES : config.status === "payment" ? PAYMENT_STATUSES : [];

  // Departments inside the caller's ceiling; the picker only narrows it.
  const pickableDepartments = useMemo(() => {
    if (!scope || scope.level === "own") return [];
    if (scope.level === "company" || scope.department_ids === null) return departments;
    return departments.filter((d) => scope.department_ids?.includes(d.id));
  }, [scope, departments]);

  const pickablePeople = useMemo(() => {
    if (!scope || scope.level === "own") return [];
    if (scope.level === "company" || scope.department_ids === null) return people;
    return people.filter((p) => p.department_id !== null && scope.department_ids?.includes(p.department_id));
  }, [scope, people]);

  const shows = (key: FilterKey) => {
    if (!config.keys.includes(key)) return false;
    if (key === "department_id") return pickableDepartments.length > 1;
    if (key === "requester_id") return pickablePeople.length > 1;
    return true;
  };

  /* Only the filters this report shows are sent, so a value chosen on another
     report (or a status this report cannot hold) never silently narrows it. */
  const params: Record<string, string> = Object.fromEntries(
    (Object.entries(filters) as [FilterKey, string][]).filter(([key, value]) =>
      value !== "" && shows(key) && (key !== "status" || statusOptions.some((o) => o.value === value))),
  );
  const searchTerm = params.q ?? "";
  // A stable key, so the report reloads when the sent filters change — not on every render.
  const query = JSON.stringify(params);

  const load = useCallback(() => {
    setLoading(true); setError(null);
    api.get<ReportResult>(`/reports/${active}`, JSON.parse(query) as Record<string, string>)
      .then(setResult)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [active, query]);

  useEffect(() => {
    const timer = window.setTimeout(load, searchTerm ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, locale, searchTerm]);

  const set = (key: FilterKey) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setFilters((f) => ({ ...f, [key]: e.target.value }));

  const activeKind = kinds.find((k) => k.key === active);
  const isNumeric = (heading: string) =>
    /amount|value|total|turnaround|vouchers|approved|rejected|pending|requests/i.test(heading);

  const sw = locale === "sw";
  const hasFilters = Object.keys(params).length > 0;
  const hint = config.money
    ? t("reportDateHintMoney")
    : config.status === "payment"
      ? t("reportApprovedOnlyHint")
      : null;
  const s = result?.summary;

  return (
    <div className="app-page app-reports">
      <PageHeader title={t("reports")} sub={t("filterExport")} />

      <div className="app-reports-grid">
        <aside className="app-report-kinds" aria-label={t("reportsYouMayRun")}>
          <div className="app-report-kinds-head">
            <span>{t("reportsYouMayRun")}</span>
            <span className="vf-count">{kinds.length}</span>
          </div>
          {kinds.map((kind) => (
            <button key={kind.key} type="button" onClick={() => setActive(kind.key)} aria-pressed={kind.key === active} className="app-report-kind">
              <Icon name={kind.icon} size={17} />
              <span className="app-report-kind-text">
                <strong>{sw ? kind.title_sw : kind.title}</strong>
                <span>{sw ? kind.body_sw : kind.body}</span>
              </span>
            </button>
          ))}
        </aside>

        <section className="app-report-main">
          <div className="vf-panel">
            <div className="vf-panel-head app-report-head">
              <div className="vf-panel-head-main">
                <h2>{sw ? activeKind?.title_sw ?? t("reports") : activeKind?.title ?? t("reports")}</h2>
                {scope && (
                  <div className="vf-panel-sub app-report-scope">
                    <Icon name={scope.level === "company" ? "ph-eye" : "ph-lock-key"} size={13} /> {scope.label}
                  </div>
                )}
              </div>
              <div className="vf-panel-actions">
                <button className="btn btn-secondary btn-sm" onClick={() => runExport(active, params, "pdf")} disabled={exporting !== null}>
                  {exporting === "pdf" ? <Spinner /> : <><Icon name="ph-file-pdf" size={14} /> PDF</>}
                </button>
                {API_MODE === "live" && (
                  <button className="btn btn-secondary btn-sm" onClick={() => runExport(active, params, "xlsx")} disabled={exporting !== null}>
                    {exporting === "xlsx" ? <Spinner /> : <><Icon name="ph-microsoft-excel-logo" size={14} /> Excel</>}
                  </button>
                )}
                <button className="btn btn-secondary btn-sm" onClick={() => runExport(active, params, "csv")} disabled={exporting !== null}>
                  {exporting === "csv" ? <Spinner /> : <><Icon name="ph-file-csv" size={14} /> CSV</>}
                </button>
              </div>
            </div>

            <div className="app-toolbar app-report-filters">
              <div className="app-toolbar-main">
                {shows("q") && (
                  <label className="app-filter-labelled"><span>{t("search")}</span>
                    <input className="input" type="search" value={filters.q} onChange={set("q")} placeholder={t("searchPh")} aria-label={t("search")} />
                  </label>
                )}
                <label className="app-filter-labelled"><span>{t("from")}</span>
                  <input className="input" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
                </label>
                <label className="app-filter-labelled"><span>{t("to")}</span>
                  <input className="input" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
                </label>
                {shows("department_id") && (
                  <label className="app-filter-labelled"><span>{t("department")}</span>
                    <select className="input" value={filters.department_id} onChange={set("department_id")} aria-label={t("department")}>
                      <option value="">{scope?.level === "departments" ? scope.label : t("allDepartments")}</option>
                      {pickableDepartments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                    </select>
                  </label>
                )}
                {shows("requester_id") && (
                  <label className="app-filter-labelled"><span>{t("employeeFilter")}</span>
                    <select className="input" value={filters.requester_id} onChange={set("requester_id")} aria-label={t("employeeFilter")}>
                      <option value="">{t("allEmployees")}</option>
                      {pickablePeople.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                    </select>
                  </label>
                )}
                {shows("kind") && (
                  <label className="app-filter-labelled"><span>{t("voucherKind")}</span>
                    <select className="input" value={filters.kind} onChange={set("kind")} aria-label={t("voucherKind")}>
                      <option value="">{t("all")}</option>
                      <option value="bank">{t("bankVoucher")}</option>
                      <option value="cash">{t("cashVoucher")}</option>
                    </select>
                  </label>
                )}
                {shows("voucher_type_id") && (
                  <label className="app-filter-labelled"><span>{t("voucherType")}</span>
                    <select className="input" value={filters.voucher_type_id} onChange={set("voucher_type_id")} aria-label={t("voucherType")}>
                      <option value="">{t("allTypes")}</option>
                      {types.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
                    </select>
                  </label>
                )}
                {shows("status") && statusOptions.length > 0 && (
                  <label className="app-filter-labelled">
                    <span>{config.status === "payment" ? t("paymentStatus") : t("status")}</span>
                    <select className="input" value={statusOptions.some((o) => o.value === filters.status) ? filters.status : ""}
                      onChange={set("status")} aria-label={config.status === "payment" ? t("paymentStatus") : t("status")}>
                      <option value="">{config.status === "payment" ? t("allPaymentStatuses") : t("allStatuses")}</option>
                      {statusOptions.map((o) => <option key={o.value} value={o.value}>{t(o.key)}</option>)}
                    </select>
                  </label>
                )}
              </div>
              {hasFilters && (
                <div className="app-toolbar-end">
                  <button className="btn btn-ghost btn-sm" onClick={() => setFilters({ ...BLANK })}>
                    <Icon name="ph-x" size={13} /> {t("clearFilters")}
                  </button>
                </div>
              )}
            </div>

            <div className="vf-panel-sub" style={{ padding: "8px 16px 0", display: "flex", gap: 6, alignItems: "center" }}>
              <Icon name="ph-info" size={13} /> {hint ?? t("reportDateHintVoucher")}
            </div>

            {s && !error && (
              config.money ? (
                <div className="app-report-figures">
                  {active === "cash" ? (
                    <>
                      <div><span>{t("paidInCash")}</span><strong className="tnum">{s.cash_total_text ?? s.paid_total_text}</strong><span className="tnum">{s.cash_count ?? s.paid_count ?? 0} {t("vouchersWord")}</span></div>
                      <div><span>{t("outstanding")}</span><strong className="tnum">{s.outstanding_total_text}</strong><span className="tnum">{s.outstanding_count ?? 0} {t("vouchersWord")}</span></div>
                      <div><span>{t("amount")}</span><strong className="tnum">{s.total_text}</strong><span className="tnum">{s.count} {t("vouchersWord")}</span></div>
                    </>
                  ) : (
                    <>
                      <div><span>{t("paidByBank")}</span><strong className="tnum">{s.bank_total_text}</strong><span className="tnum">{s.bank_count ?? 0} {t("vouchersWord")}</span></div>
                      <div><span>{t("paidInCash")}</span><strong className="tnum">{s.cash_total_text}</strong><span className="tnum">{s.cash_count ?? 0} {t("vouchersWord")}</span></div>
                      <div><span>{t("outstanding")}</span><strong className="tnum">{s.outstanding_total_text}</strong><span className="tnum">{s.outstanding_count ?? 0} {t("vouchersWord")}</span></div>
                    </>
                  )}
                  <div><span>{t("generatedOn")}</span><strong className="tnum">{formatDate(result.generated_at, locale)}</strong></div>
                </div>
              ) : (
                <div className="app-report-figures">
                  <div><span>{t("vouchers")}</span><strong className="tnum">{s.count}</strong></div>
                  <div><span>{t("amount")}</span><strong className="tnum">{s.total_text}</strong></div>
                  <div><span>{t("awaitingPayment")}</span><strong className="tnum">{s.approved_total_text}</strong></div>
                  <div><span>{t("generatedOn")}</span><strong className="tnum">{formatDate(result.generated_at, locale)}</strong></div>
                </div>
              )
            )}

            {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
            {loading && !result && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}

            {result && !error && (
              result.rows.length === 0 ? (
                <EmptyState icon="ph-chart-line" title={t("noResults")} />
              ) : (
                <div className="table-wrap" data-loading={loading || undefined}>
                  <table className="table app-report-table">
                    <thead>
                      <tr>{result.headings.map((h) => (
                        <th key={h} className={isNumeric(h) ? "num" : undefined}>{h}</th>
                      ))}</tr>
                    </thead>
                    <tbody>
                      {result.rows.map((row, i) => (
                        <tr key={i}>
                          {row.map((cell, j) => {
                            // Formatting is for the screen only. The same rows feed the
                            // PDF, Excel and CSV exports, which keep their raw values.
                            const isDate = typeof cell === "string" && /^\d{4}-\d{2}-\d{2}(T|$)/.test(cell);
                            const isRef = typeof cell === "string" && /^[A-Z]{2,5}-\d{4}-\d+$/.test(cell);
                            const tight = typeof cell === "number" || isDate || isRef;
                            return (
                              <td key={j} className={isNumeric(result.headings[j]) ? "num" : undefined} style={{
                                fontVariantNumeric: tight ? "tabular-nums" : undefined,
                                whiteSpace: tight ? "nowrap" : undefined,
                                fontWeight: isRef ? 600 : undefined,
                              }}>
                                {typeof cell === "number"
                                  ? cell.toLocaleString("en-US", { maximumFractionDigits: 2 })
                                  : isDate ? formatDate(cell as string, locale) : cell ?? "—"}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
