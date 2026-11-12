"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Invoice } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ProcStatus, useMoney, usePaged } from "@/components/procurement-ui";

type Filter = "" | "to_match" | "awaiting_approval" | "posted" | "unpaid" | "cancelled";

export default function InvoicesPage() {
  return <ErpGate module="procurement" permission="procurement.view"><InvoicesLoader /></ErpGate>;
}

function InvoicesLoader() {
  const initial = useQueryValue("status");
  if (initial === undefined) return <LoadingBlock rows={5} />;
  return <Invoices initial={(initial ?? "") as Filter} />;
}

function Invoices({ initial }: { initial: Filter }) {
  const { t, locale } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const [status, setStatus] = useState<Filter>(initial);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const { rows, error } = usePaged<Invoice>("/erp/procurement/invoices", { status: status || undefined, q: q || undefined, page }, !!q);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcInvoices")} subtitle={t("prcInvoicesSub")}
        actions={can("procurement.invoice") && <Link className="btn btn-primary" href="/erp/procurement/invoices/new"><Icon name="ph-plus" size={18} /> {t("prcNewInvoice")}</Link>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("erpSearch")} />
        <FilterChips<Filter> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "to_match", label: t("prcInvoicesToMatch") },
          { value: "awaiting_approval", label: t("prcStAwaitingApproval") }, { value: "posted", label: t("prcStPosted") },
          { value: "unpaid", label: t("prcStUnpaid") }, { value: "cancelled", label: t("prcStCancelled") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-receipt" title={t("prcNoInvoices")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prcSupplierInvoiceNo")}</th><th>{t("erpSupplier")}</th><th>{t("prcOrder")}</th><th>{t("prcDueDate")}</th><th className="num">{t("erpTotal")}</th><th className="num">{t("prcOutstanding")}</th><th>{t("prcMatch")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((i) => (
                  <tr key={i.id} className="is-clickable">
                    <td><Link href={`/erp/procurement/invoices/${i.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{i.supplier_invoice_number}</span><span className="erp-cell-sub tnum">{i.number}</span></Link></td>
                    <td>{i.supplier?.name}</td>
                    <td className="tnum">{i.order?.number}</td>
                    <td className="tnum">{formatDate(i.due_date, locale)}</td>
                    <td className="num">{money(i.total)}</td>
                    <td className="num">{i.status === "posted" ? money(i.outstanding) : "-"}</td>
                    <td><ProcStatus status={i.match_status} /></td>
                    <td><ProcStatus status={i.status === "posted" ? i.payment_status : i.status} /></td>
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
