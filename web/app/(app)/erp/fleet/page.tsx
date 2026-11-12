"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { km, type Overview, VEHICLE_STATUS_LABEL, VEHICLE_STATUSES } from "@/lib/fleet";
import { Badge, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { ExpiryBadge, TripStatusBadge, useMoney } from "@/components/fleet-ui";

export default function FleetOverviewPage() {
  return <ErpGate module="fleet" permission="fleet.view"><FleetOverview /></ErpGate>;
}

function FleetOverview() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const fmt = useMoney();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Overview }>("/erp/fleet/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const tone = { available: "ok", on_trip: "info", maintenance: "warn", out_of_service: "bad" } as const;
  const kindLabel = { insurance: t("fltInsurance"), road_licence: t("fltRoadLicence"), driving_licence: t("fltDrivingLicence") };

  return (
    <div className="erp-page">
      <PageHeader title={t("fltFleet")} subtitle={t("fltOverviewSub")}
        actions={can("fleet.trips") && <Link className="btn btn-primary" href="/erp/fleet/trips/new"><Icon name="ph-plus" size={18} /> {t("fltPlanTrip")}</Link>} />

      <StatPills label={t("fltVehicles")} items={[
        ...VEHICLE_STATUSES.map((s) => ({ label: t(VEHICLE_STATUS_LABEL[s]), value: data.vehicles.by_status[s] ?? 0, tone: tone[s], href: `/erp/fleet/vehicles?status=${s}` })),
        { label: t("fltPendingApprovals"), value: data.pending_entries, tone: data.pending_entries ? "warn" : "neutral", href: "/erp/fleet/fuel" },
      ]} />

      <StatPills label={t("fltThisMonth")} items={[
        { label: t("fltTripsClosed"), value: data.month.trips_closed, hint: t("fltThisMonth") },
        { label: t("fltRevenue"), value: fmt(data.month.revenue) },
        { label: t("fltTotalCost"), value: fmt(data.month.cost) },
        { label: t("fltProfit"), value: fmt(data.month.profit), tone: data.month.profit < 0 ? "bad" : "ok" },
        { label: t("fltLitresIssued"), value: `${km(data.month.litres)} L` },
      ]} />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("fltTripsToday")} pad={false} action={<Link className="vf-card-link" href="/erp/fleet/trips">{t("fltViewAll")}</Link>}>
          {data.trips_today.length === 0 ? <EmptyState icon="ph-path" title={t("fltNoTripsToday")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltTrip")}</th><th>{t("fltRoute")}</th><th>{t("fltVehicle")}</th><th>{t("fltDriver")}</th><th>{t("fltStatus")}</th></tr></thead>
                <tbody>
                  {data.trips_today.map((trip) => (
                    <tr key={trip.id}>
                      <td><Link className="erp-cell-link" href={`/erp/fleet/trips/${trip.id}`}><span className="erp-cell-title tnum">{trip.number}</span><span className="erp-cell-sub">{formatDateTime(trip.planned_start, locale)}</span></Link></td>
                      <td>{trip.origin} → {trip.destination}</td>
                      <td>{trip.vehicle?.registration_number ?? trip.external_vehicle ?? "-"}</td>
                      <td>{trip.driver?.user?.name ?? "-"}</td>
                      <td><TripStatusBadge status={trip.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("fltFuelAlerts")} pad={false}>
          {data.fuel_alerts.length === 0 ? <EmptyState icon="ph-gas-pump" tone="ok" title={t("fltNoFuelAlerts")} /> : (
            <ul className="erp-actions" style={{ listStyle: "none", margin: 0, padding: 12 }}>
              {data.fuel_alerts.map((trip) => (
                <li key={trip.id}>
                  <Link className="erp-action" href={`/erp/fleet/trips/${trip.id}`}>
                    <span className="erp-action-icon"><Icon name="ph-warning" size={18} /></span>
                    <span className="erp-action-text"><span className="tnum">{trip.number} · {trip.vehicle?.registration_number}</span>
                      <span className="erp-muted">{km(trip.actual_litres)} L / {km(trip.standard_litres)} L · <Badge tone="bad">+{Number(trip.fuel_variance_percent).toFixed(1)}%</Badge></span></span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("fltExpiring")} pad={false}>
          {data.expiring.length === 0 ? <EmptyState icon="ph-shield-check" tone="ok" title={t("fltNothingExpiring")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <tbody>
                  {data.expiring.map((e, i) => (
                    <tr key={i}>
                      <td><span className="erp-cell-title">{e.vehicle_id ? <Link href={`/erp/fleet/vehicles/${e.vehicle_id}`}>{e.subject}</Link> : <Link href="/erp/fleet/drivers">{e.subject}</Link>}</span><span className="erp-cell-sub">{kindLabel[e.kind]}</span></td>
                      <td><ExpiryBadge date={e.date} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("fltMaintenanceDue")} pad={false} action={<Link className="vf-card-link" href="/erp/fleet/maintenance">{t("fltViewAll")}</Link>}>
          {data.maintenance_due.length === 0 ? <EmptyState icon="ph-wrench" tone="ok" title={t("fltNothingDue")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltVehicle")}</th><th>{t("fltService")}</th><th>{t("fltNextDue")}</th><th>{t("fltStatus")}</th></tr></thead>
                <tbody>
                  {data.maintenance_due.map((s) => (
                    <tr key={s.id}>
                      <td><Link href={`/erp/fleet/vehicles/${s.vehicle_id}`}>{s.vehicle?.registration_number}</Link></td>
                      <td>{s.title}</td>
                      <td className="tnum">{[s.next_due_odometer ? `${km(s.next_due_odometer)} km` : null, s.next_due_date ? formatDate(s.next_due_date, locale) : null].filter(Boolean).join(" · ")}</td>
                      <td><Badge tone={s.state === "overdue" ? "bad" : "warn"}>{s.state === "overdue" ? t("fltOverdue") : t("fltDueSoon")}</Badge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      </div>
    </div>
  );
}
