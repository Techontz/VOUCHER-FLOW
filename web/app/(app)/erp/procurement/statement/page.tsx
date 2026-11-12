"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { useLookups } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Field, GlassCard, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";

interface Statement {
  supplier: { id: number; code: string; name: string; phone: string | null; email: string | null; city: string | null; payment_terms_days: number };
  from: string; to: string; opening_balance: number; closing_balance: number; total_invoiced: number; total_paid: number;
  entries: { date: string; type: "invoice" | "payment"; id: number; number: string; reference: string | null; due_date: string | null; debit: number; credit: number; balance: number }[];
}

const isoDaysAgo = (days: number) => new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);

export default function StatementPage() {
  return <ErpGate module="procurement" permission="procurement.view"><StatementLoader /></ErpGate>;
}

function StatementLoader() {
  const supplier = useQueryValue("supplier");
  if (supplier === undefined) return <LoadingBlock rows={5} />;
  return <SupplierStatement initial={supplier ?? ""} />;
}

function SupplierStatement({ initial }: { initial: string }) {
  const { t, locale } = useApp();
  const { lookups, error: lookupError } = useLookups();
  const [supplierId, setSupplierId] = useState(initial);
  const [from, setFrom] = useState(isoDaysAgo(180));
  const [to, setTo] = useState(isoDaysAgo(0));
  const [data, setData] = useState<Statement | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!supplierId) return;
    api.get<{ data: Statement }>(`/erp/procurement/statement/${supplierId}`, { from, to })
      .then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [supplierId, from, to]);

  if (lookupError) return <ErrorState message={lookupError} />;
  if (!lookups) return <LoadingBlock rows={5} />;

  return (
    <div className="erp-page">
      <PageHeader title={t("prcStatement")} subtitle={t("prcStatementSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("erpSupplier")} htmlFor="st-sup">
            <select id="st-sup" className="input" value={supplierId} onChange={(e) => { setSupplierId(e.target.value); setData(null); }}>
              <option value="">{t("prcPickSupplier")}</option>
              {lookups.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </Field>
          <Field label={t("prcFrom")} htmlFor="st-from"><input id="st-from" className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label={t("prcTo")} htmlFor="st-to" error={error ?? undefined}><input id="st-to" className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      </GlassCard>

      {!supplierId ? <EmptyState icon="ph-file-text" title={t("prcPickSupplierFirst")} /> : !data ? (error ? null : <LoadingBlock rows={4} />) : (
        <>
          <StatPills label={t("prcStatement")} items={[
            { label: t("prcOpeningBalance"), value: amount(data.opening_balance) },
            { label: t("prcInvoiced"), value: amount(data.total_invoiced), icon: "ph-receipt" },
            { label: t("prcPaid"), value: amount(data.total_paid), icon: "ph-hand-coins" },
            { label: t("prcClosingBalance"), value: amount(data.closing_balance), tone: data.closing_balance > 0 ? "warn" : "ok" },
          ]} />
          <GlassCard title={`${data.supplier.name} · ${formatDate(data.from, locale)} → ${formatDate(data.to, locale)}`} pad={false}>
            {data.entries.length === 0 ? <EmptyState icon="ph-tray" title={t("prcNoEntries")} /> : (
              <div className="vf-table-wrap">
                <table className="table vf-table">
                  <thead><tr><th>{t("erpDate")}</th><th>{t("erpReference")}</th><th>{t("prcDetail")}</th><th className="num">{t("prcPaid")}</th><th className="num">{t("prcInvoiced")}</th><th className="num">{t("prcBalance")}</th></tr></thead>
                  <tbody>
                    <tr><td className="tnum">{formatDate(data.from, locale)}</td><td colSpan={4}>{t("prcOpeningBalance")}</td><td className="num">{amount(data.opening_balance)}</td></tr>
                    {data.entries.map((e) => (
                      <tr key={`${e.type}-${e.id}`}>
                        <td className="tnum">{formatDate(e.date, locale)}</td>
                        <td><Link className="tnum" href={`/erp/procurement/${e.type === "invoice" ? "invoices" : "payments"}/${e.id}`}>{e.number}</Link></td>
                        <td>{e.type === "invoice" ? `${t("prcSupplierInvoice")} ${e.reference ?? ""}${e.due_date ? ` · ${t("prcDueDate")} ${formatDate(e.due_date, locale)}` : ""}` : `${t("prcSupplierPayment")}${e.reference ? ` · ${e.reference}` : ""}`}</td>
                        <td className="num">{e.debit ? amount(e.debit) : ""}</td>
                        <td className="num">{e.credit ? amount(e.credit) : ""}</td>
                        <td className="num">{amount(e.balance)}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot><tr><th colSpan={5}>{t("prcClosingBalance")}</th><th className="num">{amount(data.closing_balance)}</th></tr></tfoot>
                </table>
              </div>
            )}
          </GlassCard>
        </>
      )}
    </div>
  );
}
