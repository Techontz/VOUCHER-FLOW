"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { CreditNote } from "@/lib/sales-api";
import { ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type Act, ActionDialog, Facts, Money, SalesBadge, TotalsBlock } from "@/components/sales-ui";

export default function CreditNotePage() {
  return <ErpGate module="sales" permission="sales.view"><CreditNoteDetail /></ErpGate>;
}

function CreditNoteDetail() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const { id } = useParams<{ id: string }>();
  const [note, setNote] = useState<CreditNote | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);

  const load = useCallback(() => {
    api.get<{ data: CreditNote }>(`/erp/sales/credit-notes/${id}`).then((r) => setNote(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!note) return <LoadingBlock rows={5} />;
  const path = `/erp/sales/credit-notes/${note.id}`;

  return (
    <div className="erp-page">
      <PageHeader back={<Link href="/erp/sales/returns" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salReturns")}</Link>}
        kicker={note.return_to_stock ? t("salReturn") : t("salCreditNote")} title={<span className="tnum">{note.number}</span>}
        subtitle={<>{note.customer?.name} · {formatDate(note.credit_date, locale)}</>}
        actions={<>
          <SalesBadge status={note.status} />
          {note.status === "draft" && can("sales.return") && <button className="btn btn-secondary" onClick={() => setAct({ key: "cancel", path: `${path}/cancel`, label: t("salCancelDoc"), icon: "ph-x-circle", tone: "warn", title: t("salCancelDoc") })}>{t("salCancelDoc")}</button>}
          {note.status === "draft" && can("sales.return") && <button className="btn btn-primary" onClick={() => setAct({ key: "post", path: `${path}/post`, label: t("erpPost"), icon: "ph-check-circle", title: fill(t("erpPostQ"), { number: note.number }), sub: note.return_to_stock ? t("salPostReturnSub") : t("salPostCreditSub") })}><Icon name="ph-check-circle" size={18} /> {t("erpPost")}</button>}
        </>} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("salUnitPrice")}</th><th className="num">{t("salVatPct")}</th><th className="num">{t("salLineTotal")}</th>{note.return_to_stock && <th>{t("erpBatch")}</th>}</tr></thead>
              <tbody>
                {note.lines?.map((l) => (
                  <tr key={l.id}>
                    <td>{l.product?.name}<span className="erp-cell-sub tnum">{l.product?.sku}</span></td>
                    <td className="num">{qty(l.quantity)}</td>
                    <td className="num"><Money value={l.unit_price} /></td>
                    <td className="num">{Number(l.tax_rate)}%</td>
                    <td className="num"><Money value={l.line_total} /></td>
                    {note.return_to_stock && <td className="tnum">{l.batch_number ?? "-"}{l.expiry_date ? ` · ${formatDate(l.expiry_date, locale)}` : ""}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>
        <GlassCard title={t("salSummary")}>
          <TotalsBlock totals={note} />
          <Facts rows={[
            [t("salInvoice"), note.invoice && <Link href={`/erp/sales/invoices/${note.invoice.id}`} className="tnum">{note.invoice.number}</Link>],
            [t("erpReason"), note.reason],
            [t("salReturnTo"), note.return_to_stock ? note.warehouse?.name : null],
            [t("salStockDocument"), note.stock_document && <Link href={`/erp/documents/${note.stock_document.id}`} className="tnum">{note.stock_document.number}</Link>],
            [t("erpPrepared"), note.creator?.name],
            [t("erpPostedBy"), note.posted_at ? `${note.poster?.name ?? "-"} · ${formatDateTime(note.posted_at, locale)}` : null],
          ]} />
        </GlassCard>
      </div>
      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} />
    </div>
  );
}
