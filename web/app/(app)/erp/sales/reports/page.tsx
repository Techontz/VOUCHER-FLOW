"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty } from "@/lib/erp";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { Money } from "@/components/sales-ui";

type Group = "customer" | "product" | "month";

interface Report {
  group: string; from: string; to: string;
  rows: { key: string | number; label: string; quantity: number; invoices: number; gross: number; returns: number; net: number; tax: number }[];
  total: { gross: number; returns: number; net: number; tax: number };
}

export default function SalesReportsPage() {
  return <ErpGate module="sales" permission="sales.view"><SalesReports /></ErpGate>;
}

/** Net sales by customer, product or month: posted invoices less posted credit notes, excluding VAT. */
function SalesReports() {
  const { t } = useApp();
  const [group, setGroup] = useState<Group>("customer");
  const [from, setFrom] = useState(`${new Date().getFullYear()}-01-01`);
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10));
  const [data, setData] = useState<Report | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Report }>("/erp/sales/reports/sales", { group, from, to }).then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [group, from, to]);

  const max = Math.max(1, ...(data?.rows ?? []).map((r) => r.net));
  const label = group === "customer" ? t("salCustomer") : group === "product" ? t("erpProduct") : t("salMonth");

  return (
    <div className="erp-page">
      <PageHeader title={t("salReports")} subtitle={t("salReportsSub")}
        actions={<button className="btn btn-secondary sal-noprint" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("salPrint")}</button>} />
      <GlassCard className="sal-noprint">
        <div className="erp-form-grid">
          <Field label={t("salGroupBy")}>
            <FilterChips<Group> value={group} onChange={setGroup} items={[{ value: "customer", label: t("salCustomer") }, { value: "product", label: t("erpProduct") }, { value: "month", label: t("salMonth") }]} />
          </Field>
          <Field label={t("salFrom")} htmlFor="rp-f"><input id="rp-f" className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label={t("salTo")} htmlFor="rp-t"><input id="rp-t" className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      </GlassCard>
      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock /> : data.rows.length === 0 ? <EmptyState icon="ph-chart-bar" title={t("salNoSalesInPeriod")} /> : (
        <div className="erp-grid">
          <GlassCard title={t("salNetSales")}>
            <ul className="erp-hbars">
              {data.rows.slice(0, 10).map((r) => (
                <li key={r.key}>
                  <span className="erp-hbar-label">{r.label}</span>
                  <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(Math.max(0, r.net) / max) * 100}%` }} /></span>
                  <span className="erp-hbar-value"><Money value={r.net} /></span>
                </li>
              ))}
            </ul>
          </GlassCard>
          <GlassCard className="erp-span-2" pad={false}>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{label}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("salInvoices")}</th><th className="num">{t("salGross")}</th><th className="num">{t("salReturns")}</th><th className="num">{t("salNet")}</th><th className="num">{t("salVat")}</th></tr></thead>
                <tbody>
                  {data.rows.map((r) => (
                    <tr key={r.key}>
                      <td>{r.label}</td>
                      <td className="num">{qty(r.quantity)}</td>
                      <td className="num">{r.invoices}</td>
                      <td className="num"><Money value={r.gross} /></td>
                      <td className="num">{r.returns ? <Money value={r.returns} /> : "-"}</td>
                      <td className="num"><Money value={r.net} strong /></td>
                      <td className="num"><Money value={r.tax} /></td>
                    </tr>
                  ))}
                  <tr className="sal-total-row"><td>{t("salTotal")}</td><td /><td /><td className="num"><Money value={data.total.gross} /></td><td className="num"><Money value={data.total.returns} /></td><td className="num"><Money value={data.total.net} strong /></td><td className="num"><Money value={data.total.tax} /></td></tr>
                </tbody>
              </table>
            </div>
          </GlassCard>
        </div>
      )}
    </div>
  );
}
