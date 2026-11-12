"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Requisition, RequisitionStatus } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ProcStatus, useMoney, usePaged } from "@/components/procurement-ui";

export default function RequisitionsPage() {
  return <ErpGate module="procurement" permission="procurement.view"><Requisitions /></ErpGate>;
}

function Requisitions() {
  const initial = useQueryValue("status");
  if (initial === undefined) return <LoadingBlock rows={5} />;
  return <RequisitionList initial={(initial ?? "") as RequisitionStatus | ""} />;
}

function RequisitionList({ initial }: { initial: RequisitionStatus | "" }) {
  const { t, locale } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const [status, setStatus] = useState<RequisitionStatus | "">(initial);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const { rows, error } = usePaged<Requisition>("/erp/procurement/requisitions", { status: status || undefined, q: q || undefined, page }, !!q);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcRequisitions")} subtitle={t("prcRequisitionsSub")}
        actions={can("procurement.request") && <Link className="btn btn-primary" href="/erp/procurement/requisitions/new"><Icon name="ph-plus" size={18} /> {t("prcNewRequisition")}</Link>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("erpSearch")} />
        <FilterChips<RequisitionStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("prcStDraft") }, { value: "submitted", label: t("prcStSubmitted") },
          { value: "approved", label: t("prcStApproved") }, { value: "ordered", label: t("prcStOrdered") }, { value: "rejected", label: t("prcStRejected") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-clipboard-text" title={t("prcNoRequisitions")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("prcDepartment")}</th><th>{t("prcRequester")}</th><th>{t("prcNeededBy")}</th><th className="num">{t("prcEstimate")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className="is-clickable">
                    <td><Link href={`/erp/procurement/requisitions/${r.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.justification}</span></Link></td>
                    <td>{r.department?.name ?? "-"}</td>
                    <td>{r.requester?.name ?? "-"}</td>
                    <td className="tnum">{r.needed_by ? formatDate(r.needed_by, locale) : "-"}</td>
                    <td className="num">{money(r.total)}</td>
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
