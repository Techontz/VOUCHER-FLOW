"use client";

import Link from "next/link";
import { Fragment, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney, formatDate } from "@/lib/format";
import { type Aged, AGED_BUCKETS, AGED_LABEL } from "@/lib/sales-api";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Money, useCurrency } from "@/components/sales-ui";

export default function AgedPage() {
  return <ErpGate module="sales" permission="sales.view"><AgedReceivables /></ErpGate>;
}

/** What customers owe, by how long past due, as at any date. */
function AgedReceivables() {
  const { t, locale } = useApp();
  const currency = useCurrency();
  const [asOf, setAsOf] = useState(new Date().toISOString().slice(0, 10));
  const [data, setData] = useState<Aged | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<number | null>(null);

  useEffect(() => {
    api.get<{ data: Aged }>("/erp/sales/reports/aged-receivables", { as_of: asOf }).then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [asOf]);

  return (
    <div className="erp-page">
      <PageHeader title={t("salAgedReceivables")} subtitle={t("salAgedSub")}
        actions={<button className="btn btn-secondary sal-noprint" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("salPrint")}</button>} />
      <GlassCard className="sal-noprint">
        <Field label={t("salAsOf")} htmlFor="ag-date"><input id="ag-date" className="input" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} style={{ maxWidth: 220 }} /></Field>
      </GlassCard>
      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock /> : (
        <>
          <StatPills label={t("salAgedReceivables")} items={[
            ...AGED_BUCKETS.map((b) => ({ label: t(AGED_LABEL[b]), value: compactMoney(data.totals[b], currency), tone: b === "current" ? "ok" as const : b === "d90_plus" ? "bad" as const : data.totals[b] > 0 ? "warn" as const : "neutral" as const })),
            { label: t("salTotalDue"), value: compactMoney(data.totals.total, currency) },
          ]} />
          {data.rows.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("salNothingOwedAll")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("salCustomer")}</th>{AGED_BUCKETS.map((b) => <th key={b} className="num">{t(AGED_LABEL[b])}</th>)}<th className="num">{t("salTotal")}</th></tr></thead>
                <tbody>
                  {data.rows.map((r) => (
                    <Fragment key={r.customer_id}>
                      <tr className="is-clickable" onClick={() => setOpen(open === r.customer_id ? null : r.customer_id)}>
                        <td><span className="erp-cell-title">{r.name}</span><span className="erp-cell-sub">{r.code} · <Link href={`/erp/sales/statement?customer=${r.customer_id}`} onClick={(e) => e.stopPropagation()}>{t("salStatement")}</Link></span></td>
                        {AGED_BUCKETS.map((b) => <td key={b} className="num">{r[b] ? <Money value={r[b]} /> : "-"}</td>)}
                        <td className="num"><Money value={r.total} strong /></td>
                      </tr>
                      {open === r.customer_id && r.invoices.map((i) => (
                        <tr key={i.id} className="sal-subrow">
                          <td><Link href={`/erp/sales/invoices/${i.id}`} className="tnum">{i.number}</Link><span className="erp-cell-sub">{t("salDue")} {formatDate(i.due_date, locale)}{i.days_overdue > 0 ? ` · ${i.days_overdue} ${t("salDaysLate")}` : ""}</span></td>
                          {AGED_BUCKETS.map((b) => <td key={b} className="num">{i.bucket === b ? <Money value={i.open} /> : ""}</td>)}
                          <td />
                        </tr>
                      ))}
                    </Fragment>
                  ))}
                  <tr className="sal-total-row"><td>{t("salTotal")}</td>{AGED_BUCKETS.map((b) => <td key={b} className="num"><Money value={data.totals[b]} /></td>)}<td className="num"><Money value={data.totals.total} strong /></td></tr>
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}
