"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { DOCUMENT_ICON, DOCUMENT_TYPES, type DocumentStatus, type DocumentType, type Paginated, PREPARE_PERMISSION, type StockDocument, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { DOC_HINT, DOC_LABEL, DocStatus, ErpGate, FilterChips } from "@/components/erp-ui";

export default function DocumentsPage() {
  return <ErpGate module="inventory" permission="inventory.view"><Documents /></ErpGate>;
}

function Documents() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [type, setType] = useState<DocumentType | "">("");
  const [status, setStatus] = useState<DocumentStatus | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<StockDocument> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [choosing, setChoosing] = useState(false);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<StockDocument>>("/erp/stock-documents", { type: type || undefined, status: status || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [type, status, q, page]);

  const preparable = DOCUMENT_TYPES.filter((d) => can(PREPARE_PERMISSION[d]));

  return (
    <div className="erp-page">
      <PageHeader title={t("erpDocuments")} subtitle={t("erpDocumentsSub")}
        actions={preparable.length > 0 && (
          <button className="btn btn-primary" onClick={() => setChoosing(true)}><Icon name="ph-plus" size={18} /> {t("erpNewDocument")}</button>
        )} />

      <Toolbar end={
        <select className="input" aria-label={t("erpType")} value={type} onChange={(e) => { setType(e.target.value as DocumentType | ""); setPage(1); }} style={{ maxWidth: 220 }}>
          <option value="">{t("erpAll")}</option>
          {DOCUMENT_TYPES.map((d) => <option key={d} value={d}>{t(DOC_LABEL[d])}</option>)}
        </select>
      }>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("erpReference")}`} />
        <FilterChips<DocumentStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("erpStatusDraft") },
          { value: "posted", label: t("erpStatusPosted") }, { value: "reversed", label: t("erpStatusReversed") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-tray" title={t("erpNoDocuments")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("erpType")}</th><th>{t("erpWarehouse")}</th><th>{t("erpDate")}</th><th className="num">{t("erpLines")}</th><th>{t("erpPrepared")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((d) => (
                  <tr key={d.id} className="is-clickable">
                    <td><Link href={`/erp/documents/${d.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{d.number}</span>{d.reference && <span className="erp-cell-sub">{d.reference}</span>}</Link></td>
                    <td><span className="erp-inline-icon"><Icon name={DOCUMENT_ICON[d.type]} size={16} /> {t(DOC_LABEL[d.type])}</span></td>
                    <td>{d.warehouse?.name}{d.to_warehouse ? ` → ${d.to_warehouse.name}` : ""}{d.supplier ? <span className="erp-cell-sub">{d.supplier.name}</span> : null}</td>
                    <td className="tnum">{formatDate(d.document_date, locale)}</td>
                    <td className="num">{d.lines_count}</td>
                    <td>{d.creator?.name ?? "-"}</td>
                    <td><DocStatus status={d.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <Dialog open={choosing} title={t("erpNewDocument")} onClose={() => setChoosing(false)}>
        <div className="erp-actions">
          {preparable.map((d) => (
            <Link key={d} href={`/erp/documents/new?type=${d}`} className="erp-action">
              <span className="erp-action-icon"><Icon name={DOCUMENT_ICON[d]} size={20} /></span>
              <span className="erp-action-text"><span>{t(DOC_LABEL[d])}</span><span className="erp-muted">{t(DOC_HINT[d])}</span></span>
              <Icon name="ph-caret-right" size={16} style={{ marginLeft: "auto", opacity: .5 }} />
            </Link>
          ))}
        </div>
      </Dialog>
    </div>
  );
}
