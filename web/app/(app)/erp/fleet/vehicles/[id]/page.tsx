"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { type Downtime, DOWNTIME_LABEL, type FuelIssue, HIRE_BASIS_LABEL, km, type Schedule, type ServiceRecord, type Trip, type Tyre, type Vehicle } from "@/lib/fleet";
import { Badge, Dialog, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { ErpGate } from "@/components/erp-ui";
import { EntryBadge, ExpiryBadge, FormError, Row, TripStatusBadge, useMoney, useSubmit, VehicleStatusBadge } from "@/components/fleet-ui";
import { VehicleFormDialog } from "@/components/fleet-vehicle-form";

type Detail = Vehicle & {
  trips: Trip[]; fuel: FuelIssue[]; schedules: Schedule[]; tyres: Tyre[]; downtimes: Downtime[]; services: ServiceRecord[];
  open_downtime: Downtime | null;
};

type Tab = "trips" | "fuel" | "services" | "tyres" | "downtime";

export default function VehiclePage() {
  return <ErpGate module="fleet" permission="fleet.view"><VehicleDetail /></ErpGate>;
}

function VehicleDetail() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const fmt = useMoney();
  const { id } = useParams<{ id: string }>();
  const [v, setV] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("trips");
  const [editing, setEditing] = useState(false);
  const [statusTo, setStatusTo] = useState<"available" | "out_of_service" | null>(null);
  const { busy, error: actionError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: Detail }>(`/erp/fleet/vehicles/${id}`).then((r) => setV(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!v) return <LoadingBlock rows={6} />;

  async function changeStatus() {
    if (!statusTo) return;
    const r = await run(() => api.post(`/erp/fleet/vehicles/${id}/status`, { status: statusTo }));
    if (r) { toast(t("fltVehicleSaved"), v?.registration_number, "ok"); setStatusTo(null); load(); }
  }

  const manage = can("fleet.manage");
  const mayToggle = manage && !v.open_downtime && (v.status === "available" || v.status === "out_of_service");

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/fleet/vehicles" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("fltVehicles")}</Link>}
        kicker={v.ownership === "hired" ? `${t("fltHired")} · ${v.supplier?.name ?? ""}` : t("fltOwned")}
        title={<span className="erp-inline-icon tnum"><Icon name="ph-truck" size={34} /> {v.registration_number}</span>}
        subtitle={[v.make, v.model, v.year, v.capacity ? `${km(v.capacity)} ${v.capacity_unit}` : null].filter(Boolean).join(" · ")}
        actions={<>
          <VehicleStatusBadge status={v.status} />
          {manage && <button className="btn btn-secondary" onClick={() => setEditing(true)}><Icon name="ph-pencil-simple" size={17} /> {t("fltEdit")}</button>}
          {mayToggle && (v.status === "available"
            ? <button className="btn btn-secondary" onClick={() => setStatusTo("out_of_service")}>{t("fltTakeOut")}</button>
            : <button className="btn btn-primary" onClick={() => setStatusTo("available")}>{t("fltReturnToService")}</button>)}
        </>}
      />

      <div className="erp-grid">
        <GlassCard title={t("fltVehicle")}>
          <dl className="erp-review">
            <Row label={t("fltOdometer")}><span className="tnum">{km(v.odometer)} km</span></Row>
            <Row label={t("fltDriver")}>{v.driver?.user?.name ?? "-"}</Row>
            <Row label={t("fltType")}>{v.type}</Row>
            {v.ownership === "hired" && <Row label={t("fltHireTerms")}>{v.hire_rate_basis ? `${fmt(v.hire_rate)} ${t(HIRE_BASIS_LABEL[v.hire_rate_basis])}` : "-"}{v.hire_includes_fuel ? ` · ${t("fltWetHire")}` : ""}</Row>}
            {v.open_downtime && <Row label={t("fltOffRoad")}><Badge tone="warn">{t(DOWNTIME_LABEL[v.open_downtime.reason])}</Badge> {formatDateTime(v.open_downtime.started_at, locale)}</Row>}
            {v.notes && <Row label={t("fltNotes")}>{v.notes}</Row>}
          </dl>
        </GlassCard>
        <GlassCard title={t("fltPapers")}>
          <dl className="erp-review">
            <Row label={t("fltInsurance")}>{v.insurer ?? "-"}{v.insurance_policy_number ? <span className="erp-cell-sub">{v.insurance_policy_number}</span> : null}</Row>
            <Row label={t("fltInsuranceExpiry")}><ExpiryBadge date={v.insurance_expiry} /></Row>
            <Row label={t("fltRoadLicence")}>{v.road_licence_number ?? "-"}</Row>
            <Row label={t("fltRoadLicenceExpiry")}><ExpiryBadge date={v.road_licence_expiry} /></Row>
          </dl>
        </GlassCard>
        <GlassCard title={t("fltFixedCosts")}>
          {v.ownership === "hired" ? <p className="erp-muted">{t("fltHiredNoFixed")}</p> : (
            <dl className="erp-review">
              <Row label={t("fltMonthlyInsurance")}><span className="tnum">{fmt(v.monthly_insurance)}</span></Row>
              <Row label={t("fltMonthlyLicence")}><span className="tnum">{fmt(v.monthly_licence)}</span></Row>
              <Row label={t("fltMonthlyDepreciation")}><span className="tnum">{fmt(v.monthly_depreciation)}</span></Row>
              <Row label={t("fltMonthlyOther")}><span className="tnum">{fmt(v.monthly_other_fixed)}</span></Row>
              <Row label={t("fltPerMonth")}><strong className="tnum">{fmt(v.monthly_fixed_cost ?? 0)}</strong><span className="erp-cell-sub">{v.allocation_basis === "km" ? `${t("fltByKm")} · ${km(v.expected_monthly_km)} km` : t("fltByDays")}</span></Row>
            </dl>
          )}
        </GlassCard>
      </div>

      <Tabs<Tab> label={t("fltHistory")} value={tab} onChange={setTab} items={[
        { value: "trips", label: t("fltTrips"), count: v.trips.length },
        { value: "fuel", label: t("fltFuel"), count: v.fuel.length },
        { value: "services", label: t("fltMaintenance"), count: v.services.length },
        { value: "tyres", label: t("fltTyres"), count: v.tyres.filter((x) => !x.removed_date).length },
        { value: "downtime", label: t("fltDowntime"), count: v.downtimes.length },
      ]} />

      <GlassCard pad={false}>
        {tab === "trips" && (v.trips.length === 0 ? <EmptyState icon="ph-path" title={t("fltNoTrips")} /> : (
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltTrip")}</th><th>{t("fltRoute")}</th><th>{t("fltDriver")}</th><th>{t("fltCustomer")}</th><th>{t("fltStatus")}</th></tr></thead>
            <tbody>{v.trips.map((trip) => (
              <tr key={trip.id}>
                <td><Link className="erp-cell-link" href={`/erp/fleet/trips/${trip.id}`}><span className="erp-cell-title tnum">{trip.number}</span><span className="erp-cell-sub">{formatDate(trip.planned_start, locale)}</span></Link></td>
                <td>{trip.origin} → {trip.destination}</td><td>{trip.driver?.user?.name ?? "-"}</td><td>{trip.customer?.name ?? "-"}</td>
                <td><TripStatusBadge status={trip.status} /></td>
              </tr>
            ))}</tbody>
          </table></div>
        ))}
        {tab === "fuel" && (v.fuel.length === 0 ? <EmptyState icon="ph-gas-pump" title={t("fltNoFuel")} /> : (
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltDate")}</th><th>{t("fltTrip")}</th><th>{t("fltStation")}</th><th className="num">{t("fltLitres")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltStatus")}</th></tr></thead>
            <tbody>{v.fuel.map((f) => (
              <tr key={f.id}>
                <td className="tnum">{formatDate(f.issue_date, locale)}</td>
                <td>{f.trip ? <Link href={`/erp/fleet/trips/${f.trip.id}`}>{f.trip.number}</Link> : "-"}</td>
                <td>{f.station ?? "-"}</td><td className="num">{km(f.litres)}</td><td className="num">{amount(f.amount)}</td><td><EntryBadge status={f.status} /></td>
              </tr>
            ))}</tbody>
          </table></div>
        ))}
        {tab === "services" && (
          <>
            {v.schedules.length > 0 && (
              <div className="vf-table-wrap"><table className="table vf-table">
                <thead><tr><th>{t("fltSchedule")}</th><th>{t("fltInterval")}</th><th>{t("fltNextDue")}</th><th>{t("fltStatus")}</th></tr></thead>
                <tbody>{v.schedules.map((s) => (
                  <tr key={s.id}>
                    <td>{s.title}</td>
                    <td>{[s.interval_km ? `${km(s.interval_km)} km` : null, s.interval_days ? `${s.interval_days} ${t("fltDays")}` : null].filter(Boolean).join(" / ")}</td>
                    <td className="tnum">{[s.next_due_odometer ? `${km(s.next_due_odometer)} km` : null, s.next_due_date ? formatDate(s.next_due_date, locale) : null].filter(Boolean).join(" · ")}</td>
                    <td><Badge tone={s.state === "overdue" ? "bad" : s.state === "due" ? "warn" : "ok"}>{s.state === "overdue" ? t("fltOverdue") : s.state === "due" ? t("fltDueSoon") : t("fltOk")}</Badge></td>
                  </tr>
                ))}</tbody>
              </table></div>
            )}
            {v.services.length === 0 ? <EmptyState icon="ph-wrench" title={t("fltNoServices")} /> : (
              <div className="vf-table-wrap"><table className="table vf-table">
                <thead><tr><th>{t("fltService")}</th><th>{t("fltWorkDone")}</th><th>{t("fltGarage")}</th><th className="num">{t("fltCost")}</th><th>{t("fltStatus")}</th></tr></thead>
                <tbody>{v.services.map((s) => (
                  <tr key={s.id}>
                    <td><span className="tnum">{s.number}</span><span className="erp-cell-sub">{formatDate(s.service_date, locale)}{s.odometer ? ` · ${km(s.odometer)} km` : ""}</span></td>
                    <td>{s.work_done}</td><td>{s.supplier?.name ?? "-"}</td><td className="num">{amount(s.cost)}</td>
                    <td><Badge tone={s.status === "posted" ? "ok" : s.status === "draft" ? "info" : "neutral"}>{t(s.status === "posted" ? "fltPosted" : s.status === "draft" ? "fltDraft" : "fltStatusCancelled")}</Badge></td>
                  </tr>
                ))}</tbody>
              </table></div>
            )}
          </>
        )}
        {tab === "tyres" && (v.tyres.length === 0 ? <EmptyState icon="ph-circle-dashed" title={t("fltNoTyres")} /> : (
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltPosition")}</th><th>{t("fltSerial")}</th><th>{t("fltFitted")}</th><th>{t("fltRemoved")}</th><th className="num">{t("fltKmRun")}</th></tr></thead>
            <tbody>{v.tyres.map((x) => (
              <tr key={x.id}>
                <td>{x.position}</td><td className="tnum">{x.serial_number}<span className="erp-cell-sub">{[x.brand, x.size].filter(Boolean).join(" ")}</span></td>
                <td className="tnum">{formatDate(x.fitted_date, locale)} · {km(x.fitted_odometer)} km</td>
                <td>{x.removed_date ? <>{formatDate(x.removed_date, locale)}<span className="erp-cell-sub">{x.removal_reason}</span></> : <Badge tone="ok">{t("fltOnVehicle")}</Badge>}</td>
                <td className="num">{km(Number(x.removed_odometer ?? v.odometer) - Number(x.fitted_odometer))}</td>
              </tr>
            ))}</tbody>
          </table></div>
        ))}
        {tab === "downtime" && (v.downtimes.length === 0 ? <EmptyState icon="ph-clock" title={t("fltNoDowntime")} /> : (
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltReason")}</th><th>{t("fltStarted")}</th><th>{t("fltEnded")}</th></tr></thead>
            <tbody>{v.downtimes.map((d) => (
              <tr key={d.id}>
                <td>{t(DOWNTIME_LABEL[d.reason])}<span className="erp-cell-sub">{d.description}</span></td>
                <td className="tnum">{formatDateTime(d.started_at, locale)}</td>
                <td className="tnum">{d.ended_at ? formatDateTime(d.ended_at, locale) : <Badge tone="warn">{t("fltOpen")}</Badge>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        ))}
      </GlassCard>

      {editing && <VehicleFormDialog vehicle={v} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load(); }} />}

      <Dialog open={statusTo !== null} title={statusTo === "available" ? t("fltReturnToService") : t("fltTakeOut")} onClose={() => setStatusTo(null)} busy={busy}
        icon="ph-truck" tone={statusTo === "available" ? "info" : "warn"} summary={[{ label: t("fltVehicle"), value: v.registration_number }]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setStatusTo(null)} disabled={busy}>{t("fltBack")}</button>
          <button className={statusTo === "available" ? "btn btn-primary" : "btn btn-danger"} onClick={changeStatus} disabled={busy}>{t("fltConfirm")}</button>
        </>}>
        <FormError error={actionError} />
      </Dialog>
    </div>
  );
}
