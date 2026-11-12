"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { AGED_BUCKETS, AGED_LABEL, type Statement, useSalesLookups } from "@/lib/sales-api";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Money } from "@/components/sales-ui";

export default function StatementPage() {
  return <ErpGate module="sales" permission="sales.view"><StatementGate /></ErpGate>;
}

function StatementGate() {
  const customer = useQueryValue("customer");
  if (customer === undefined) return <LoadingBlock rows={4} />;
  return <CustomerStatement initial={customer ?? ""} />;
}

function monthsAgo(n: number) {
  const d = new Date();
  d.setMonth(d.getMonth() - n, 1);
  return d.toISOString().slice(0, 10);
}

/** A customer's account: brought forward, every document in the period, running balance. Prints cleanly. */
function CustomerStatement({ initial }: { initial: string }) {
  const { t, locale } = useApp();
  const { lookups } = useSalesLookups();
  const [customer, setCustomer] = useState(initial);
  const [from, setFrom] = useState(monthsAgo(3));
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10));
  const [data, setData] = useState<Statement | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!customer) return;
    api.get<{ data: Statement }>(`/erp/sales/customers/${customer}/statement`, { from, to })
      .then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [customer, from, to]);

  const href = (type: string, id: number) => type === "invoice" ? `/erp/sales/invoices/${id}` : type === "credit_note" ? `/erp/sales/returns/${id}` : "/erp/sales/receipts";
  const typeLabel = { invoice: t("salInvoice"), receipt: t("salReceipt"), credit_note: t("salCreditNote") };

  return (
    <div className="erp-page">
      <PageHeader title={t("salStatements")} subtitle={t("salStatementsSub")}
        actions={data && <button className="btn btn-secondary sal-noprint" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("salPrint")}</button>} />
      <GlassCard className="sal-noprint">
        <div className="erp-form-grid">
          <Field label={t("salCustomer")} htmlFor="st-c">
            <select id="st-c" className="input" value={customer} onChange={(e) => { setCustomer(e.target.value); setData(null); }}>
              <option value="">{t("salPickCustomer")}</option>
              {lookups?.customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </Field>
          <Field label={t("salFrom")} htmlFor="st-f"><input id="st-f" className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label={t("salTo")} htmlFor="st-t"><input id="st-t" className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      </GlassCard>

      {!customer ? <EmptyState icon="ph-user" title={t("salPickCustomerFirst")} /> : error ? <ErrorState message={error} /> : !data ? <LoadingBlock rows={4} /> : (
        <article className="sal-sheet">
          <header className="sal-sheet-head">
            <div>
              <div className="sal-sheet-label">{t("salStatementFor")}</div>
              <div className="sal-sheet-seller">{data.customer.name}</div>
              <div className="erp-muted">{[data.customer.address, data.customer.city].filter(Boolean).join(", ")}</div>
              <div className="erp-muted">{data.customer.requires_prepayment ? t("salModePrepayment") : `${t("salCreditLimit")}: `}{!data.customer.requires_prepayment && <Money value={data.customer.credit_limit} />}{!data.customer.requires_prepayment && ` · ${data.customer.payment_terms_days} ${t("salDays")}`}</div>
            </div>
            <div className="sal-sheet-title">
              <h1>{t("salStatement")}</h1>
              <div className="erp-muted">{formatDate(data.from, locale)} - {formatDate(data.to, locale)}</div>
              <div>{t("salClosingBalance")}: <Money value={data.closing_balance} strong /></div>
            </div>
          </header>
          <table className="table vf-table sal-sheet-lines">
            <thead><tr><th>{t("erpDate")}</th><th>{t("salDocument")}</th><th>{t("salDetail")}</th><th className="num">{t("salDebit")}</th><th className="num">{t("salCredit")}</th><th className="num">{t("salBalance")}</th></tr></thead>
            <tbody>
              <tr><td className="tnum">{formatDate(data.from, locale)}</td><td colSpan={4}><em>{t("salBroughtForward")}</em></td><td className="num"><Money value={data.opening_balance} /></td></tr>
              {data.lines.map((l) => (
                <tr key={`${l.type}${l.id}`}>
                  <td className="tnum">{formatDate(l.date, locale)}</td>
                  <td><Link href={href(l.type, l.id)} className="tnum">{l.number}</Link><span className="erp-cell-sub">{typeLabel[l.type]}</span></td>
                  <td>{l.detail}</td>
                  <td className="num">{l.debit ? <Money value={l.debit} /> : ""}</td>
                  <td className="num">{l.credit ? <Money value={l.credit} /> : ""}</td>
                  <td className="num"><Money value={l.balance} /></td>
                </tr>
              ))}
              <tr className="sal-total-row"><td colSpan={3}>{t("salTotal")}</td><td className="num"><Money value={data.total_debit} /></td><td className="num"><Money value={data.total_credit} /></td><td className="num"><Money value={data.closing_balance} strong /></td></tr>
            </tbody>
          </table>
          <div className="sal-aged-strip">
            {AGED_BUCKETS.map((b) => <div key={b}><span className="sal-sheet-label">{t(AGED_LABEL[b])}</span><Money value={data.aged[b]} /></div>)}
            <div><span className="sal-sheet-label">{t("salTotalDue")}</span><Money value={data.aged.total} strong /></div>
          </div>
        </article>
      )}
    </div>
  );
}
