"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { COST_OPTION_LABEL, type CostOption, km, useFleetLookups } from "@/lib/fleet";
import { EmptyState, ErrorState, Field, GlassCard, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { ErpGate } from "@/components/erp-ui";
import { useMoney } from "@/components/fleet-ui";

interface Figures { revenue: number; fuel: number; expenses: number; hire: number; fixed: number; total_cost: number; profit: number; distance_km: number }
interface Report {
  from: string; to: string;
  trips: (Figures & { id: number; number: string; cost_option: CostOption; origin: string; destination: string; date: string; vehicle: string | null; driver: string | null; customer: string | null })[];
  vehicles: (Figures & { id: number; registration_number: string; ownership: string; trips: number; fixed_budget: number; unabsorbed_fixed: number })[];
  totals: Figures;
}

export default function FleetReportsPage() {
  return <ErpGate module="fleet" permission="fleet.view"><Reports /></ErpGate>;
}

function iso(d: Date) { return d.toISOString().slice(0, 10); }

function Reports() {
  const { t, locale } = useApp();
  const fmt = useMoney();
  const { lookups } = useFleetLookups();
  const [from, setFrom] = useState(() => iso(new Date(new Date().getTime() - 30 * 86400000)));
  const [to, setTo] = useState(() => iso(new Date()));
  const [vehicle, setVehicle] = useState("");
  const [view, setView] = useState<"trips" | "vehicles">("trips");
  const [data, setData] = useState<Report | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Report }>("/erp/fleet/reports/profitability", { from, to, vehicle_id: vehicle || undefined })
      .then((r) => { setData(r.data); setError(null); }).catch((e) => setError(e.message));
  }, [from, to, vehicle]);

  const profit = (n: number) => <strong className="tnum" style={{ color: n < 0 ? "var(--st-bad-fg)" : undefined }}>{amount(n)}</strong>;

  return (
    <div className="erp-page">
      <PageHeader title={t("fltProfitability")} subtitle={t("fltProfitabilitySub")} />
      <div className="erp-form-grid">
        <Field label={t("fltFrom")} htmlFor="rp-from"><input id="rp-from" type="date" className="input" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label={t("fltTo")} htmlFor="rp-to"><input id="rp-to" type="date" className="input" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        <Field label={t("fltVehicle")} htmlFor="rp-veh">
          <select id="rp-veh" className="input" value={vehicle} onChange={(e) => setVehicle(e.target.value)}>
            <option value="">{t("fltAll")}</option>
            {lookups?.vehicles?.map((v) => <option key={v.id} value={v.id}>{v.registration_number}</option>)}
          </select>
        </Field>
      </div>

      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock rows={6} /> : (
        <>
          <StatPills label={t("fltProfitability")} items={[
            { label: t("fltRevenue"), value: fmt(data.totals.revenue) },
            { label: t("fltFuel"), value: fmt(data.totals.fuel) },
            { label: t("fltExpenses"), value: fmt(data.totals.expenses) },
            { label: t("fltHire"), value: fmt(data.totals.hire) },
            { label: t("fltFixedShare"), value: fmt(data.totals.fixed) },
            { label: t("fltProfit"), value: fmt(data.totals.profit), tone: data.totals.profit < 0 ? "bad" : "ok" },
          ]} />
          <Tabs<"trips" | "vehicles"> label={t("fltProfitability")} value={view} onChange={setView} items={[
            { value: "trips", label: t("fltPerTripView"), count: data.trips.length },
            { value: "vehicles", label: t("fltPerVehicleView"), count: data.vehicles.length },
          ]} />
          <GlassCard pad={false}>
            {view === "trips" ? (data.trips.length === 0 ? <EmptyState icon="ph-chart-bar" title={t("fltNoClosedTrips")} /> : (
              <div className="vf-table-wrap"><table className="table vf-table">
                <thead><tr><th>{t("fltTrip")}</th><th>{t("fltVehicle")}</th><th className="num">km</th><th className="num">{t("fltRevenue")}</th><th className="num">{t("fltFuel")}</th><th className="num">{t("fltExpenses")}</th><th className="num">{t("fltHire")}</th><th className="num">{t("fltFixedShare")}</th><th className="num">{t("fltProfit")}</th></tr></thead>
                <tbody>{data.trips.map((r) => (
                  <tr key={r.id}>
                    <td><Link className="erp-cell-link" href={`/erp/fleet/trips/${r.id}`}><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.origin} → {r.destination} · {formatDate(r.date, locale)} · {t(COST_OPTION_LABEL[r.cost_option])}</span></Link></td>
                    <td>{r.vehicle ?? "-"}<span className="erp-cell-sub">{r.customer}</span></td>
                    <td className="num">{km(r.distance_km)}</td>
                    <td className="num">{amount(r.revenue)}</td><td className="num">{amount(r.fuel)}</td><td className="num">{amount(r.expenses)}</td>
                    <td className="num">{amount(r.hire)}</td><td className="num">{amount(r.fixed)}</td><td className="num">{profit(r.profit)}</td>
                  </tr>
                ))}</tbody>
                <tfoot><tr><th>{t("fltTotal")}</th><th /><th className="num">{km(data.totals.distance_km)}</th><th className="num">{amount(data.totals.revenue)}</th><th className="num">{amount(data.totals.fuel)}</th><th className="num">{amount(data.totals.expenses)}</th><th className="num">{amount(data.totals.hire)}</th><th className="num">{amount(data.totals.fixed)}</th><th className="num">{profit(data.totals.profit)}</th></tr></tfoot>
              </table></div>
            )) : (data.vehicles.length === 0 ? <EmptyState icon="ph-truck" title={t("fltNoClosedTrips")} /> : (
              <div className="vf-table-wrap"><table className="table vf-table">
                <thead><tr><th>{t("fltVehicle")}</th><th className="num">{t("fltTrips")}</th><th className="num">km</th><th className="num">{t("fltRevenue")}</th><th className="num">{t("fltTotalCost")}</th><th className="num">{t("fltProfit")}</th><th className="num">{t("fltUnabsorbed")}</th></tr></thead>
                <tbody>{data.vehicles.map((v) => (
                  <tr key={v.id}>
                    <td><Link href={`/erp/fleet/vehicles/${v.id}`}>{v.registration_number}</Link><span className="erp-cell-sub">{v.ownership === "hired" ? t("fltHired") : t("fltOwned")}</span></td>
                    <td className="num">{v.trips}</td><td className="num">{km(v.distance_km)}</td>
                    <td className="num">{amount(v.revenue)}</td><td className="num">{amount(v.total_cost)}</td><td className="num">{profit(v.profit)}</td>
                    <td className="num">{amount(v.unabsorbed_fixed)}</td>
                  </tr>
                ))}</tbody>
              </table></div>
            ))}
          </GlassCard>
          {view === "vehicles" && <p className="erp-muted">{t("fltUnabsorbedHint")}</p>}
        </>
      )}
    </div>
  );
}
