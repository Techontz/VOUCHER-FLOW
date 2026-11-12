"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, type Product, qty, type StockBalance, type StockMovement, useErp, useQueryValue, type Warehouse } from "@/lib/erp";
import { compactMoney, formatDate } from "@/lib/format";
import { Badge, EmptyState, ErrorState, GlassCard, LoadingBlock, PageHeader, Pagination, StatPills } from "@/components/ui";
import { SearchInput, Tabs, Toolbar } from "@/components/app-ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { MovementTable } from "@/components/erp-movements";

type Tab = "balances" | "ledger" | "alerts" | "valuation";
const TABS: Tab[] = ["balances", "ledger", "alerts", "valuation"];

export default function StockPage() {
  return <ErpGate module="inventory" permission="inventory.view"><Stock /></ErpGate>;
}

function Stock() {
  const { t } = useApp();
  const wanted = useQueryValue("tab");
  const [chosen, setTab] = useState<Tab | null>(null);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [warehouse, setWarehouse] = useState("");
  // The link's ?tab= until the person picks one themselves.
  const tab: Tab = chosen ?? (TABS.includes(wanted as Tab) ? (wanted as Tab) : "balances");

  useEffect(() => {
    api.get<{ data: Warehouse[] }>("/erp/warehouses").then((r) => setWarehouses(r.data)).catch(() => undefined);
  }, []);

  const filter = (tab === "balances" || tab === "ledger") && (
    <select className="input" aria-label={t("erpWarehouse")} value={warehouse} onChange={(e) => setWarehouse(e.target.value)} style={{ maxWidth: 240 }}>
      <option value="">{t("erpWarehouses")}: {t("erpAll")}</option>
      {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
    </select>
  );

  return (
    <div className="erp-page">
      <PageHeader title={t("erpStock")} subtitle={t("erpStockSub")} />
      <Tabs label={t("erpStock")} value={tab} onChange={setTab} items={[
        { value: "balances", label: t("erpBalances"), icon: "ph-stack" },
        { value: "ledger", label: t("erpLedger"), icon: "ph-list-bullets" },
        { value: "alerts", label: t("erpAlerts"), icon: "ph-bell-ringing" },
        { value: "valuation", label: t("erpValuation"), icon: "ph-coins" },
      ]} />
      {tab === "balances" && <Balances warehouse={warehouse} filter={filter} />}
      {tab === "ledger" && <Ledger warehouse={warehouse} filter={filter} />}
      {tab === "alerts" && <Alerts />}
      {tab === "valuation" && <Valuation />}
    </div>
  );
}

function Balances({ warehouse, filter }: { warehouse: string; filter: React.ReactNode }) {
  const { t, locale } = useApp();
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<StockBalance> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<Paginated<StockBalance>>("/erp/stock/balances", { q: q || undefined, warehouse_id: warehouse || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [q, warehouse, page]);

  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  return (
    <>
      <Toolbar end={filter}><SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}: ${t("erpProduct")}`} /></Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-stack" title={t("erpNoMovements")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th><th>{t("erpWarehouse")}</th><th>{t("erpBatch")}</th><th>{t("erpExpiry")}</th><th className="num">{t("erpOnHand")}</th><th className="num">{t("erpAvgCost")}</th><th className="num">{t("erpValue")}</th></tr></thead>
              <tbody>
                {rows.data.map((b) => (
                  <tr key={b.id}>
                    <td><Link href={`/erp/products/${b.product_id}`} className="erp-cell-link"><span className="erp-cell-title">{b.product?.name}</span><span className="erp-cell-sub tnum">{b.product?.sku}</span></Link></td>
                    <td>{b.warehouse?.name}</td>
                    <td className="tnum">{b.batch_number || "-"}</td>
                    <td className="tnum">{b.expiry_date ? formatDate(b.expiry_date, locale) : "-"}</td>
                    <td className="num">{qty(b.quantity)} <span className="erp-muted">{b.product?.unit?.code}</span></td>
                    <td className="num">{amount(b.average_cost)}</td>
                    <td className="num">{amount(b.value)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </>
  );
}

function Ledger({ warehouse, filter }: { warehouse: string; filter: React.ReactNode }) {
  const { t } = useApp();
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<StockMovement> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<StockMovement>>("/erp/stock/movements", { q: q || undefined, warehouse_id: warehouse || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [q, warehouse, page]);

  return (
    <>
      <Toolbar end={filter}><SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}: ${t("erpReference")}`} /></Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-list" title={t("erpNoMovements")} /> : (
        <>
          <MovementTable rows={rows.data} showProduct />
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </>
  );
}

