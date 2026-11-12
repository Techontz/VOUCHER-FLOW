"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Quotation } from "@/lib/sales-api";
import { ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type Act, ActionDialog, Facts, Money, SalesBadge, TotalsBlock } from "@/components/sales-ui";

export default function QuotationPage() {
  return <ErpGate module="sales" permission="sales.view"><QuotationDetail /></ErpGate>;
}

function QuotationDetail() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<Quotation | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Quotation }>(`/erp/sales/quotations/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={6} />;

  const path = `/erp/sales/quotations/${doc.id}`;
  const open = doc.status === "draft" || doc.status === "sent";
  const quote = can("sales.quote");

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/sales/quotations" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salQuotations")}</Link>}
        kicker={t("salQuotation")} title={<span className="tnum">{doc.number}</span>}
        subtitle={<>{doc.customer?.name} · {formatDate(doc.quote_date, locale)}</>}
        actions={<>
          <SalesBadge status={doc.status} />
          {doc.status === "draft" && quote && <Link className="btn btn-secondary" href={`${path}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {doc.status === "draft" && quote && <button className="btn btn-secondary" onClick={() => setAct({ key: "send", path: `${path}/send`, label: t("salMarkSent"), icon: "ph-paper-plane-tilt", title: t("salMarkSentQ") })}>{t("salMarkSent")}</button>}
          {open && quote && <button className="btn btn-secondary" onClick={() => setAct({ key: "reject", path: `${path}/reject`, label: t("salDeclined"), icon: "ph-thumbs-down", tone: "warn", title: t("salDeclinedQ") })}>{t("salDeclined")}</button>}
          {open && quote && <button className="btn btn-secondary" onClick={() => setAct({ key: "cancel", path: `${path}/cancel`, label: t("salCancelDoc"), icon: "ph-x-circle", tone: "warn", title: t("salCancelDoc") })}>{t("salCancelDoc")}</button>}
          {open && quote && can("sales.order") && (
            <button className="btn btn-primary" onClick={() => setAct({
              key: "convert", path: `${path}/convert`, label: t("salConvert"), icon: "ph-arrow-right", title: fill(t("salConvertQ"), { number: doc.number }), sub: t("salConvertSub"),
              then: (r) => router.push(`/erp/sales/orders/${r.data.id}`),
            })}><Icon name="ph-shopping-cart" size={18} /> {t("salConvert")}</button>
          )}
          {doc.order && <Link className="btn btn-secondary" href={`/erp/sales/orders/${doc.order.id}`}>{doc.order.number}</Link>}
        </>} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("salUnitPrice")}</th><th className="num">{t("salDiscountPct")}</th><th className="num">{t("salVatPct")}</th><th className="num">{t("salLineTotal")}</th></tr></thead>
              <tbody>
                {doc.lines?.map((l) => (
                  <tr key={l.id}>
                    <td><span className="erp-cell-title">{l.product?.name}</span><span className="erp-cell-sub tnum">{l.product?.sku}</span></td>
                    <td className="num">{qty(l.quantity)} <span className="erp-muted">{l.product?.unit?.code}</span></td>
                    <td className="num"><Money value={l.unit_price} /></td>
                    <td className="num">{Number(l.discount_percent) ? `${Number(l.discount_percent)}%` : "-"}</td>
                    <td className="num">{Number(l.tax_rate)}%</td>
                    <td className="num"><Money value={l.line_total} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>
        <GlassCard title={t("salSummary")}>
          <TotalsBlock totals={doc} />
          <Facts rows={[
            [t("salValidUntil"), formatDate(doc.valid_until, locale)],
            [t("erpPrepared"), doc.creator?.name],
            [t("salNotes"), doc.notes],
          ]} />
        </GlassCard>
      </div>

      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} />
    </div>
  );
}
