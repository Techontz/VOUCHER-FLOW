"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { compactMoney, formatDate } from "@/lib/format";
import { ORDER_STATUSES, type Overview } from "@/lib/production-api";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills, type StatPill } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { ORDER_STATUS_LABEL, OrderStatusBadge, percent } from "@/components/production-ui";

export default function ProductionOverviewPage() {
  return <ErpGate module="production" permission="production.view"><ProductionOverview /></ErpGate>;
}

function ProductionOverview() {
  const { t, locale } = useApp();
  const { can, config } = useErp();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Overview }>("/erp/production/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const p = data.period;
  const pills: StatPill[] = [
    { label: t("prdOpenOrders"), value: data.open_orders, icon: "ph-factory", href: "/erp/production/orders?status=open" },
    { label: t("prdTodayOutput"), value: qty(data.today.released), hint: fill(t("prdTodayHint"), { produced: qty(data.today.produced) }), icon: "ph-package" },
    { label: t("prdQcPending"), value: data.qc_pending, icon: "ph-seal-check", tone: data.qc_pending ? "warn" : "ok", href: "/erp/production/qc" },
    { label: t("prdYield30"), value: percent(p.yield_percent), hint: fill(t("prdYieldHint"), { released: qty(p.released), produced: qty(p.produced) }), icon: "ph-chart-line-up", tone: p.yield_percent !== null && p.yield_percent < 95 ? "warn" : "neutral" },
    { label: t("prdWastage30"), value: percent(p.wastage_percent), hint: fill(t("prdWastageHint"), { wastage: qty(p.wastage), rejected: qty(p.rejected) }), icon: "ph-recycle" },
    { label: t("prdMaterialsIssued"), value: compactMoney(p.materials_issued_value, currency), hint: `${currency} ${amount(p.materials_issued_value)}`, icon: "ph-tray-arrow-up" },
  ];

  const peak = Math.max(1, ...data.trend.map((d) => d.produced));
  const statusPeak = Math.max(1, ...ORDER_STATUSES.map((s) => data.by_status[s] ?? 0));

  return (
    <div className="erp-page">
      <PageHeader title={t("prdNav")} subtitle={t("prdOverviewSub")}
        actions={<>
          {can("production.plan") && <Link className="btn btn-primary" href="/erp/production/orders/new"><Icon name="ph-plus" size={18} /> {t("prdNewOrder")}</Link>}
          <Link className="btn btn-secondary" href="/erp/production/genealogy"><Icon name="ph-tree-structure" size={18} /> {t("prdNavGenealogy")}</Link>
        </>} />

      <div className="app-dash-figures" data-count={pills.length}><StatPills items={pills} label={t("prdNav")} /></div>

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prdOutputTrend")} subtitle={t("prdOutputTrendSub")}>
          <div className="erp-bars" style={{ gridTemplateColumns: `repeat(${data.trend.length}, minmax(0, 1fr))` }} role="img"
            aria-label={data.trend.map((d) => `${formatDate(d.date, locale)}: ${qty(d.released)}`).join(", ")}>
            {data.trend.map((d, i) => (
              <div key={d.date} className="erp-bar" title={`${formatDate(d.date, locale)} · ${t("prdProduced")} ${qty(d.produced)} · ${t("prdReleasedQty")} ${qty(d.released)}`}>
                <div className="erp-bar-track">
                  <div className="erp-bar-fill" style={{ height: `${Math.max(d.produced ? 6 : 0, (d.produced / peak) * 100)}%` }} data-today={i === data.trend.length - 1 ? "" : undefined} />
                </div>
                <span className="erp-bar-label">{new Date(`${d.date}T00:00:00`).getDate()}</span>
              </div>
            ))}
          </div>
        </GlassCard>

        <GlassCard title={t("prdByStatus")} action={<Link className="vf-card-link" href="/erp/production/orders">{t("erpViewAll")}</Link>}>
          <ul className="erp-hbars">
            {ORDER_STATUSES.map((s) => (
              <li key={s}>
                <span className="erp-hbar-label"><Link href={`/erp/production/orders?status=${s}`}>{t(ORDER_STATUS_LABEL[s])}</Link></span>
                <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${((data.by_status[s] ?? 0) / statusPeak) * 100}%` }} /></span>
                <span className="erp-hbar-value tnum">{data.by_status[s] ?? 0}</span>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("prdByProduct")} subtitle={fill(t("prdVarianceClosedLine"), { amount: `${currency} ${amount(p.variance_closed)}` })} pad={false}>
          {data.by_product.length === 0 ? <EmptyState icon="ph-factory" title={t("prdNoOutput")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("prdProduced")}</th><th className="num">{t("prdReleasedQty")}</th><th className="num">{t("prdWaste")}</th><th className="num">{t("prdYield")}</th></tr></thead>
                <tbody>
                  {data.by_product.map((r) => (
                    <tr key={r.product_id}>
                      <td><span className="erp-cell-title">{r.name}</span><span className="erp-cell-sub tnum">{r.sku}</span></td>
                      <td className="num">{qty(r.produced)}</td>
                      <td className="num">{qty(r.released)}</td>
                      <td className="num">{qty(r.wastage)}</td>
                      <td className="num">{percent(r.yield_percent)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("prdUpcoming")} pad={false} action={<Link className="vf-card-link" href="/erp/production/orders?status=open">{t("erpViewAll")}</Link>}>
          {data.recent_orders.length === 0 ? <EmptyState icon="ph-calendar-blank" title={t("prdNoOpenOrders")} /> : (
            <ul className="erp-list">
              {data.recent_orders.map((o) => (
                <li key={o.id}>
                  <Link href={`/erp/production/orders/${o.id}`} className="erp-list-row">
                    <span className="erp-list-icon"><Icon name="ph-factory" size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title">{o.product?.name}</span>
                      <span className="erp-list-sub tnum">{o.number} · {qty(o.released_quantity)} / {qty(o.planned_quantity)} · {formatDate(o.planned_start, locale)}</span>
                    </span>
                    <OrderStatusBadge status={o.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      </div>
    </div>
  );
}
