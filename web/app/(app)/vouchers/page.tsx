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
  { value: "approved", key: "awaitingPayment" },
  { value: "paid", key: "paidAct" },
  { value: "rejected", key: "rejected" },
  { value: "changes_requested", key: "requestChanges" },
] as const;

const BLANK = { q: "", status: "", kind: "", department_id: "", voucher_type_id: "", from: "", to: "" };

export default function VouchersPage() {
  const { t, user, company, locale } = useApp();
  // Six stacked controls swallow a phone screen; fold them away by default
  // there and leave them open on a desktop, where they cost one row.
  const [showFilters, setShowFilters] = useState(true);
  useEffect(() => {
    setShowFilters(window.matchMedia("(min-width: 981px)").matches);
  }, []);
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ ...BLANK });
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
  const isEmployee = user?.role === "employee";
  const activeFilters = [filters.kind, filters.department_id, filters.voucher_type_id, filters.from, filters.to].filter(Boolean).length;

  return (
    <div className="app-page">
      <PageHeader
        title={isEmployee ? t("myVouchers") : t("voucherRegister")}
        sub={isEmployee ? "You see only your own vouchers." : undefined}
        actions={user?.role !== "cashier" && user?.role !== "super_admin"
          ? <Link className="btn btn-primary" href="/vouchers/new"><Icon name="ph-plus" size={15} /> {t("createVoucher")}</Link>
          : undefined}
      />

      <div className="app-tabs" role="tablist" aria-label={t("status")}>
        {STATUSES.map((s) => (
          <button key={s.value} type="button" role="tab" aria-selected={filters.status === s.value}
            onClick={() => { setPage(1); setFilters((f) => ({ ...f, status: s.value })); }}>
            {s.value === "" ? t("all") : t(s.key as never)}
            {filters.status === s.value && result?.meta?.total != null && <span className="app-tabs-count">{result.meta.total}</span>}
          </button>
        ))}
      </div>

      <section className="vf-panel app-register">
        <div className="app-toolbar">
          <div className="app-toolbar-main">
            <label className="app-search">
              <Icon name="ph-magnifying-glass" size={15} />
              <input className="input" placeholder={t("searchPh")} value={filters.q} onChange={set("q")} aria-label={t("search")} />
            </label>
            <button type="button" className="btn btn-secondary btn-sm vf-filter-toggle" aria-expanded={showFilters} onClick={() => setShowFilters((v) => !v)}>
              <Icon name="ph-sliders-horizontal" size={14} /> {t("filters")}{activeFilters ? ` · ${activeFilters}` : ""}
            </button>
            <div className="app-filters" hidden={!showFilters}>
              <FilterField label={t("voucherKind")} htmlFor="f-kind">
                <select id="f-kind" className="input" value={filters.kind} onChange={set("kind")}>
                  <option value="">{t("all")}</option>
                  <option value="bank">{t("bankVoucher")}</option>
                  <option value="cash">{t("cashVoucher")}</option>
                </select>
              </FilterField>
              {departments.length > 0 && (
                <FilterField label={t("department")} htmlFor="f-dept">
                  <select id="f-dept" className="input" value={filters.department_id} onChange={set("department_id")}>
                    <option value="">{t("allDepartments")}</option>
                    {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </FilterField>
              )}
              <FilterField label={t("voucherType")} htmlFor="f-type">
                <select id="f-type" className="input" value={filters.voucher_type_id} onChange={set("voucher_type_id")}>
                  <option value="">{t("allTypes")}</option>
                  {types.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
                </select>
              </FilterField>
              <FilterField label={t("from")} htmlFor="f-from">
                <input id="f-from" className="input" type="date" value={filters.from} onChange={set("from")} />
              </FilterField>
              <FilterField label={t("to")} htmlFor="f-to">
                <input id="f-to" className="input" type="date" value={filters.to} onChange={set("to")} />
              </FilterField>
            </div>
          </div>
          <div className="app-toolbar-end">
            <span className="app-result-count tnum">
              {t("showing")} {rows.length} {t("of")} {result?.meta?.total ?? 0}
              {result?.meta?.total_amount != null && <> · <strong>{money(result.meta.total_amount, result.meta.currency ?? company?.currency)}</strong></>}
            </span>
            {hasFilters && (
              <button className="btn btn-ghost btn-sm" onClick={() => { setFilters({ ...BLANK }); setPage(1); }}>
                <Icon name="ph-x" size={13} /> {t("clearFilters")}
              </button>
            )}
          </div>
        </div>

        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {loading && !result && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}

        {!loading && rows.length === 0 && !error && (
          <EmptyState
            title={hasFilters ? t("noResults") : t("noVouchersYet")}
            body={hasFilters ? undefined : t("noVouchersBody")}
            action={hasFilters
              ? <button className="btn btn-secondary" onClick={() => setFilters({ ...BLANK })}>{t("clearFilters")}</button>
              : <Link className="btn btn-primary" href="/vouchers/new">{t("createVoucher")}</Link>}
          />
        )}

        {rows.length > 0 && (
          <div data-loading={loading || undefined} className="app-register-body">
            <VoucherTable vouchers={rows} bare />
            <Pagination
              page={result?.meta?.current_page ?? 1}
              lastPage={result?.meta?.last_page ?? 1}
              total={result?.meta?.total ?? rows.length}
              onChange={setPage}
            />
          </div>
        )}
      </section>
    </div>
  );
}

/** A labelled filter control — the bare selects read as unlabelled otherwise. */
function FilterField({ label, htmlFor, children }: { label: string; htmlFor: string; children: React.ReactNode }) {
  return (
    <div className="app-filter">
      <label htmlFor={htmlFor} className="sr-only">{label}</label>
      {children}
    </div>
  );
}
