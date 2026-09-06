"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { VoucherTable } from "@/components/voucher-bits";
import type { Department, Paginated, Voucher, VoucherType } from "@/lib/types";

const STATUSES = [
  { value: "", key: "allStatuses" },
  { value: "drafts", key: "drafts" },
  { value: "pending", key: "pending" },
  { value: "approved", key: "approved" },
  { value: "rejected", key: "rejected" },
  { value: "changes_requested", key: "requestChanges" },
] as const;

export default function VouchersPage() {
  const { t, user, company, locale } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", status: "", department_id: "", voucher_type_id: "", from: "", to: "" });
  const [result, setResult] = useState<Paginated<Voucher> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [types, setTypes] = useState<VoucherType[]>([]);

  useEffect(() => {
    api.get<{ data: Department[] }>("/departments").then((r) => setDepartments(r.data)).catch(() => undefined);
    api.get<{ data: VoucherType[] }>("/voucher-types").then((r) => setTypes(r.data)).catch(() => undefined);
  }, []);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    api.get<Paginated<Voucher>>("/vouchers", { ...filters, page, per_page: 20 })
      .then(setResult)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q]);

  const set = (key: keyof typeof filters) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setPage(1);
    setFilters((f) => ({ ...f, [key]: e.target.value }));
  };

  const hasFilters = Object.values(filters).some(Boolean);
  const rows = result?.data ?? [];

  return (
    <div style={{ maxWidth: 1200 }}>
      <PageHeader
        kicker={user?.role === "employee" ? t("myVouchers") : t("register")}
        title={user?.role === "employee" ? t("myVouchers") : t("voucherRegister")}
        sub={user?.role === "employee" ? "You see only your own vouchers." : undefined}
        actions={<Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus-circle" size={15} /> {t("createVoucher")}</Link>}
      />

      <div style={{
        display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))",
        gap: "var(--space-2)", marginBottom: "var(--space-4)",
      }}>
        <input className="input" placeholder={t("searchPh")} value={filters.q} onChange={set("q")} aria-label={t("search")} />
        <select className="input" value={filters.status} onChange={set("status")} aria-label={t("status")}>
          {STATUSES.map((s) => <option key={s.value} value={s.value}>{t(s.key as never)}</option>)}
        </select>
        {departments.length > 0 && (
          <select className="input" value={filters.department_id} onChange={set("department_id")} aria-label={t("department")}>
            <option value="">{t("allDepartments")}</option>
            {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </select>
        )}
        <select className="input" value={filters.voucher_type_id} onChange={set("voucher_type_id")} aria-label={t("voucherType")}>
          <option value="">{t("allTypes")}</option>
          {types.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
        </select>
        <input className="input" type="date" value={filters.from} onChange={set("from")} aria-label={t("from")} />
        <input className="input" type="date" value={filters.to} onChange={set("to")} aria-label={t("to")} />
      </div>

      <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-3)", marginBottom: "var(--space-2)", flexWrap: "wrap" }}>
        <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)" }}>
          {t("showing")} {rows.length} {t("of")} {result?.meta?.total ?? 0}
          {result?.meta?.total_amount != null && ` · ${money(result.meta.total_amount, result.meta.currency ?? company?.currency)}`}
        </div>
        <div style={{ flex: 1 }} />
        {hasFilters && (
          <button className="btn btn-ghost btn-sm" onClick={() => { setFilters({ q: "", status: "", department_id: "", voucher_type_id: "", from: "", to: "" }); setPage(1); }}>
            <Icon name="ph-x" size={13} /> {t("clearFilters")}
          </button>
        )}
      </div>

      {error && <ErrorState message={error} onRetry={load} />}
      {loading && !result && <LoadingBlock rows={6} />}

      {!loading && rows.length === 0 && !error && (
        <EmptyState
          title={hasFilters ? t("noResults") : t("noVouchersYet")}
          body={hasFilters ? undefined : t("noVouchersBody")}
          action={hasFilters
            ? <button className="btn btn-secondary" onClick={() => setFilters({ q: "", status: "", department_id: "", voucher_type_id: "", from: "", to: "" })}>{t("clearFilters")}</button>
            : <Link className="btn btn-primary" href="/vouchers/new">{t("createVoucher")}</Link>}
        />
      )}

      {rows.length > 0 && (
        <>
          <VoucherTable vouchers={rows} />
          <Pagination
            page={result?.meta?.current_page ?? 1}
            lastPage={result?.meta?.last_page ?? 1}
            total={result?.meta?.total ?? rows.length}
            onChange={setPage}
          />
        </>
      )}
    </div>
  );
}
