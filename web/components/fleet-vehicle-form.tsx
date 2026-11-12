"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { HIRE_BASIS_LABEL, type Lookups, type Vehicle, VEHICLE_TYPES } from "@/lib/fleet";
import { Dialog, Field } from "@/components/ui";
import { Check } from "@/components/erp-ui";
import { FormError, useMoney, useSubmit } from "@/components/fleet-ui";

const num = (v: string | null | undefined) => (v === null || v === undefined || Number(v) === 0 ? "" : String(Number(v)));

/** Registers a vehicle or edits one: papers, hire terms and the monthly fixed costs trips absorb. */
export function VehicleFormDialog({ vehicle, onClose, onSaved }: { vehicle?: Vehicle | null; onClose: () => void; onSaved: (v: Vehicle) => void }) {
  const { t, toast } = useApp();
  const fmt = useMoney();
  const { busy, error, run } = useSubmit();
  const [suppliers, setSuppliers] = useState<Lookups["suppliers"]>([]);
  const [f, setF] = useState({
    registration_number: vehicle?.registration_number ?? "", make: vehicle?.make ?? "", model: vehicle?.model ?? "",
    type: vehicle?.type ?? "truck", year: vehicle?.year ? String(vehicle.year) : "", capacity: num(vehicle?.capacity),
    capacity_unit: vehicle?.capacity_unit ?? "tonnes", ownership: vehicle?.ownership ?? "owned",
    supplier_id: vehicle?.supplier_id ? String(vehicle.supplier_id) : "", hire_rate_basis: vehicle?.hire_rate_basis ?? "per_trip",
    hire_rate: num(vehicle?.hire_rate), odometer: num(vehicle?.odometer),
    insurer: vehicle?.insurer ?? "", insurance_policy_number: vehicle?.insurance_policy_number ?? "", insurance_expiry: vehicle?.insurance_expiry?.slice(0, 10) ?? "",
    road_licence_number: vehicle?.road_licence_number ?? "", road_licence_expiry: vehicle?.road_licence_expiry?.slice(0, 10) ?? "",
    monthly_insurance: num(vehicle?.monthly_insurance), monthly_licence: num(vehicle?.monthly_licence),
    monthly_depreciation: num(vehicle?.monthly_depreciation), monthly_other_fixed: num(vehicle?.monthly_other_fixed),
    allocation_basis: vehicle?.allocation_basis ?? "days", expected_monthly_km: num(vehicle?.expected_monthly_km), notes: vehicle?.notes ?? "",
  });
  const [wet, setWet] = useState(vehicle?.hire_includes_fuel ?? false);
  const [active, setActive] = useState(vehicle?.is_active ?? true);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const hired = f.ownership === "hired";

  useEffect(() => {
    api.get<{ data: Lookups }>("/erp/fleet/lookups").then((r) => setSuppliers(r.data.suppliers)).catch(() => setSuppliers([]));
  }, []);

  async function save() {
    const nil = (v: string) => (v === "" ? null : v);
    const body = {
      ...Object.fromEntries(Object.entries(f).map(([k, v]) => [k, nil(v)])),
      hire_includes_fuel: hired && wet, is_active: active,
    };
    const r = await run(() => vehicle
      ? api.put<{ data: Vehicle }>(`/erp/fleet/vehicles/${vehicle.id}`, body)
      : api.post<{ data: Vehicle }>("/erp/fleet/vehicles", body));
    if (r) { toast(t("fltVehicleSaved"), r.data.registration_number, "ok"); onSaved(r.data); }
  }

  const fixed = ["monthly_insurance", "monthly_licence", "monthly_depreciation", "monthly_other_fixed"].reduce((s, k) => s + Number(f[k as keyof typeof f] || 0), 0);
  const field = (k: keyof typeof f, label: string, type = "text", required = false) => (
    <Field label={label} htmlFor={`vf-${k}`} required={required} error={error?.field(k)}>
      <input id={`vf-${k}`} type={type} className="input" value={f[k]} onChange={set(k)} min={type === "number" ? 0 : undefined} />
    </Field>
  );

  return (
    <Dialog open wide title={vehicle ? vehicle.registration_number : t("fltNewVehicle")} onClose={onClose} busy={busy} icon="ph-truck"
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("fltCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
      </>}>
      <FormError error={error} />
      <div className="erp-form-grid">
        {field("registration_number", t("fltRegistration"), "text", true)}
        <Field label={t("fltType")} htmlFor="vf-type" error={error?.field("type")}>
          <select id="vf-type" className="input" value={f.type} onChange={set("type")}>
            {VEHICLE_TYPES.map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </Field>
        {field("make", t("fltMake"))}
        {field("model", t("fltModel"))}
        {field("year", t("fltYear"), "number")}
        {field("capacity", t("fltCapacityTonnes"), "number")}
        {field("odometer", t("fltOdometer"), "number")}
        <Field label={t("fltOwnership")} htmlFor="vf-own" error={error?.field("ownership")}>
          <select id="vf-own" className="input" value={f.ownership} onChange={set("ownership")}>
            <option value="owned">{t("fltOwned")}</option>
            <option value="hired">{t("fltHired")}</option>
          </select>
        </Field>
        {hired && (
          <>
            <Field label={t("fltOwner")} htmlFor="vf-sup" required error={error?.field("supplier_id")}>
              <select id="vf-sup" className="input" value={f.supplier_id} onChange={set("supplier_id")}>
                <option value="">{t("fltChoose")}</option>
                {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </Field>
            <Field label={t("fltHireBasis")} htmlFor="vf-basis" required error={error?.field("hire_rate_basis")}>
              <select id="vf-basis" className="input" value={f.hire_rate_basis} onChange={set("hire_rate_basis")}>
                {Object.keys(HIRE_BASIS_LABEL).map((b) => <option key={b} value={b}>{t(HIRE_BASIS_LABEL[b])}</option>)}
              </select>
            </Field>
            {field("hire_rate", t("fltHireRate"), "number", true)}
          </>
        )}
      </div>
      {hired && <Check label={t("fltWetHire")} hint={t("fltWetHireHint")} checked={wet} onChange={setWet} />}

      <h3 className="erp-muted" style={{ marginTop: 16 }}>{t("fltPapers")}</h3>
      <div className="erp-form-grid">
        {field("insurer", t("fltInsurer"))}
        {field("insurance_policy_number", t("fltPolicyNumber"))}
        {field("insurance_expiry", t("fltInsuranceExpiry"), "date")}
        {field("road_licence_number", t("fltRoadLicenceNumber"))}
        {field("road_licence_expiry", t("fltRoadLicenceExpiry"), "date")}
      </div>

      {!hired && (
        <>
          <h3 className="erp-muted" style={{ marginTop: 16 }}>{t("fltFixedCosts")}</h3>
          <div className="erp-form-grid">
            {field("monthly_insurance", t("fltMonthlyInsurance"), "number")}
            {field("monthly_licence", t("fltMonthlyLicence"), "number")}
            {field("monthly_depreciation", t("fltMonthlyDepreciation"), "number")}
            {field("monthly_other_fixed", t("fltMonthlyOther"), "number")}
            <Field label={t("fltAllocationBasis")} htmlFor="vf-alloc" error={error?.field("allocation_basis")}>
              <select id="vf-alloc" className="input" value={f.allocation_basis} onChange={set("allocation_basis")}>
                <option value="days">{t("fltByDays")}</option>
                <option value="km">{t("fltByKm")}</option>
              </select>
            </Field>
            {f.allocation_basis === "km" && field("expected_monthly_km", t("fltExpectedKm"), "number", true)}
          </div>
          <p className="erp-muted">{t("fltFixedCostsHint")} <strong className="tnum">{fmt(fixed)}</strong></p>
        </>
      )}
      {field("notes", t("fltNotes"))}
      {vehicle && <Check label={t("fltActive")} checked={active} onChange={setActive} />}
    </Dialog>
  );
}