function Alerts() {
  const { t, locale } = useApp();
  const [data, setData] = useState<{ low_stock: (Product & { on_hand: string | null })[]; expiring: StockBalance[]; expiry_window_days: number } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { api.get<{ data: NonNullable<typeof data> }>("/erp/stock/alerts").then((r) => setData(r.data)).catch((e) => setError(e.message)); }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock />;
  if (!data.low_stock.length && !data.expiring.length) return <EmptyState icon="ph-check-circle" tone="ok" title={t("erpNoAlerts")} />;

  return (
    <div className="erp-grid">
      <GlassCard title={t("erpBelowReorder")} subtitle={String(data.low_stock.length)} pad={false}>
        {data.low_stock.length === 0 ? <EmptyState icon="ph-check" tone="ok" title={t("erpNoAlerts")} /> : (
          <ul className="erp-list">
            {data.low_stock.map((p) => (
              <li key={p.id}><Link href={`/erp/products/${p.id}`} className="erp-list-row">
                <span className="erp-list-main"><span className="erp-list-title">{p.name}</span><span className="erp-list-sub tnum">{p.sku}</span></span>
                <span className="tnum"><strong>{qty(p.on_hand ?? 0)}</strong> / {qty(p.reorder_level)} {p.unit?.code}</span>
              </Link></li>
            ))}
          </ul>
        )}
      </GlassCard>
      <GlassCard title={fill(t("erpExpiring"), { n: data.expiry_window_days })} subtitle={String(data.expiring.length)} pad={false}>
        {data.expiring.length === 0 ? <EmptyState icon="ph-check" tone="ok" title={t("erpNoAlerts")} /> : (
          <ul className="erp-list">
            {data.expiring.map((b) => (
              <li key={b.id}><Link href={`/erp/products/${b.product_id}`} className="erp-list-row">
                <span className="erp-list-main"><span className="erp-list-title">{b.product?.name}</span><span className="erp-list-sub tnum">{b.batch_number} · {b.warehouse?.name} · {qty(b.quantity)}</span></span>
                <Badge tone={b.expired ? "bad" : "warn"} dot>{b.expired ? t("erpExpired") : formatDate(b.expiry_date, locale)}</Badge>
              </Link></li>
            ))}
          </ul>
        )}
      </GlassCard>
    </div>
  );
}

function Valuation() {
  const { t } = useApp();
  const { config } = useErp();
  const [data, setData] = useState<{ total: number; by_warehouse: { id: number; name: string; value: number }[]; by_category: { id: number | null; name: string; value: number }[] } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { api.get<{ data: NonNullable<typeof data> }>("/erp/stock/valuation").then((r) => setData(r.data)).catch((e) => setError(e.message)); }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock />;
  const currency = config?.settings.base_currency ?? "TZS";



  return (
    <>
      <StatPills items={[{ label: t("erpStockValue"), value: compactMoney(data.total, currency), hint: `${currency} ${amount(data.total)} · ${t("erpWeightedAverage")}`, icon: "ph-coins" }]} />
      <div className="erp-grid">
        <GlassCard title={t("erpByWarehouse")}><Bars rows={data.by_warehouse} /></GlassCard>
        <GlassCard title={t("erpByCategory")}><Bars rows={data.by_category} /></GlassCard>
      </div>
    </>
  );
}

/** Horizontal bars scaled to the largest value, for the valuation breakdowns. */
function Bars({ rows }: { rows: { name: string; value: number }[] }) {
  const peak = Math.max(1, ...rows.map((r) => r.value));
  return (
    <ul className="erp-hbars">
      {rows.map((r) => (
        <li key={r.name}>
          <span className="erp-hbar-label">{r.name}</span>
          <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(r.value / peak) * 100}%` }} /></span>
          <span className="erp-hbar-value tnum">{amount(r.value)}</span>
        </li>
      ))}
    </ul>
  );
}
