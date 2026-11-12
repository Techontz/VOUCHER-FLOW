"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { Invoice } from "@/lib/procurement-api";
import { Badge, Banner, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type ActionSpec, ActionDialog, ApprovalTrail, BackLink, Facts, ProcStatus, useMoney } from "@/components/procurement-ui";

export default function InvoicePage() {
  return <ErpGate module="procurement" permission="procurement.view"><InvoiceDetail /></ErpGate>;
}

function InvoiceDetail() {
  const { t, locale, toast, user } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const { id } = useParams<{ id: string }>();
  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionSpec | null>(null);
  const router = useRouter();
  // The payment voucher on its way for this invoice, if one is.
  const [voucher, setVoucher] = useState<{ id: number; number: string; status: string } | null>(null);
  const [raising, setRaising] = useState(false);

  const load = useCallback(() => {
    api.get<{ data: Invoice }>(`/erp/procurement/invoices/${id}`).then((r) => setInvoice(r.data)).catch((e) => setError(e.message));
    api.get<{ data: { id: number; number: string; status: string } | null }>(`/erp/procurement/invoices/${id}/voucher`)
      .then((r) => setVoucher(r.data)).catch(() => setVoucher(null));
  }, [id]);

  /** Sends the invoice through VouchFlow: a draft voucher for what is owed. */
  async function raiseVoucher() {
    setRaising(true);
    try {
      const r = await api.post<{ data: { id: number; number: string } }>(`/erp/procurement/invoices/${id}/voucher`);
      toast(t("linkRaised"), fill(t("linkRaisedBody"), { number: r.data.number }), "ok");
      router.push(`/vouchers/${r.data.id}`);
    } catch (e) {
      toast(t("linkRaiseFailed"), (e as Error).message, "bad");
      setRaising(false);
    }
  }
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!invoice) return <LoadingBlock rows={6} />;

  const base = `/erp/procurement/invoices/${invoice.id}`;
  const open = ["draft", "awaiting_approval", "approved"].includes(invoice.status);
  const actions: ActionSpec[] = [];
  if (invoice.status === "awaiting_approval" && can("procurement.approve") && invoice.created_by !== user?.id) {
    actions.push({ key: "approve", label: t("prcApproveVariance"), title: fill(t("prcApproveVarianceQ"), { number: invoice.number }), sub: t("prcApproveVarianceSub"), icon: "ph-seal-check", tone: "warn", path: `${base}/approve`, comment: "optional" });
  }
  if (["draft", "approved"].includes(invoice.status) && can("procurement.invoice")) {
    actions.push({ key: "post", label: t("erpPost"), title: fill(t("prcPostInvoiceQ"), { number: invoice.number }), sub: t("prcPostInvoiceSub"), icon: "ph-check-circle", path: `${base}/post` });
  }
  if (open && can("procurement.invoice")) {
    actions.push({ key: "cancel", label: t("prcCancelDoc"), title: fill(t("prcCancelQ"), { number: invoice.number }), icon: "ph-x-circle", tone: "warn", path: `${base}/cancel`, danger: true });
  }

  const lines = invoice.lines ?? [];
  const priceVariance = lines.reduce((s, l) => s + Number(l.price_variance), 0);

  return (
    <div className="erp-page">
      <PageHeader
        back={<BackLink href="/erp/procurement/invoices" label={t("prcInvoices")} />}
        kicker={`${t("prcSupplierInvoice")} · ${invoice.number}`}
        title={<span className="tnum">{invoice.supplier_invoice_number}</span>}
        subtitle={<>{invoice.supplier?.name} · {formatDate(invoice.invoice_date, locale)} · {t("prcDueDate")} {formatDate(invoice.due_date, locale)}</>}
        actions={<>
          <ProcStatus status={invoice.status} />
          {invoice.status === "posted" && <ProcStatus status={invoice.payment_status} />}
          {open && can("procurement.invoice") && <Link className="btn btn-secondary" href={`${base}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {voucher && <Link className="btn btn-secondary" href={`/vouchers/${voucher.id}`}><Icon name="ph-receipt" size={17} /> {fill(t("linkVoucherOpen"), { number: voucher.number })}</Link>}
          {invoice.status === "posted" && invoice.outstanding > 0 && can("procurement.pay") && !voucher && (
            <button type="button" className="btn btn-primary" onClick={raiseVoucher} disabled={raising}><Icon name="ph-receipt" size={17} /> {t("linkRaiseVoucher")}</button>
          )}
          {invoice.status === "posted" && invoice.outstanding > 0 && can("procurement.pay") && <Link className="btn btn-secondary" href={`/erp/procurement/payments/new?supplier=${invoice.supplier_id}&invoice=${invoice.id}`}><Icon name="ph-hand-coins" size={17} /> {t("prcPay")}</Link>}
          {actions.map((a) => (
            <button key={a.key} className={a.key === "cancel" ? "btn btn-secondary" : "btn btn-primary"} onClick={() => setAction(a)}><Icon name={a.icon} size={17} /> {a.label}</button>
          ))}
        </>}
      />

      {invoice.status === "awaiting_approval" && <Banner tone="warn" icon="ph-warning" title={t("prcVarianceBannerTitle")}>{t("prcVarianceBannerBody")}</Banner>}

      <GlassCard title={t("prcThreeWayMatch")} subtitle={t("prcThreeWayMatchSub")} pad={false}>
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead>
              <tr>
                <th>{t("prcItem")}</th>
                <th className="num">{t("prcOrdered")}</th>
                <th className="num">{t("prcOrderPrice")}</th>
                <th className="num">{t("prcReceivedNotInvoiced")}</th>
                <th className="num">{t("prcInvoicedQty")}</th>
                <th className="num">{t("prcInvoicePrice")}</th>
                <th className="num">{t("prcQuantityVariance")}</th>
                <th className="num">{t("prcPriceVariance")}</th>
                <th>{t("prcMatch")}</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((l) => (
                <tr key={l.id}>
                  <td><span className="erp-cell-title">{l.description}</span>{l.expense_account && <span className="erp-cell-sub">{l.expense_account.code} · {l.expense_account.name}</span>}</td>
                  <td className="num">{l.order_line ? qty(l.order_line.quantity) : "-"}</td>
                  <td className="num">{amount(l.order_unit_price)}</td>
                  <td className="num">{qty(l.matchable_quantity)}</td>
                  <td className="num">{qty(l.quantity)}</td>
                  <td className="num">{amount(l.unit_price)}</td>
                  <td className="num" style={Number(l.quantity_variance) > 0 ? { color: "var(--st-bad-fg)", fontWeight: 600 } : undefined}>{Number(l.quantity_variance) > 0 ? `+${qty(l.quantity_variance)}` : qty(l.quantity_variance)}</td>
                  <td className="num" style={Number(l.price_variance) !== 0 ? { color: l.flagged ? "var(--st-bad-fg)" : undefined, fontWeight: 600 } : undefined}>{amount(l.price_variance)}</td>
                  <td>{l.flagged ? <Badge tone="bad" dot>{t("prcStVariance")}</Badge> : <Badge tone="ok" dot>{t("prcStMatched")}</Badge>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </GlassCard>

      <div className="erp-grid">
        <GlassCard title={t("prcAmounts")}>
          <Facts rows={[
            [t("prcSubtotal"), money(invoice.subtotal)],
            [t("prcVat"), money(invoice.vat_amount)],
            [t("erpTotal"), <strong key="t">{money(invoice.total)}</strong>],
            [t("prcPriceVariance"), money(priceVariance)],
            [t("prcPaid"), money(invoice.amount_paid)],
            [t("prcOutstanding"), invoice.status === "posted" ? money(invoice.outstanding) : null],
          ]} />
        </GlassCard>

        <GlassCard title={t("erpStatus")}>
          <Facts rows={[
            [t("prcOrder"), invoice.order ? <Link className="tnum" href={`/erp/procurement/orders/${invoice.order.id}`}>{invoice.order.number}</Link> : null],
            [t("erpPrepared"), invoice.creator ? `${invoice.creator.name} · ${formatDateTime(invoice.created_at, locale)}` : null],
            [t("prcVarianceApprovedBy"), invoice.variance_approver ? `${invoice.variance_approver.name} · ${formatDateTime(invoice.variance_approved_at, locale)}` : null],
            [t("erpPostedBy"), invoice.poster ? `${invoice.poster.name} · ${formatDateTime(invoice.posted_at, locale)}` : null],
            [t("prcJournal"), invoice.journal?.number ?? null],
            [t("erpNotes"), invoice.notes],
          ]} />
        </GlassCard>

        <GlassCard title={t("prcPayments")} pad={false}>
          {!invoice.allocations?.length ? <EmptyState icon="ph-hand-coins" title={t("prcNoPayments")} /> : (
            <ul className="erp-list">
              {invoice.allocations.map((a) => (
                <li key={a.id}>
                  <Link className="erp-list-row" href={`/erp/procurement/payments/${a.payment?.id}`}>
                    <span className="erp-list-icon"><Icon name="ph-hand-coins" size={18} /></span>
                    <span className="erp-list-main"><span className="erp-list-title tnum">{a.payment?.number}</span><span className="erp-list-sub">{a.payment ? formatDate(a.payment.payment_date, locale) : ""} · {money(a.amount)}</span></span>
                    <ProcStatus status={a.payment?.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("prcApprovals")}>
          <ApprovalTrail approvals={invoice.approvals} />
        </GlassCard>
      </div>

      <ActionDialog action={action} onClose={() => setAction(null)} onDone={(m) => { toast(m, undefined, "ok"); setAction(null); load(); }}
        summary={[{ label: t("erpSupplier"), value: invoice.supplier?.name ?? "-" }, { label: t("erpTotal"), value: money(invoice.total) }]} />
    </div>
  );
}
