"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { Receipt, ReceiptStatus } from "@/lib/production-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { QcDialog, ReceiptStatusBadge } from "@/components/production-ui";

type Filter = ReceiptStatus | "all";

export default function QcQueuePage() {
  return <ErpGate module="production" permission="production.view"><QcQueue /></ErpGate>;
}

/** Output waiting for its quality check, oldest first, and the checks already made. */
function QcQueue() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState<Filter>("pending_qc");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Receipt> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [inspecting, setInspecting] = useState<Receipt | null>(null);

  const load = useCallback(() => {
    api.get<Paginated<Receipt>>("/erp/production/qc", { status, q: q || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [status, q, page]);

  useEffect(() => {
    const id = window.setTimeout(load, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [load, q]);

  return (
    <div className="erp-page">
      <PageHeader title={t("prdNavQc")} subtitle={t("prdQcQueueSub")} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("prdSearchReceipts")} />
        <FilterChips<Filter> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "pending_qc", label: t("prdRcptPending") }, { value: "released", label: t("prdRcptReleased") },
          { value: "rejected", label: t("prdRcptRejected") }, { value: "all", label: t("erpAll") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? (
        <EmptyState icon="ph-seal-check" tone={status === "pending_qc" ? "ok" : undefined} title={status === "pending_qc" ? t("prdQcClear") : t("prdNoReceipts")} />
      ) : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prdReceipt")}</th><th>{t("erpProduct")}</th><th>{t("prdBatch")}</th><th className="num">{t("prdGood")}</th><th className="num">{t("prdRejected")}</th><th>{t("prdRecordedBy")}</th><th>{t("prdQc")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.order ? <Link href={`/erp/production/orders/${r.order.id}`}>{r.order.number}</Link> : null} · {formatDate(r.receipt_date, locale)}</span></td>
                    <td>{r.order?.product?.name}<span className="erp-cell-sub">{r.order?.output_warehouse?.name}</span></td>
                    <td className="tnum">{r.batch_number ?? "-"}{r.expiry_date && <span className="erp-cell-sub">{formatDate(r.expiry_date, locale)}</span>}</td>
                    <td className="num">{qty(r.good_quantity)}</td>
                    <td className="num">{qty(Number(r.rejected_quantity) + Number(r.wastage_quantity))}</td>
                    <td>{r.recorder?.name ?? "-"}</td>
                    <td>{r.qc ? <span>{r.qc.inspector?.name ?? "-"}<span className="erp-cell-sub">{formatDateTime(r.qc.checked_at, locale)}</span></span> : "-"}</td>
                    <td>
                      {r.status === "pending_qc" && can("production.qc")
                        ? <button className="btn btn-primary btn-sm" onClick={() => setInspecting(r)}><Icon name="ph-seal-check" size={16} /> {t("prdInspect")}</button>
                        : <ReceiptStatusBadge status={r.status} />}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <QcDialog receipt={inspecting} onClose={() => setInspecting(null)} onDone={() => { setInspecting(null); load(); }} />
    </div>
  );
}
