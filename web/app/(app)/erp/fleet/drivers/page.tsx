"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp } from "@/lib/erp";
import { type Driver, type Lookups, useFleetLookups } from "@/lib/fleet";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { ExpiryBadge, FormError, useMoney, useSubmit } from "@/components/fleet-ui";

export default function DriversPage() {
  return <ErpGate module="fleet" permission="fleet.view"><Drivers /></ErpGate>;
}

function Drivers() {
  const { t } = useApp();
  const { can } = useErp();
  const fmt = useMoney();
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Driver> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Driver | "new" | null>(null);

  const load = useCallback(() => {
    api.get<Paginated<Driver>>("/erp/fleet/drivers", { q: q || undefined, page }).then(setRows).catch((e) => setError(e.message));
  }, [q, page]);
  useEffect(() => {
    const id = window.setTimeout(load, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [load, q]);

  const manage = can("fleet.manage");

  return (
    <div className="erp-page">
      <PageHeader title={t("fltDrivers")} subtitle={t("fltDriversSub")}
        actions={manage && <button className="btn btn-primary" onClick={() => setEditing("new")}><Icon name="ph-plus" size={18} /> {t("fltNewDriver")}</button>} />
      <Toolbar><SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("fltSearchDrivers")} /></Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-steering-wheel" title={t("fltNoDrivers")} body={t("fltNoDriversBody")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("fltDriver")}</th><th>{t("fltLicence")}</th><th>{t("fltLicenceExpiry")}</th><th>{t("fltVehicle")}</th><th className="num">{t("fltDailyAllowance")}</th><th className="num">{t("fltOpenTrips")}</th>{manage && <th />}</tr></thead>
              <tbody>
                {rows.data.map((d) => (
                  <tr key={d.id}>
                    <td><span className="erp-cell-title">{d.user?.name}</span><span className="erp-cell-sub">{d.phone ?? d.user?.phone ?? d.user?.email}</span>{!d.is_active && <span className="erp-cell-sub">{t("fltInactive")}</span>}</td>
                    <td className="tnum">{d.licence_number}{d.licence_class && <span className="erp-cell-sub">{t("fltClass")} {d.licence_class}</span>}</td>
                    <td><ExpiryBadge date={d.licence_expiry} /></td>
                    <td>{d.vehicle ? <Link href={`/erp/fleet/vehicles/${d.vehicle.id}`}>{d.vehicle.registration_number}</Link> : "-"}</td>
                    <td className="num">{fmt(d.daily_allowance)}</td>
                    <td className="num">{d.open_trips_count ?? 0}</td>
                    {manage && <td><button className="btn btn-secondary btn-sm" onClick={() => setEditing(d)}>{t("fltEdit")}</button></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {editing && <DriverDialog driver={editing === "new" ? null : editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load(); }} />}
    </div>
  );
}

function DriverDialog({ driver, onClose, onSaved }: { driver: Driver | null; onClose: () => void; onSaved: () => void }) {
  const { t, toast } = useApp();
  const { lookups } = useFleetLookups();
  const { busy, error, run } = useSubmit();
  const [candidates, setCandidates] = useState<{ id: number; name: string; email: string }[] | null>(driver ? [] : null);
  const [f, setF] = useState({
    user_id: "", licence_number: driver?.licence_number ?? "", licence_class: driver?.licence_class ?? "",
    licence_expiry: driver?.licence_expiry?.slice(0, 10) ?? "", phone: driver?.phone ?? "",
    vehicle_id: driver?.vehicle_id ? String(driver.vehicle_id) : "", daily_allowance: driver ? String(Number(driver.daily_allowance)) : "25000",
  });
  const [active, setActive] = useState(driver?.is_active ?? true);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));

  useEffect(() => {
    if (driver) return;
    api.get<{ data: { id: number; name: string; email: string }[] }>("/erp/fleet/driver-candidates").then((r) => setCandidates(r.data)).catch(() => setCandidates([]));
  }, [driver]);

  async function save() {
    const body = { ...f, vehicle_id: f.vehicle_id || null, licence_expiry: f.licence_expiry || null, is_active: active, ...(driver ? { user_id: undefined } : {}) };
    const r = await run(() => driver ? api.put(`/erp/fleet/drivers/${driver.id}`, body) : api.post("/erp/fleet/drivers", body));
    if (r) { toast(t("fltDriverSaved"), undefined, "ok"); onSaved(); }
  }

  const vehicles: NonNullable<Lookups["vehicles"]> = (lookups?.vehicles ?? []).filter((v) => v.ownership === "owned");

  return (
    <Dialog open wide title={driver ? driver.user?.name ?? t("fltDriver") : t("fltNewDriver")} onClose={onClose} busy={busy} icon="ph-steering-wheel"
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("fltCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
      </>}>
      <FormError error={error} />
      <div className="erp-form-grid">
        {!driver && (
          <Field label={t("fltPerson")} htmlFor="dr-user" required hint={t("fltPersonHint")} error={error?.field("user_id")}>
            <select id="dr-user" className="input" value={f.user_id} onChange={set("user_id")}>
              <option value="">{candidates === null ? "..." : candidates.length ? t("fltChoose") : t("fltNoCandidates")}</option>
              {candidates?.map((c) => <option key={c.id} value={c.id}>{c.name} · {c.email}</option>)}
            </select>
          </Field>
        )}
        <Field label={t("fltLicenceNumber")} htmlFor="dr-lic" required error={error?.field("licence_number")}><input id="dr-lic" className="input" value={f.licence_number} onChange={set("licence_number")} /></Field>
        <Field label={t("fltClass")} htmlFor="dr-cls" error={error?.field("licence_class")}><input id="dr-cls" className="input" value={f.licence_class} onChange={set("licence_class")} /></Field>
        <Field label={t("fltLicenceExpiry")} htmlFor="dr-exp" error={error?.field("licence_expiry")}><input id="dr-exp" type="date" className="input" value={f.licence_expiry} onChange={set("licence_expiry")} /></Field>
        <Field label={t("fltPhone")} htmlFor="dr-ph" error={error?.field("phone")}><input id="dr-ph" className="input" value={f.phone} onChange={set("phone")} /></Field>
        <Field label={t("fltAssignedVehicle")} htmlFor="dr-veh" error={error?.field("vehicle_id")}>
          <select id="dr-veh" className="input" value={f.vehicle_id} onChange={set("vehicle_id")}>
            <option value="">{t("fltNone")}</option>
            {vehicles.map((v) => <option key={v.id} value={v.id}>{v.registration_number}</option>)}
          </select>
        </Field>
        <Field label={t("fltDailyAllowance")} htmlFor="dr-all" error={error?.field("daily_allowance")}><input id="dr-all" type="number" min="0" className="input" value={f.daily_allowance} onChange={set("daily_allowance")} /></Field>
      </div>
      {driver && <Check label={t("fltActive")} checked={active} onChange={setActive} />}
    </Dialog>
  );
}
