"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { EmptyState, ErrorState, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import type { AuditEntry, Paginated } from "@/lib/types";

export default function AuditPage() {
  const { t, locale } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", action: "", from: "", to: "" });
  const [result, setResult] = useState<Paginated<AuditEntry> | null>(null);
  const [actions, setActions] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: string[] }>("/audit-logs/actions").then((r) => setActions(r.data)).catch(() => undefined);
  }, []);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<AuditEntry>>("/audit-logs", { ...filters, page, per_page: 30 })
      .then(setResult)
      .catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q]);

  const set = (key: keyof typeof filters) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setPage(1);
    setFilters((f) => ({ ...f, [key]: e.target.value }));
  };

  const rows = result?.data ?? [];

  return (
    <div style={{ maxWidth: 1200 }}>
      <PageHeader kicker={t("onRecord")} title={t("auditLogs")}
        sub="Who did what, when and from which device. Entries are append-only." />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        <input className="input" placeholder={t("search")} value={filters.q} onChange={set("q")} aria-label={t("search")} />
        <select className="input" value={filters.action} onChange={set("action")} aria-label={t("actions")}>
          <option value="">{t("allActions")}</option>
          {actions.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
        <input className="input" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
        <input className="input" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
      </div>

      {error && <ErrorState message={error} onRetry={load} />}
      {!result && !error && <LoadingBlock rows={6} />}

      {result && rows.length === 0 && <EmptyState icon="ph-scroll" title={t("noResults")} />}

      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("people")}</th><th>{t("actions")}</th><th>Change</th><th>{t("date")}</th><th>Device</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <span style={{ width: 26, height: 26, borderRadius: "50%", background: "var(--color-accent-200)", color: "var(--color-accent-800)", display: "grid", placeItems: "center", fontSize: 11, fontWeight: 600, flex: "none" }}>
                          {row.actor.initials}
                        </span>
                        <span>
                          <span style={{ display: "block" }}>{row.actor.name}</span>
                          {row.company && <span style={{ display: "block", fontSize: 12, color: "var(--color-neutral-600)" }}>{row.company}</span>}
                        </span>
                      </div>
                    </td>
                    <td style={{ minWidth: 220 }}>{row.description}</td>
                    <td style={{ color: "var(--color-neutral-700)", fontSize: 13 }}>{row.change_summary ?? "—"}</td>
                    <td style={{ whiteSpace: "nowrap" }}>{formatDateTime(row.created_at, locale)}</td>
                    <td style={{ fontSize: 12.5, color: "var(--color-neutral-600)", maxWidth: 220 }}>
                      {row.ip}{row.user_agent ? ` · ${row.user_agent.slice(0, 40)}` : ""}
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
    </div>
  );
}
