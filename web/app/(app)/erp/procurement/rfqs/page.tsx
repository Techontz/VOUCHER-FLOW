"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Rfq, RfqStatus } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ProcStatus, usePaged } from "@/components/procurement-ui";

export default function RfqsPage() {
  return <ErpGate module="procurement" permission="procurement.view"><Rfqs /></ErpGate>;
}

function Rfqs() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState<RfqStatus | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const { rows, error } = usePaged<Rfq>("/erp/procurement/rfqs", { status: status || undefined, q: q || undefined, page }, !!q);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcRfqs")} subtitle={t("prcRfqsSub")}
        actions={can("procurement.quote") && <Link className="btn btn-primary" href="/erp/procurement/rfqs/new"><Icon name="ph-plus" size={18} /> {t("prcNewRfq")}</Link>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("erpSearch")} />
        <FilterChips<RfqStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("prcStDraft") }, { value: "sent", label: t("prcStSent") },
          { value: "awarded", label: t("prcStAwarded") }, { value: "cancelled", label: t("prcStCancelled") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-paper-plane-tilt" title={t("prcNoRfqs")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("prcRequisition")}</th><th>{t("prcClosingDate")}</th><th className="num">{t("prcQuotes")}</th><th>{t("prcWinner")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className="is-clickable">
                    <td><Link href={`/erp/procurement/rfqs/${r.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.title}</span></Link></td>
                    <td className="tnum">{r.requisition?.number ?? "-"}</td>
                    <td className="tnum">{r.closing_date ? formatDate(r.closing_date, locale) : "-"}</td>
                    <td className="num">{r.quotations_count ?? 0} / {r.suppliers_count ?? 0}</td>
                    <td>{r.selected_quotation?.supplier?.name ?? "-"}</td>
                    <td><ProcStatus status={r.status} /></td>
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
