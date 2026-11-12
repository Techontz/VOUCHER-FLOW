"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { type Invoice, usePaged } from "@/lib/sales-api";
import { EmptyState, ErrorState, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { Money, SalesBadge } from "@/components/sales-ui";

type Filter = "" | "draft" | "open" | "overdue" | "posted" | "cancelled";

export default function InvoicesPage() {
  return <ErpGate module="sales" permission="sales.view"><Invoices /></ErpGate>;
}

function Invoices() {
  const { t, locale } = useApp();
  const [filter, setFilter] = useState<Filter>("");
  const [q, setQ] = useState("");
  const query = filter === "open" ? { open_only: 1 } : filter === "overdue" ? { overdue: 1 } : { status: filter || undefined };
  const { rows, error, setPage } = usePaged<Invoice>("/erp/sales/invoices", query, q);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <div className="erp-page">
      <PageHeader title={t("salInvoices")} subtitle={t("salInvoicesSub")} />
      <Toolbar>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchDocs")} />
        <FilterChips<Filter> value={filter} onChange={setFilter} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("salStDraft") }, { value: "open", label: t("salUnpaid") },
          { value: "overdue", label: t("salOverdue") }, { value: "posted", label: t("salStPosted") }, { value: "cancelled", label: t("salStCancelled") },
        ]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-receipt" title={t("salNoInvoices")} body={t("salNoInvoicesBody")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salInvoice")}</th><th>{t("salCustomer")}</th><th>{t("erpDate")}</th><th>{t("salDue")}</th><th className="num">{t("salTotal")}</th><th className="num">{t("salBalance")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => {
                  const late = r.status === "posted" && r.balance > 0 && r.due_date.slice(0, 10) < today;
                  return (
                    <tr key={r.id}>
                      <td><Link className="erp-cell-link" href={`/erp/sales/invoices/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span>{r.order && <span className="erp-cell-sub">{r.order.number}</span>}</Link></td>
                      <td>{r.customer?.name}</td>
                      <td className="tnum">{formatDate(r.invoice_date, locale)}</td>
                      <td className="tnum" style={late ? { color: "var(--st-bad-fg)" } : undefined}>{formatDate(r.due_date, locale)}</td>
                      <td className="num"><Money value={r.total} /></td>
                      <td className="num"><Money value={r.balance} /></td>
                      <td><SalesBadge status={r.status} /></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}
