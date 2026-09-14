"use client";

import { useCallback, useEffect, useState } from "react";
import { api, API_MODE, download, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import type { Department, VoucherType } from "@/lib/types";

interface ReportKind {
  key: string; icon: string; title: string; title_sw: string; body: string; body_sw: string;
}

interface ReportResult {
  kind: string;
  headings: string[];
  rows: (string | number | null)[][];
  summary: { count: number; total_text: string; approved_total_text: string };
  generated_at: string;
}

/** What this caller is allowed to look back over. */
interface ReportScope { label: string; departments: string[]; locked: boolean }

export default function ReportsPage() {
  const { t, locale, user, reportError, toast } = useApp();
  const [kinds, setKinds] = useState<ReportKind[]>([]);
  const [scope, setScope] = useState<ReportScope | null>(null);
  const [active, setActive] = useState("vouchers");
  const [filters, setFilters] = useState({ from: "", to: "", department_id: "", voucher_type_id: "", status: "", kind: "" });
  const [result, setResult] = useState<ReportResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [types, setTypes] = useState<VoucherType[]>([]);

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

  const load = useCallback(() => {
    setLoading(true); setError(null);
    api.get<ReportResult>(`/reports/${active}`, filters)
      .then(setResult)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [active, filters]);

  useEffect(load, [load, locale]);

  async function exportAs(format: "pdf" | "xlsx" | "csv") {
    /* Phase 1: the report on screen is real, so the spreadsheet is built from
       it here rather than pretending a server produced one. PDF goes through
       the browser's print dialog, which is also how a reader saves one. */
    if (API_MODE === "mock") {
      if (format === "pdf") {
        toast(t("exportBtn"), "Choose “Save as PDF” in the print dialog.", "warn");
        window.setTimeout(() => window.print(), 150);
        return;
      }
      if (!result) return;
      const csv = [result.headings, ...result.rows]
        .map((row) => row.map((cell) => {
          const text = cell === null || cell === undefined ? "" : String(cell);
          return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
        }).join(","))
        .join("\r\n");
      // A BOM keeps Excel honest about UTF-8 (Swahili headings, the − sign).
      const blob = new Blob([`\uFEFF${csv}`], { type: "text/csv;charset=utf-8" });
      saveBlob(blob, `vouchflow-${active}-${new Date().toISOString().slice(0, 10)}.csv`);
      toast(t("exportBtn"), `${result.rows.length} rows · CSV`, "ok");
      return;
    }

    setExporting(format);
    try {
      const blob = await download(`/reports/${active}/export`, { ...filters, format });
      saveBlob(blob, `vouchflow-${active}-${new Date().toISOString().slice(0, 10)}.${format}`);
      toast("Export ready", `${active} report · ${format.toUpperCase()}`, "ok");
    } catch (err) {
      reportError(err, "Could not build the export");
    } finally { setExporting(null); }
  }

  const set = (key: keyof typeof filters) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setFilters((f) => ({ ...f, [key]: e.target.value }));

  const activeKind = kinds.find((k) => k.key === active);
  const isNumeric = (heading: string) =>
    /amount|value|total|turnaround|vouchers|approved|rejected|pending|requests/i.test(heading);

  const sw = locale === "sw";

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
                    <Icon name={scope.locked ? "ph-lock-key" : "ph-eye"} size={13} /> {scope.label}
                  </div>
                )}
              </div>
              <div className="vf-panel-actions">
                <button className="btn btn-secondary btn-sm" onClick={() => exportAs("pdf")} disabled={exporting !== null}>
                  {exporting === "pdf" ? <Spinner /> : <><Icon name="ph-file-pdf" size={14} /> PDF</>}
                </button>
                {API_MODE === "live" && (
                  <button className="btn btn-secondary btn-sm" onClick={() => exportAs("xlsx")} disabled={exporting !== null}>
                    {exporting === "xlsx" ? <Spinner /> : <><Icon name="ph-microsoft-excel-logo" size={14} /> Excel</>}
                  </button>
                )}
                <button className="btn btn-secondary btn-sm" onClick={() => exportAs("csv")} disabled={exporting !== null}>
                  {exporting === "csv" ? <Spinner /> : <><Icon name="ph-file-csv" size={14} /> CSV</>}
                </button>
              </div>
            </div>

            <div className="app-toolbar app-report-filters">
              <div className="app-toolbar-main">
                <label className="app-filter-labelled"><span>{t("from")}</span>
                  <input className="input" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
                </label>
                <label className="app-filter-labelled"><span>{t("to")}</span>
                  <input className="input" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
                </label>
                <label className="app-filter-labelled"><span>{t("department")}</span>
                  <select className="input" value={filters.department_id} onChange={set("department_id")}
                    aria-label={t("department")} disabled={scope?.locked && scope.departments.length <= 1}>
                    <option value="">
                      {scope?.locked && scope.departments.length ? scope.departments.join(" · ") : t("allDepartments")}
                    </option>
                    {departments
                      .filter((d) => !scope?.locked || scope.departments.includes(d.name))
                      .map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </label>
                <label className="app-filter-labelled"><span>{t("voucherKind")}</span>
                  <select className="input" value={filters.kind} onChange={set("kind")} aria-label={t("voucherKind")}>
                    <option value="">{t("all")}</option>
                    <option value="bank">{t("bankVoucher")}</option>
                    <option value="cash">{t("cashVoucher")}</option>
                  </select>
                </label>
                <label className="app-filter-labelled"><span>{t("voucherType")}</span>
                  <select className="input" value={filters.voucher_type_id} onChange={set("voucher_type_id")} aria-label={t("voucherType")}>
                    <option value="">{t("allTypes")}</option>
                    {types.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
                  </select>
                </label>
                <label className="app-filter-labelled"><span>{t("status")}</span>
                  <select className="input" value={filters.status} onChange={set("status")} aria-label={t("status")}>
                    <option value="">{t("allStatuses")}</option>
                    <option value="pending">{t("pending")}</option>
                    <option value="approved">{t("approved")}</option>
                    <option value="rejected">{t("rejected")}</option>
                  </select>
                </label>
              </div>
            </div>

            {result && !error && (
              <div className="app-report-figures">
                <div><span>{t("vouchers")}</span><strong className="tnum">{result.summary.count}</strong></div>
                <div><span>{t("amount")}</span><strong className="tnum">{result.summary.total_text}</strong></div>
                <div><span>{t("approved")}</span><strong className="tnum">{result.summary.approved_total_text}</strong></div>
                <div><span>{sw ? "Imetolewa" : "Generated"}</span><strong className="tnum">{formatDate(result.generated_at, locale)}</strong></div>
              </div>
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
