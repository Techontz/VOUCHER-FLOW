"use client";

import { useCallback, useEffect, useState } from "react";
import { api, API_MODE, download, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
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

export default function ReportsPage() {
  const { t, locale, reportError, toast } = useApp();
  const [kinds, setKinds] = useState<ReportKind[]>([]);
  const [active, setActive] = useState("vouchers");
  const [filters, setFilters] = useState({ from: "", to: "", department_id: "", voucher_type_id: "", status: "" });
  const [result, setResult] = useState<ReportResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [types, setTypes] = useState<VoucherType[]>([]);

  useEffect(() => {
    api.get<{ data: ReportKind[] }>("/reports").then((r) => setKinds(r.data)).catch(() => undefined);
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

  return (
    <div style={{ maxWidth: 1300 }}>
      <PageHeader kicker={t("reports")} title={locale === "sw" ? activeKind?.title_sw ?? t("reports") : activeKind?.title ?? t("reports")}
        sub={t("filterExport")}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => exportAs("pdf")} disabled={exporting !== null}>
              {exporting === "pdf" ? <Spinner /> : <><Icon name="ph-file-pdf" size={15} /> PDF</>}
            </button>
            {API_MODE === "live" && (
              <button className="btn btn-secondary" onClick={() => exportAs("xlsx")} disabled={exporting !== null}>
                {exporting === "xlsx" ? <Spinner /> : <><Icon name="ph-microsoft-excel-logo" size={15} /> Excel</>}
              </button>
            )}
            <button className="btn btn-secondary" onClick={() => exportAs("csv")} disabled={exporting !== null}>
              {exporting === "csv" ? <Spinner /> : <><Icon name="ph-file-csv" size={15} /> CSV</>}
            </button>
          </>
        } />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))", gap: "var(--space-3)", marginBottom: "var(--space-6)" }}>
        {kinds.map((kind) => {
          const on = kind.key === active;
          return (
            <button key={kind.key} onClick={() => setActive(kind.key)} aria-pressed={on}
              style={{
                textAlign: "left", cursor: "pointer", fontFamily: "var(--font-body)",
                border: `1px solid ${on ? "var(--color-accent-500)" : "var(--vf-line)"}`,
                background: on ? "color-mix(in srgb, var(--color-accent-500) 9%, var(--vf-elev-1))" : "var(--vf-elev-1)",
                color: "var(--color-text)", borderRadius: 14, padding: "var(--space-4)",
                transition: "border-color .18s ease, background .18s ease",
              }}>
              <Icon name={kind.icon} size={22} color="var(--color-accent-600)" />
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 16, marginTop: 6 }}>
                {locale === "sw" ? kind.title_sw : kind.title}
              </div>
              <div style={{ fontSize: 13, color: "var(--color-neutral-700)" }}>
                {locale === "sw" ? kind.body_sw : kind.body}
              </div>
            </button>
          );
        })}
      </div>

      <div className="vf-panel" style={{ padding: "var(--space-4)", marginBottom: "var(--space-4)",
        display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-2)" }}>
        <input className="input" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
        <input className="input" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
        <select className="input" value={filters.department_id} onChange={set("department_id")} aria-label={t("department")}>
          <option value="">{t("allDepartments")}</option>
          {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="input" value={filters.voucher_type_id} onChange={set("voucher_type_id")} aria-label={t("voucherType")}>
          <option value="">{t("allTypes")}</option>
          {types.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
        </select>
        <select className="input" value={filters.status} onChange={set("status")} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          <option value="pending">{t("pending")}</option>
          <option value="approved">{t("approved")}</option>
          <option value="rejected">{t("rejected")}</option>
        </select>
      </div>

      {error && <ErrorState message={error} onRetry={load} />}
      {loading && <LoadingBlock rows={6} />}

      {!loading && result && (
        <>
          <div style={{ display: "flex", gap: "var(--space-6)", flexWrap: "wrap", marginBottom: "var(--space-3)", fontSize: 14.5 }}>
            <span><strong>{result.summary.count}</strong> {t("vouchers")}</span>
            <span>{t("amount")}: <strong>{result.summary.total_text}</strong></span>
            <span>{t("approved")}: <strong>{result.summary.approved_total_text}</strong></span>
          </div>

          {result.rows.length === 0 ? (
            <EmptyState icon="ph-chart-line" title={t("noResults")} />
          ) : (
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>{result.headings.map((h) => (
                    <th key={h} style={{ textAlign: isNumeric(h) ? "right" : "left" }}>{h}</th>
                  ))}</tr>
                </thead>
                <tbody>
                  {result.rows.map((row, i) => (
                    <tr key={i}>
                      {row.map((cell, j) => (
                        <td key={j} style={{
                          textAlign: isNumeric(result.headings[j]) ? "right" : "left",
                          fontVariantNumeric: typeof cell === "number" ? "tabular-nums" : undefined,
                          whiteSpace: typeof cell === "number" ? "nowrap" : undefined,
                        }}>
                          {typeof cell === "number" ? cell.toLocaleString("en-US", { maximumFractionDigits: 2 }) : cell ?? "—"}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}
