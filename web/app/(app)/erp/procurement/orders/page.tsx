"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Order, OrderStatus } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ProcStatus, Progress, useMoney, usePaged } from "@/components/procurement-ui";

type Filter = OrderStatus | "to_receive" | "";

export default function OrdersPage() {
  return <ErpGate module="procurement" permission="procurement.view"><OrdersLoader /></ErpGate>;
}

function OrdersLoader() {
  const initial = useQueryValue("status");
  if (initial === undefined) return <LoadingBlock rows={5} />;
  return <Orders initial={(initial ?? "") as Filter} />;
}

function Orders({ initial }: { initial: Filter }) {
  const { t, locale } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const [status, setStatus] = useState<Filter>(initial);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const { rows, error } = usePaged<Order>("/erp/procurement/orders", { status: status || undefined, q: q || undefined, page }, !!q);

  return (
    <div className="erp-page">
      <PageHeader title={t("prcOrders")} subtitle={t("prcOrdersSub")}
        actions={can("procurement.order") && <Link className="btn btn-primary" href="/erp/procurement/orders/new"><Icon name="ph-plus" size={18} /> {t("prcNewOrder")}</Link>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("erpSearch")} />
        <FilterChips<Filter> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("prcStDraft") }, { value: "submitted", label: t("prcStSubmitted") },
          { value: "to_receive", label: t("prcToReceive") }, { value: "partially_received", label: t("prcStPartiallyReceived") },
          { value: "received", label: t("prcStReceived") }, { value: "closed", label: t("prcStClosed") }, { value: "cancelled", label: t("prcStCancelled") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-shopping-cart" title={t("prcNoOrders")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("erpSupplier")}</th><th>{t("erpDate")}</th><th>{t("prcReceived")}</th><th className="num">{t("erpTotal")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((o) => (
                  <tr key={o.id} className="is-clickable">
                    <td><Link href={`/erp/procurement/orders/${o.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{o.number}</span>{o.requisition && <span className="erp-cell-sub tnum">{o.requisition.number}</span>}</Link></td>
                    <td>{o.supplier?.name}</td>
                    <td className="tnum">{formatDate(o.order_date, locale)}</td>
                    <td><Progress done={Number(o.received_quantity ?? 0)} of={Number(o.ordered_quantity ?? 0)} /></td>
                    <td className="num">{money(o.total)}</td>
                    <td><ProcStatus status={o.status} /></td>
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
