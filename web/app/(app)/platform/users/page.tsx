"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import type { Paginated, User } from "@/lib/types";

export default function PlatformUsersPage() {
  const { t, locale, toast, reportError } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", role: "", status: "" });
  const [result, setResult] = useState<Paginated<User> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<User>>("/platform/users", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q, locale]);

  async function setStatus(user: User, status: "active" | "suspended") {
    try {
      await api.put(`/platform/users/${user.id}`, { status });
      toast(status === "suspended" ? "User suspended" : "User activated", user.name, status === "suspended" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err); }
  }

  const rows = result?.data ?? [];

  return (
    <div style={{ maxWidth: 1200 }}>
      <PageHeader kicker="Platform" title={t("users")} sub="Every account across all tenants." />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        <input className="input" placeholder={t("search")} value={filters.q}
          onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, q: e.target.value })); }} aria-label={t("search")} />
        <select className="input" value={filters.role} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, role: e.target.value })); }} aria-label={t("role")}>
          <option value="">All roles</option>
          <option value="super_admin">Super Admin</option><option value="company_admin">Administrator</option>
          <option value="hod">HOD</option><option value="ceo">CEO</option><option value="cashier">Cashier</option>
          <option value="finance">Finance</option><option value="employee">Employee</option>
        </select>
        <select className="input" value={filters.status} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, status: e.target.value })); }} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          <option value="active">{t("active")}</option><option value="invited">{t("invited")}</option><option value="suspended">{t("suspended")}</option>
        </select>
      </div>

      {error && <ErrorState message={error} onRetry={load} />}
      {!result && !error && <LoadingBlock rows={6} />}
      {result && rows.length === 0 && <EmptyState icon="ph-users-three" title={t("noResults")} />}

      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>{t("fullName")}</th><th>{t("companyName")}</th><th>{t("role")}</th>
                  <th>{t("status")}</th><th>Last seen</th><th /></tr>
              </thead>
              <tbody>
                {rows.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <span style={{ fontWeight: 500 }}>{user.name}</span>
                      <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{user.email}</span>
                    </td>
                    <td>{user.company_id ? (user as any).company?.name ?? `#${user.company_id}` : "Platform"}</td>
                    <td>{user.role_label}</td>
                    <td>
                      <span className={`tag ${user.status === "active" ? "tag-accent" : user.status === "invited" ? "tag-outline" : "tag-accent-2"}`}>
                        {user.status}
                      </span>
                    </td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDateTime(user.last_login_at, locale)}</td>
                    <td style={{ textAlign: "right" }}>
                      {user.status !== "suspended" ? (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(user, "suspended")} title={t("suspend")} style={{ color: "var(--color-accent-2-700)" }}>
                          <Icon name="ph-prohibit" size={14} />
                        </button>
                      ) : (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(user, "active")} title={t("activate")}>
                          <Icon name="ph-check-circle" size={14} />
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
