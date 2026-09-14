"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { EmptyState, ErrorState, LoadingBlock, Pagination } from "@/components/ui";
import { SearchInput, SettingsLayout } from "@/components/app-ui";
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
    <SettingsLayout title={t("auditLogs")} sub="Who did what, when and from which device. Entries are append-only.">
      <section className="vf-panel">
        <div className="app-toolbar">
          <div className="app-toolbar-main">
            <SearchInput value={filters.q} onChange={(q) => { setPage(1); setFilters((f) => ({ ...f, q })); }} placeholder={t("search")} />
            <select className="input" value={filters.action} onChange={set("action")} aria-label={t("actions")}>
              <option value="">{t("allActions")}</option>
              {actions.map((a) => <option key={a} value={a}>{a}</option>)}
            </select>
            <input className="input app-date" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
            <input className="input app-date" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
          </div>
          {result?.meta?.total != null && <div className="app-toolbar-end"><span className="app-result-count tnum">{result.meta.total}</span></div>}
        </div>

        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
        {result && rows.length === 0 && <EmptyState icon="ph-scroll" title={t("noResults")} />}

        {rows.length > 0 && (
          <>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr><th>{t("people")}</th><th>{t("actions")}</th><th>Change</th><th>{t("date")}</th><th>Device</th></tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <div className="app-person">
                          <span className="app-avatar" aria-hidden="true">{row.actor.initials}</span>
                          <span className="app-person-text">
                            <strong>{row.actor.name}</strong>
                            {row.company && <span>{row.company}</span>}
                          </span>
                        </div>
                      </td>
                      <td style={{ minWidth: 220 }}>{row.description}</td>
                      <td className="app-cell-sub" style={{ fontSize: 13 }}>{row.change_summary ?? "—"}</td>
                      <td className="tnum" style={{ whiteSpace: "nowrap" }}>{formatDateTime(row.created_at, locale)}</td>
                      <td className="app-cell-sub" style={{ maxWidth: 220 }}>
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
      </section>
    </SettingsLayout>
  );
}
