"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import type { Company, Paginated } from "@/lib/types";

const STATUS_TAG: Record<string, string> = {
  active: "tag-accent", trial: "tag-outline", past_due: "tag-accent-2",
  suspended: "tag-accent-2", cancelled: "tag-neutral",
};

export default function PlatformCompaniesPage() {
  const { t, locale, toast, reportError } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", status: "" });
  const [result, setResult] = useState<Paginated<Company> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<Company>>("/platform/companies", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q, locale]);

  async function setStatus(company: Company, action: "suspend" | "activate") {
    try {
      await api.post(`/platform/companies/${company.id}/${action}`);
      toast(action === "suspend" ? "Company suspended" : "Company activated", company.name, action === "suspend" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err, "Could not update the company"); }
  }

  const rows = result?.data ?? [];

  return (
    <div style={{ maxWidth: 1300 }}>
      <PageHeader kicker="Platform" title={t("companies")}
        sub="Every tenant on the platform. Data stays sealed inside each company." />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        <input className="input" placeholder={t("search")} value={filters.q}
          onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, q: e.target.value })); }} aria-label={t("search")} />
        <select className="input" value={filters.status}
          onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, status: e.target.value })); }} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          <option value="active">Active</option><option value="trial">Trial</option>
          <option value="past_due">Past due</option><option value="suspended">Suspended</option>
        </select>
      </div>

      {error && <ErrorState message={error} onRetry={load} />}
      {!result && !error && <LoadingBlock rows={6} />}
      {result && rows.length === 0 && <EmptyState icon="ph-buildings" title={t("noResults")} />}

      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>{t("companyName")}</th><th>{t("plan")}</th><th style={{ textAlign: "right" }}>{t("users")}</th>
                  <th style={{ textAlign: "right" }}>{t("vouchers")}</th><th>{t("status")}</th><th>Renews</th><th>{t("joined")}</th><th /></tr>
              </thead>
              <tbody>
                {rows.map((company) => (
                  <tr key={company.id}>
                    <td>
                      <Link href={`/platform/companies/${company.id}`} style={{ fontWeight: 500 }}>{company.name}</Link>
                      <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)" }}>{company.email}</div>
                    </td>
                    <td>{company.plan?.name ?? "—"}</td>
                    <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{company.users_count ?? 0}</td>
                    <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{company.vouchers_count ?? 0}</td>
                    <td><span className={`tag ${STATUS_TAG[company.status] ?? "tag-neutral"}`}>{company.status}</span></td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>
                      {formatDate(company.status === "trial" ? company.trial_ends_at : company.current_period_end, locale)}
                    </td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDate(company.created_at, locale)}</td>
                    <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                      {company.status === "suspended" ? (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(company, "activate")} title={t("activate")}>
                          <Icon name="ph-check-circle" size={14} />
                        </button>
                      ) : (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(company, "suspend")} title={t("suspend")} style={{ color: "var(--color-accent-2-700)" }}>
                          <Icon name="ph-prohibit" size={14} />
                        </button>
                      )}
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
