"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, money } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination, StatBlock, StatGrid } from "@/components/ui";
import type { Invoice, Paginated } from "@/lib/types";

export default function PlatformPaymentsPage() {
  const { t, locale, toast, reportError } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", status: "", method: "" });
  const [result, setResult] = useState<Paginated<Invoice> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<Invoice>>("/platform/payments", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q, locale]);

  async function act(invoice: Invoice, action: "refund" | "mark-paid") {
    try {
      await api.post(`/platform/payments/${invoice.id}/${action}`, action === "mark-paid" ? { reference: "manual" } : {});
      toast(action === "refund" ? "Refunded" : "Marked paid", invoice.number, action === "refund" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err, "Could not update the invoice"); }
  }

  const rows = result?.data ?? [];

  return (
    <div className="app-page">
      <PageHeader kicker="Platform" title={t("payments")} sub="Every invoice raised across all tenants." />

      <div style={{ marginBottom: "var(--space-6)" }}>
        <StatGrid>
          <StatBlock label="Collected" value={money(result?.meta?.collected ?? 0, "TZS")} sub="all time, paid" />
          <StatBlock label="Outstanding" value={money(result?.meta?.outstanding ?? 0, "TZS")} sub="pending or failed" />
          <StatBlock label="Invoices" value={String(result?.meta?.total ?? 0)} sub="matching these filters" />
        </StatGrid>
      </div>

      <section className="vf-panel">
      <div className="app-toolbar">
        <div className="app-toolbar-main">
        <input className="input app-toolbar-search" placeholder={t("search")} value={filters.q}
          onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, q: e.target.value })); }} aria-label={t("search")} />
        <select className="input" value={filters.status} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, status: e.target.value })); }} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          <option value="paid">Paid</option><option value="pending">Pending</option>
          <option value="failed">Failed</option><option value="refunded">Refunded</option>
        </select>
        <select className="input" value={filters.method} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, method: e.target.value })); }} aria-label={t("method")}>
          <option value="">All methods</option>
          <option value="mobile_money">Mobile Money</option><option value="card">Card</option><option value="bank_transfer">Bank transfer</option>
        </select>
        </div>
      </div>

      {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
      {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
      {result && rows.length === 0 && <EmptyState icon="ph-credit-card" title={t("noResults")} />}

      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>{t("invoice")}</th><th>{t("companyName")}</th><th>{t("plan")}</th>
                  <th style={{ textAlign: "right" }}>{t("amount")}</th><th>{t("method")}</th>
                  <th>{t("status")}</th><th>{t("date")}</th><th /></tr>
              </thead>
              <tbody>
                {rows.map((invoice) => (
                  <tr key={invoice.id}>
                    <td style={{ fontVariantNumeric: "tabular-nums" }}>{invoice.number}</td>
                    <td>{invoice.company}</td>
                    <td style={{ color: "var(--color-neutral-700)" }}>{invoice.description}</td>
                    <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{invoice.amount_text}</td>
                    <td>{invoice.method_label}</td>
                    <td><span className={`badge ${invoice.status_tag}`}>{invoice.status}</span></td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDate(invoice.paid_at ?? invoice.issued_at, locale)}</td>
                    <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                      {invoice.status === "paid" && (
                        <button className="btn btn-ghost btn-sm" onClick={() => act(invoice, "refund")} title="Refund" style={{ color: "var(--color-accent-2-700)" }}>
                          <Icon name="ph-arrow-counter-clockwise" size={14} />
                        </button>
                      )}
                      {(invoice.status === "pending" || invoice.status === "failed") && (
                        <button className="btn btn-ghost btn-sm" onClick={() => act(invoice, "mark-paid")} title="Mark paid">
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
      </section>
    </div>
  );
}
