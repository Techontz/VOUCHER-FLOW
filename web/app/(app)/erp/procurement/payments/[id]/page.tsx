"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { PAYMENT_METHODS, type Payment } from "@/lib/procurement-api";
import { ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type ActionSpec, ActionDialog, BackLink, Facts, METHOD_LABEL, ProcStatus, useMoney } from "@/components/procurement-ui";

export default function PaymentPage() {
  return <ErpGate module="procurement" permission="procurement.view"><PaymentDetail /></ErpGate>;
}

function PaymentDetail() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const { id } = useParams<{ id: string }>();
  const [payment, setPayment] = useState<Payment | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionSpec | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Payment }>(`/erp/procurement/payments/${id}`).then((r) => setPayment(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!payment) return <LoadingBlock rows={6} />;

  const base = `/erp/procurement/payments/${payment.id}`;
  const method = (PAYMENT_METHODS as readonly string[]).includes(payment.method) ? t(METHOD_LABEL[payment.method as (typeof PAYMENT_METHODS)[number]]) : payment.method;

  return (
    <div className="erp-page">
      <PageHeader
        back={<BackLink href="/erp/procurement/payments" label={t("prcPayments")} />}
        kicker={t("prcSupplierPayment")}
        title={<span className="tnum">{payment.number}</span>}
        subtitle={<>{payment.supplier?.name} · {formatDate(payment.payment_date, locale)} · {money(payment.amount)}</>}
        actions={<>
          <ProcStatus status={payment.status} />
          {payment.status === "draft" && can("procurement.pay") && <>
            <button className="btn btn-secondary" onClick={() => setAction({ key: "cancel", label: t("prcCancelDoc"), title: fill(t("prcCancelQ"), { number: payment.number }), icon: "ph-x-circle", tone: "warn", path: `${base}/cancel`, danger: true })}>{t("prcCancelDoc")}</button>
            <button className="btn btn-primary" onClick={() => setAction({ key: "post", label: t("erpPost"), title: fill(t("prcPostPaymentQ"), { number: payment.number }), sub: t("prcPostPaymentSub"), icon: "ph-check-circle", path: `${base}/post` })}><Icon name="ph-check-circle" size={17} /> {t("erpPost")}</button>
          </>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prcAllocations")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prcSupplierInvoiceNo")}</th><th>{t("prcDueDate")}</th><th className="num">{t("erpTotal")}</th><th className="num">{t("prcAllocated")}</th></tr></thead>
              <tbody>
                {payment.allocations?.map((a) => (
                  <tr key={a.id}>
                    <td>{a.invoice && <Link className="erp-cell-link" href={`/erp/procurement/invoices/${a.invoice.id}`}><span className="erp-cell-title tnum">{a.invoice.supplier_invoice_number}</span><span className="erp-cell-sub tnum">{a.invoice.number}</span></Link>}</td>
                    <td className="tnum">{a.invoice ? formatDate(a.invoice.due_date, locale) : "-"}</td>
                    <td className="num">{a.invoice ? money(a.invoice.total) : "-"}</td>
                    <td className="num">{money(a.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>
        <GlassCard title={t("erpStatus")}>
          <Facts rows={[
            [t("prcPaidFrom"), payment.account ? `${payment.account.code} · ${payment.account.name}` : null],
            [t("prcMethod"), method],
            [t("erpReference"), payment.reference],
            [t("erpPrepared"), payment.creator ? `${payment.creator.name} · ${formatDateTime(payment.created_at, locale)}` : null],
            [t("erpPostedBy"), payment.poster ? `${payment.poster.name} · ${formatDateTime(payment.posted_at, locale)}` : null],
            [t("prcJournal"), payment.journal?.number ?? null],
            [t("erpNotes"), payment.notes],
          ]} />
        </GlassCard>
      </div>

      <ActionDialog action={action} onClose={() => setAction(null)} onDone={(m) => { toast(m, undefined, "ok"); setAction(null); load(); }}
        summary={[{ label: t("erpSupplier"), value: payment.supplier?.name ?? "-" }, { label: t("prcAmount"), value: money(payment.amount) }]} />
    </div>
  );
}
