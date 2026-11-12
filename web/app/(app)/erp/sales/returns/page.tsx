"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { type CreditNote, usePaged } from "@/lib/sales-api";
import { Badge, EmptyState, ErrorState, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { Money, SalesBadge } from "@/components/sales-ui";

export default function ReturnsPage() {
  return <ErpGate module="sales" permission="sales.view"><Returns /></ErpGate>;
}

function Returns() {
  const { t, locale } = useApp();
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const { rows, error, setPage } = usePaged<CreditNote>("/erp/sales/credit-notes", { status: status || undefined }, q);

  return (
    <div className="erp-page">
      <PageHeader title={t("salReturns")} subtitle={t("salReturnsSub")} />
      <Toolbar>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchDocs")} />
        <FilterChips value={status} onChange={setStatus} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("salStDraft") }, { value: "posted", label: t("salStPosted") }, { value: "cancelled", label: t("salStCancelled") },
        ]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-arrow-u-up-left" title={t("salNoCreditNotes")} body={t("salNoCreditNotesBody")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salCreditNote")}</th><th>{t("salCustomer")}</th><th>{t("salInvoice")}</th><th>{t("erpDate")}</th><th>{t("erpReason")}</th><th className="num">{t("salTotal")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td><Link className="erp-cell-link" href={`/erp/sales/returns/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span>{r.return_to_stock && <Badge tone="info">{t("salGoodsReturned")}</Badge>}</Link></td>
                    <td>{r.customer?.name}</td>
                    <td className="tnum">{r.invoice?.number}</td>
                    <td className="tnum">{formatDate(r.credit_date, locale)}</td>
                    <td>{r.reason}</td>
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
