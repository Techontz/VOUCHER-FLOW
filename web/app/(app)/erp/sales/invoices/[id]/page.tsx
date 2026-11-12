"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Invoice } from "@/lib/sales-api";
import { ErrorState, Icon, LoadingBlock } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type Act, ActionDialog, Money, SalesBadge, TotalsBlock } from "@/components/sales-ui";

export default function InvoicePage() {
  return <ErpGate module="sales" permission="sales.view"><InvoiceDetail /></ErpGate>;
}

/** The invoice as the customer receives it: a clean sheet that prints from the browser. */
function InvoiceDetail() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const { id } = useParams<{ id: string }>();
  const [inv, setInv] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Invoice }>(`/erp/sales/invoices/${id}`).then((r) => setInv(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!inv) return <LoadingBlock rows={6} />;

  const path = `/erp/sales/invoices/${inv.id}`;
  const c = inv.customer;

  return (
    <div className="erp-page">
      <div className="sal-noprint sal-doc-bar">
        <Link href="/erp/sales/invoices" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salInvoices")}</Link>
        <span className="sal-doc-actions">
          <SalesBadge status={inv.status} />
          {inv.status === "draft" && can("sales.invoice") && <button className="btn btn-secondary" onClick={() => setAct({ key: "cancel", path: `${path}/cancel`, label: t("salCancelDoc"), icon: "ph-x-circle", tone: "warn", title: t("salCancelDoc") })}>{t("salCancelDoc")}</button>}
          {inv.status === "draft" && can("sales.invoice") && <button className="btn btn-primary" onClick={() => setAct({ key: "post", path: `${path}/post`, label: t("erpPost"), icon: "ph-check-circle", title: fill(t("erpPostQ"), { number: inv.number }), sub: t("salPostInvoiceSub") })}><Icon name="ph-check-circle" size={18} /> {t("erpPost")}</button>}
          {inv.status === "posted" && inv.balance > 0 && can("sales.receipt") && <Link className="btn btn-primary" href={`/erp/sales/receipts/new?invoice=${inv.id}`}><Icon name="ph-hand-coins" size={18} /> {t("salRecordReceipt")}</Link>}
          {inv.status === "posted" && can("sales.return") && <Link className="btn btn-secondary" href={`/erp/sales/returns/new?invoice=${inv.id}`}><Icon name="ph-arrow-u-up-left" size={17} /> {t("salCreditNote")}</Link>}
          <button className="btn btn-secondary" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("salPrint")}</button>
        </span>
      </div>

      <article className="sal-sheet">
        <header className="sal-sheet-head">
          <div>
            <div className="sal-sheet-seller">{inv.seller?.name}</div>
            <div className="erp-muted">{[inv.seller?.address, inv.seller?.city].filter(Boolean).join(", ")}</div>
            <div className="erp-muted">{[inv.seller?.phone, inv.seller?.email].filter(Boolean).join(" · ")}</div>
            {inv.seller?.tin && <div className="erp-muted">TIN {inv.seller.tin}</div>}
          </div>
          <div className="sal-sheet-title">
            <h1>{inv.status === "draft" ? t("salDraftInvoice") : t("salTaxInvoice")}</h1>
            <div className="tnum"><strong>{inv.number}</strong></div>
            <div className="erp-muted">{t("erpDate")}: {formatDate(inv.invoice_date, locale)}</div>
            <div className="erp-muted">{t("salDue")}: {formatDate(inv.due_date, locale)}</div>
          </div>
        </header>

        <section className="sal-sheet-parties">
          <div>
            <div className="sal-sheet-label">{t("salBillTo")}</div>
            <strong>{c?.name}</strong>
            <div>{[c?.address, c?.city].filter(Boolean).join(", ")}</div>
            {c?.tin && <div>TIN {c.tin}</div>}
          </div>
          <div>
            <div className="sal-sheet-label">{t("salReference")}</div>
            {inv.order && <div>{t("salOrder")}: <Link href={`/erp/sales/orders/${inv.order.id}`} className="tnum">{inv.order.number}</Link></div>}
            {inv.loading_order?.delivery_note_number && <div>{t("salDeliveryNote")}: {inv.loading_order.delivery_note_number}</div>}
            {inv.order?.delivery_address && <div>{inv.order.delivery_address}</div>}
          </div>
        </section>

        <table className="table vf-table sal-sheet-lines">
          <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("salUnitPrice")}</th><th className="num">{t("salDiscountPct")}</th><th className="num">{t("salVatPct")}</th><th className="num">{t("salAmount")}</th></tr></thead>
          <tbody>
            {inv.lines?.map((l) => (
              <tr key={l.id}>
                <td>{l.product?.name}<span className="erp-cell-sub tnum">{l.product?.sku}</span></td>
                <td className="num">{qty(l.quantity)} {l.product?.unit?.code}</td>
                <td className="num"><Money value={l.unit_price} /></td>
                <td className="num">{Number(l.discount_percent) ? `${Number(l.discount_percent)}%` : "-"}</td>
                <td className="num">{Number(l.tax_rate)}%</td>
                <td className="num"><Money value={l.line_total} /></td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="sal-sheet-foot">
          <div className="sal-sheet-notes">
            {(inv.allocations?.length ?? 0) > 0 && (
              <>
                <div className="sal-sheet-label">{t("salPayments")}</div>
                {inv.allocations!.map((a) => <div key={a.id} className="tnum">{a.receipt?.number} · {formatDate(a.receipt?.receipt_date, locale)} · <Money value={a.amount} /> {a.receipt?.status !== "verified" && <em>({t(a.receipt?.status === "rejected" ? "salStRejected" : "salStRecorded")})</em>}</div>)}
              </>
            )}
            {(inv.credit_notes?.length ?? 0) > 0 && (
              <>
                <div className="sal-sheet-label">{t("salCreditNotes")}</div>
                {inv.credit_notes!.map((n) => <div key={n.id} className="tnum"><Link href={`/erp/sales/returns/${n.id}`}>{n.number}</Link> · <Money value={n.total} /> ({t(n.status === "posted" ? "salStPosted" : "salStDraft")})</div>)}
              </>
            )}
          </div>
          <TotalsBlock totals={inv} extra={[
            { label: t("salPaid"), value: <Money value={inv.amount_paid} /> },
            ...(Number(inv.amount_credited) ? [{ label: t("salCredited"), value: <Money value={inv.amount_credited} /> }] : []),
            { label: t("salBalance"), value: <Money value={inv.balance} strong /> },
          ]} />
        </div>
      </article>

      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} />
    </div>
  );
}
