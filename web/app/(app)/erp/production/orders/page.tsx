"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, qty, useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { OrderStatus, ProductionOrder } from "@/lib/production-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ORDER_STATUS_LABEL, OrderStatusBadge } from "@/components/production-ui";

type Filter = OrderStatus | "open" | "";

export default function ProductionOrdersPage() {
  return <ErpGate module="production" permission="production.view"><Orders /></ErpGate>;
}

function Orders() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const initial = useQueryValue("status");
  const [status, setStatus] = useState<Filter | null>(null);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<ProductionOrder> | null>(null);
  const [error, setError] = useState<string | null>(null);

  // The deep link (?status=open) is read once the location is known.
  const filter: Filter = status ?? ((initial ?? "") as Filter);

  useEffect(() => {
    if (initial === undefined) return;
    const id = window.setTimeout(() => {
      api.get<Paginated<ProductionOrder>>("/erp/production/orders", { status: filter || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [filter, q, page, initial]);

  const chips: { value: Filter; label: string }[] = [
    { value: "", label: t("erpAll") },
    { value: "open", label: t("prdOpen") },
    ...(["planned", "released", "in_progress", "completed", "closed", "cancelled"] as OrderStatus[]).map((s) => ({ value: s as Filter, label: t(ORDER_STATUS_LABEL[s]) })),
  ];

  return (
    <div className="erp-page">
      <PageHeader title={t("prdNavOrders")} subtitle={t("prdOrdersSub")}
        actions={can("production.plan") && (
          <Link className="btn btn-primary" href="/erp/production/orders/new"><Icon name="ph-plus" size={18} /> {t("prdNewOrder")}</Link>
        )} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("prdSearchOrders")} />
        <FilterChips<Filter> value={filter} onChange={(v) => { setStatus(v); setPage(1); }} items={chips} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? (
        <EmptyState icon="ph-factory" title={t("prdNoOrders")}
          action={can("production.plan") ? <Link className="btn btn-primary" href="/erp/production/orders/new">{t("prdNewOrder")}</Link> : undefined} />
      ) : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prdOrder")}</th><th>{t("erpProduct")}</th><th className="num">{t("prdPlanned")}</th><th className="num">{t("prdReleasedQty")}</th><th>{t("prdPlannedDates")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((o) => (
                  <tr key={o.id} className="is-clickable">
                    <td><Link href={`/erp/production/orders/${o.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{o.number}</span>{o.reference && <span className="erp-cell-sub">{o.reference}</span>}</Link></td>
                    <td><span className="erp-cell-title">{o.product?.name}</span><span className="erp-cell-sub">{o.bom ? `${t("prdVersion")} ${o.bom.version}` : ""}</span></td>
                    <td className="num">{qty(o.planned_quantity)} <span className="erp-muted">{o.product?.unit?.code}</span></td>
                    <td className="num">{qty(o.released_quantity)}</td>
                    <td className="tnum">{formatDate(o.planned_start, locale)}{o.planned_end !== o.planned_start ? ` ${t("prdUntil")} ${formatDate(o.planned_end, locale)}` : ""}</td>
                    <td><OrderStatusBadge status={o.status} /></td>
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
