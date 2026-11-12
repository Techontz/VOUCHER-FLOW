"use client";

import Link from "next/link";
import { Fragment, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { useMoney } from "@/components/procurement-ui";

type Bucket = "current" | "days_1_30" | "days_31_60" | "days_61_90" | "over_90";
type Amounts = Record<Bucket | "total", number>;

interface Ageing {
  as_of: string; buckets: Bucket[]; totals: Amounts;
  rows: (Amounts & {
    supplier: { id: number; code: string; name: string };
    invoices: { id: number; number: string; supplier_invoice_number: string; invoice_date: string; due_date: string; days_overdue: number; bucket: Bucket; outstanding: number }[];
  })[];
}

const LABEL: Record<Bucket, MessageKey> = {
  current: "prcBucketCurrent", days_1_30: "prcBucket1to30", days_31_60: "prcBucket31to60", days_61_90: "prcBucket61to90", over_90: "prcBucketOver90",
};

export default function AgeingPage() {
  return <ErpGate module="procurement" permission="procurement.view"><PayablesAgeing /></ErpGate>;
}

function PayablesAgeing() {
  const { t, locale } = useApp();
  const money = useMoney();
  const [asOf, setAsOf] = useState(new Date().toISOString().slice(0, 10));
  const [data, setData] = useState<Ageing | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<number | null>(null);

  useEffect(() => {
    api.get<{ data: Ageing }>("/erp/procurement/ageing", { as_of: asOf }).then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [asOf]);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcAgeing")} subtitle={t("prcAgeingSub")}
        actions={<Field label={t("prcAsOf")} htmlFor="ag-asof"><input id="ag-asof" className="input" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} /></Field>} />

      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock rows={5} /> : (
        <>
          <StatPills label={t("prcAgeing")} items={[
            ...data.buckets.map((b) => ({ label: t(LABEL[b]), value: amount(data.totals[b]), tone: (b === "current" ? "ok" : b === "days_1_30" ? "warn" : "bad") as "ok" | "warn" | "bad" })),
            { label: t("erpTotal"), value: amount(data.totals.total), icon: "ph-wallet" },
          ]} />

          <GlassCard title={fill2(t("prcAgeingBySupplier"), formatDate(data.as_of, locale))} pad={false}>
            {data.rows.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("prcNothingOwedAtAll")} /> : (
              <div className="vf-table-wrap">
                <table className="table vf-table">
                  <thead>
                    <tr><th>{t("erpSupplier")}</th>{data.buckets.map((b) => <th key={b} className="num">{t(LABEL[b])}</th>)}<th className="num">{t("erpTotal")}</th></tr>
                  </thead>
                  <tbody>
                    {data.rows.map((r) => (
                      <Fragment key={r.supplier.id}>
                        <tr className="is-clickable" onClick={() => setOpen(open === r.supplier.id ? null : r.supplier.id)}>
                          <td>
                            <span className="erp-inline-icon"><Icon name={open === r.supplier.id ? "ph-caret-down" : "ph-caret-right"} size={14} /> <span className="erp-cell-title">{r.supplier.name}</span></span>
                            <Link className="erp-cell-sub" href={`/erp/procurement/statement?supplier=${r.supplier.id}`} onClick={(e) => e.stopPropagation()}>{t("prcStatement")}</Link>
                          </td>
                          {data.buckets.map((b) => <td key={b} className="num" style={r[b] && b !== "current" ? { color: "var(--st-bad-fg)" } : undefined}>{r[b] ? amount(r[b]) : "-"}</td>)}
                          <td className="num"><strong>{amount(r.total)}</strong></td>
                        </tr>
                        {open === r.supplier.id && r.invoices.map((i) => (
                          <tr key={i.id}>
                            <td style={{ paddingLeft: 36 }}><Link href={`/erp/procurement/invoices/${i.id}`} className="tnum">{i.supplier_invoice_number}</Link> <span className="erp-muted">· {t("prcDueDate")} {formatDate(i.due_date, locale)}{i.days_overdue ? ` · ${i.days_overdue} ${t("prcDaysLate")}` : ""}</span></td>
                            {data.buckets.map((b) => <td key={b} className="num">{i.bucket === b ? amount(i.outstanding) : ""}</td>)}
                            <td className="num">{amount(i.outstanding)}</td>
                          </tr>
                        ))}
                      </Fragment>
                    ))}
                  </tbody>
                  <tfoot>
                    <tr><th>{t("erpTotal")}</th>{data.buckets.map((b) => <th key={b} className="num">{amount(data.totals[b])}</th>)}<th className="num">{money(data.totals.total)}</th></tr>
                  </tfoot>
                </table>
              </div>
            )}
          </GlassCard>
        </>
      )}
    </div>
  );
}

function fill2(text: string, date: string): string {
  return text.split("{date}").join(date);
}
