"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Quotation, STATUS_LABEL, usePaged } from "@/lib/sales-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { Money, SalesBadge } from "@/components/sales-ui";

const STATUSES = ["draft", "sent", "converted", "rejected", "cancelled"] as const;

export default function QuotationsPage() {
  return <ErpGate module="sales" permission="sales.view"><Quotations /></ErpGate>;
}

function Quotations() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const { rows, error, setPage } = usePaged<Quotation>("/erp/sales/quotations", { status: status || undefined }, q);

  return (
    <div className="erp-page">
      <PageHeader title={t("salQuotations")} subtitle={t("salQuotationsSub")}
        actions={can("sales.quote") && <Link className="btn btn-primary" href="/erp/sales/quotations/new"><Icon name="ph-plus" size={18} /> {t("salNewQuotation")}</Link>} />
      <Toolbar>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchDocs")} />
        <FilterChips value={status} onChange={setStatus} items={[{ value: "", label: t("erpAll") }, ...STATUSES.map((s) => ({ value: s, label: t(STATUS_LABEL[s]) }))]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-note-pencil" title={t("salNoQuotations")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salQuotation")}</th><th>{t("salCustomer")}</th><th>{t("erpDate")}</th><th>{t("salValidUntil")}</th><th className="num">{t("salTotal")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td><Link className="erp-cell-link" href={`/erp/sales/quotations/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span>{r.order && <span className="erp-cell-sub">→ {r.order.number}</span>}</Link></td>
                    <td>{r.customer?.name}</td>
                    <td className="tnum">{formatDate(r.quote_date, locale)}</td>
                    <td className="tnum">{formatDate(r.valid_until, locale)}</td>
                    <td className="num"><Money value={r.total} /></td>
                    <td><SalesBadge status={r.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}
