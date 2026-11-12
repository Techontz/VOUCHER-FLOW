"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type SalesOrder, STATUS_LABEL, usePaged } from "@/lib/sales-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate } from "@/components/erp-ui";
import { Money, SalesBadge } from "@/components/sales-ui";

const STATUSES = ["draft", "submitted", "awaiting_payment", "ready", "loading", "dispatched", "delivered", "rejected", "cancelled"] as const;

export default function OrdersPage() {
  return <ErpGate module="sales" permission="sales.view"><OrdersGate /></ErpGate>;
}

function OrdersGate() {
  const initial = useQueryValue("status");
  if (initial === undefined) return <LoadingBlock />;
  return <Orders initial={initial ?? ""} />;
}

function Orders({ initial }: { initial: string }) {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState(initial);
  const [mode, setMode] = useState("");
  const [q, setQ] = useState("");
  const { rows, error, setPage } = usePaged<SalesOrder>("/erp/sales/orders", { status: status || undefined, payment_mode: mode || undefined }, q);

  return (
    <div className="erp-page">
      <PageHeader title={t("salOrders")} subtitle={t("salOrdersSub")}
        actions={can("sales.order") && <Link className="btn btn-primary" href="/erp/sales/orders/new"><Icon name="ph-plus" size={18} /> {t("salNewOrder")}</Link>} />
      <Toolbar end={<>
        <select className="input" aria-label={t("erpStatus")} value={status} onChange={(e) => setStatus(e.target.value)} style={{ maxWidth: 200 }}>
          <option value="">{t("erpAll")}</option>
          {STATUSES.map((s) => <option key={s} value={s}>{t(STATUS_LABEL[s])}</option>)}
        </select>
        <select className="input" aria-label={t("salPaymentMode")} value={mode} onChange={(e) => setMode(e.target.value)} style={{ maxWidth: 170 }}>
          <option value="">{t("salAnyTerms")}</option>
          <option value="prepayment">{t("salModePrepayment")}</option>
          <option value="credit">{t("salModeCredit")}</option>
        </select>
      </>}>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchDocs")} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-shopping-cart" title={t("salNoOrders")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salOrder")}</th><th>{t("salCustomer")}</th><th>{t("erpDate")}</th><th>{t("salPaymentMode")}</th><th className="num">{t("salTotal")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td><Link className="erp-cell-link" href={`/erp/sales/orders/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.lines_count} {t("erpLines").toLowerCase()}</span></Link></td>
                    <td>{r.customer?.name}</td>
                    <td className="tnum">{formatDate(r.order_date, locale)}</td>
                    <td>{r.payment_mode ? t(r.payment_mode === "prepayment" ? "salModePrepayment" : "salModeCredit") : "-"}</td>
                    <td className="num"><Money value={r.total} /></td>
                    <td><SalesBadge status={r.status} /></td>
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
