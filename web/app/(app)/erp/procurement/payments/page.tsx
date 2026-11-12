"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Payment, PaymentStatus } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ProcStatus, useMoney, usePaged } from "@/components/procurement-ui";

export default function PaymentsPage() {
  return <ErpGate module="procurement" permission="procurement.view"><Payments /></ErpGate>;
}

function Payments() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const [status, setStatus] = useState<PaymentStatus | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const { rows, error } = usePaged<Payment>("/erp/procurement/payments", { status: status || undefined, q: q || undefined, page }, !!q);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcPayments")} subtitle={t("prcPaymentsSub")}
        actions={can("procurement.pay") && <Link className="btn btn-primary" href="/erp/procurement/payments/new"><Icon name="ph-plus" size={18} /> {t("prcNewPayment")}</Link>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("erpSearch")} />
        <FilterChips<PaymentStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("prcStDraft") }, { value: "posted", label: t("prcStPosted") }, { value: "cancelled", label: t("prcStCancelled") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-hand-coins" title={t("prcNoPayments")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("erpSupplier")}</th><th>{t("erpDate")}</th><th>{t("prcPaidFrom")}</th><th className="num">{t("prcAmount")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((p) => (
                  <tr key={p.id} className="is-clickable">
                    <td><Link href={`/erp/procurement/payments/${p.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{p.number}</span>{p.reference && <span className="erp-cell-sub">{p.reference}</span>}</Link></td>
                    <td>{p.supplier?.name}</td>
                    <td className="tnum">{formatDate(p.payment_date, locale)}</td>
                    <td>{p.account ? `${p.account.code} · ${p.account.name}` : "-"}</td>
                    <td className="num">{money(p.amount)}</td>
                    <td><ProcStatus status={p.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}
