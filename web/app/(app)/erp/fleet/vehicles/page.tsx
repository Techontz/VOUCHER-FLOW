"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { km, type Vehicle, VEHICLE_STATUS_LABEL, VEHICLE_STATUSES, type VehicleStatus } from "@/lib/fleet";
import { Badge, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ExpiryBadge, VehicleStatusBadge } from "@/components/fleet-ui";
import { VehicleFormDialog } from "@/components/fleet-vehicle-form";

export default function VehiclesPage() {
  return <ErpGate module="fleet" permission="fleet.view"><Vehicles /></ErpGate>;
}

function Vehicles() {
  const initial = useQueryValue("status");
  if (initial === undefined) return <LoadingBlock />;
  return <VehicleList initial={(VEHICLE_STATUSES as string[]).includes(initial ?? "") ? (initial as VehicleStatus) : ""} />;
}

function VehicleList({ initial }: { initial: VehicleStatus | "" }) {
  const { t } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const [status, setStatus] = useState<VehicleStatus | "">(initial);
  const [ownership, setOwnership] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Vehicle> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<Vehicle>>("/erp/fleet/vehicles", { status: status || undefined, ownership: ownership || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [status, ownership, q, page]);

  return (
    <div className="erp-page">
      <PageHeader title={t("fltVehicles")} subtitle={t("fltVehiclesSub")}
        actions={can("fleet.manage") && <button className="btn btn-primary" onClick={() => setCreating(true)}><Icon name="ph-plus" size={18} /> {t("fltNewVehicle")}</button>} />

      <Toolbar end={
        <select className="input" aria-label={t("fltOwnership")} value={ownership} onChange={(e) => { setOwnership(e.target.value); setPage(1); }} style={{ maxWidth: 200 }}>
          <option value="">{t("fltAll")}</option>
          <option value="owned">{t("fltOwned")}</option>
          <option value="hired">{t("fltHired")}</option>
        </select>
      }>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("fltSearchVehicles")} />
        <FilterChips<VehicleStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("fltAll") }, ...VEHICLE_STATUSES.map((s) => ({ value: s, label: t(VEHICLE_STATUS_LABEL[s]) })),
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-truck" title={t("fltNoVehicles")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("fltRegistration")}</th><th>{t("fltOwnership")}</th><th>{t("fltDriver")}</th><th className="num">{t("fltOdometer")}</th><th>{t("fltInsurance")}</th><th>{t("fltRoadLicence")}</th><th>{t("fltStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((v) => (
                  <tr key={v.id} className="is-clickable">
                    <td><Link href={`/erp/fleet/vehicles/${v.id}`} className="erp-cell-link"><span className="erp-cell-title tnum">{v.registration_number}</span><span className="erp-cell-sub">{[v.make, v.model, v.capacity ? `${km(v.capacity)} ${v.capacity_unit}` : null].filter(Boolean).join(" · ")}</span></Link></td>
                    <td>{v.ownership === "hired" ? <><Badge tone="info">{t("fltHired")}</Badge><span className="erp-cell-sub">{v.supplier?.name}</span></> : t("fltOwned")}</td>
                    <td>{v.driver?.user?.name ?? "-"}</td>
                    <td className="num">{km(v.odometer)}</td>
                    <td><ExpiryBadge date={v.insurance_expiry} /></td>
                    <td><ExpiryBadge date={v.road_licence_expiry} /></td>
                    <td><VehicleStatusBadge status={v.status} />{!v.is_active && <span className="erp-cell-sub">{t("fltInactive")}</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {creating && <VehicleFormDialog onClose={() => setCreating(false)} onSaved={(v) => router.push(`/erp/fleet/vehicles/${v.id}`)} />}
    </div>
  );
}
