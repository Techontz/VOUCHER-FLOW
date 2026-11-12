"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { type Downtime, DOWNTIME_LABEL, km, type Schedule, type ServiceRecord, type Tyre, useFleetLookups } from "@/lib/fleet";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { FormError, type PayMode, PaymentFields, useSubmit } from "@/components/fleet-ui";

type Tab = "schedules" | "services" | "tyres" | "downtime";

export default function MaintenancePage() {
  return <ErpGate module="fleet" permission="fleet.view"><Maintenance /></ErpGate>;
}

function Maintenance() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("schedules");
  return (
    <div className="erp-page">
      <PageHeader title={t("fltMaintenance")} subtitle={t("fltMaintenanceSub")} />
      <Tabs<Tab> label={t("fltMaintenance")} value={tab} onChange={setTab} items={[
        { value: "schedules", label: t("fltSchedules"), icon: "ph-calendar-check" },
        { value: "services", label: t("fltServiceRecords"), icon: "ph-wrench" },
        { value: "tyres", label: t("fltTyres"), icon: "ph-circle-dashed" },
        { value: "downtime", label: t("fltDowntime"), icon: "ph-clock" },
      ]} />
      {tab === "schedules" && <Schedules />}
      {tab === "services" && <Services />}
      {tab === "tyres" && <Tyres />}
      {tab === "downtime" && <Downtimes />}
    </div>
  );
}

function today() { return new Date().toISOString().slice(0, 10); }

function VehicleSelect({ value, onChange, error, id }: { value: string; onChange: (v: string) => void; error?: string; id: string }) {
  const { t } = useApp();
  const { lookups } = useFleetLookups();
  return (
    <Field label={t("fltVehicle")} htmlFor={id} required error={error}>
      <select id={id} className="input" value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">{t("fltChoose")}</option>
        {lookups?.vehicles?.filter((v) => v.ownership === "owned").map((v) => <option key={v.id} value={v.id}>{v.registration_number}</option>)}
      </select>
    </Field>
  );
}

function Schedules() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [rows, setRows] = useState<Schedule[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Schedule | "new" | null>(null);
  const [f, setF] = useState({ vehicle_id: "", title: "", interval_km: "", interval_days: "", last_done_odometer: "", last_done_date: "" });
  const { busy, error: formError, setError: setFormError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: Schedule[] }>("/erp/fleet/schedules").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  function open(s: Schedule | "new") {
    const x = s === "new" ? null : s;
    setFormError(null);
    setF({
      vehicle_id: x ? String(x.vehicle_id) : "", title: x?.title ?? "", interval_km: x?.interval_km ? String(x.interval_km) : "",
      interval_days: x?.interval_days ? String(x.interval_days) : "", last_done_odometer: x?.last_done_odometer ? String(Number(x.last_done_odometer)) : "",
      last_done_date: x?.last_done_date?.slice(0, 10) ?? "",
    });
    setEditing(s);
  }

  async function save() {
    const nil = (v: string) => v || null;
    const body = { vehicle_id: f.vehicle_id, title: f.title, interval_km: nil(f.interval_km), interval_days: nil(f.interval_days), last_done_odometer: nil(f.last_done_odometer), last_done_date: nil(f.last_done_date) };
    const r = await run(() => editing && editing !== "new" ? api.put(`/erp/fleet/schedules/${editing.id}`, body) : api.post("/erp/fleet/schedules", body));
    if (r) { toast(t("fltScheduleSaved"), undefined, "ok"); setEditing(null); load(); }
  }

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const manage = can("fleet.maintenance");

  if (error) return <ErrorState message={error} />;
  if (!rows) return <LoadingBlock />;

  return (
    <GlassCard title={t("fltSchedules")} pad={false}
      action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => open("new")}><Icon name="ph-plus" size={15} /> {t("fltNewSchedule")}</button> : undefined}>
      {rows.length === 0 ? <EmptyState icon="ph-calendar-check" title={t("fltNoSchedules")} /> : (
        <div className="vf-table-wrap"><table className="table vf-table">
          <thead><tr><th>{t("fltVehicle")}</th><th>{t("fltSchedule")}</th><th>{t("fltInterval")}</th><th>{t("fltLastDone")}</th><th>{t("fltNextDue")}</th><th>{t("fltStatus")}</th>{manage && <th />}</tr></thead>
          <tbody>{rows.map((s) => (
            <tr key={s.id}>
              <td><Link href={`/erp/fleet/vehicles/${s.vehicle_id}`}>{s.vehicle?.registration_number}</Link><span className="erp-cell-sub">{km(s.vehicle?.odometer)} km</span></td>
              <td>{s.title}</td>
              <td>{[s.interval_km ? `${km(s.interval_km)} km` : null, s.interval_days ? `${s.interval_days} ${t("fltDays")}` : null].filter(Boolean).join(" / ")}</td>
              <td className="tnum">{[s.last_done_odometer ? `${km(s.last_done_odometer)} km` : null, s.last_done_date ? formatDate(s.last_done_date, locale) : null].filter(Boolean).join(" · ") || "-"}</td>
              <td className="tnum">{[s.next_due_odometer ? `${km(s.next_due_odometer)} km` : null, s.next_due_date ? formatDate(s.next_due_date, locale) : null].filter(Boolean).join(" · ") || "-"}</td>
              <td><Badge tone={s.state === "overdue" ? "bad" : s.state === "due" ? "warn" : "ok"}>{s.state === "overdue" ? t("fltOverdue") : s.state === "due" ? t("fltDueSoon") : t("fltOk")}</Badge></td>
              {manage && <td><button className="btn btn-secondary btn-sm" onClick={() => open(s)}>{t("fltEdit")}</button></td>}
            </tr>
          ))}</tbody>
        </table></div>
      )}
      <Dialog open={editing !== null} wide title={editing === "new" ? t("fltNewSchedule") : t("fltEdit")} onClose={() => setEditing(null)} busy={busy} icon="ph-calendar-check"
        actions={<>
          <button className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
        </>}>
        <FormError error={formError} />
        <div className="erp-form-grid">
          <VehicleSelect id="sc-veh" value={f.vehicle_id} onChange={(v) => setF((p) => ({ ...p, vehicle_id: v }))} error={formError?.field("vehicle_id")} />
          <Field label={t("fltService")} htmlFor="sc-t" required error={formError?.field("title")}><input id="sc-t" className="input" value={f.title} onChange={set("title")} placeholder={t("fltServiceExample")} /></Field>
          <Field label={t("fltEveryKm")} htmlFor="sc-km" error={formError?.field("interval_km")}><input id="sc-km" type="number" min="1" className="input" value={f.interval_km} onChange={set("interval_km")} /></Field>
          <Field label={t("fltEveryDays")} htmlFor="sc-d" error={formError?.field("interval_days")}><input id="sc-d" type="number" min="1" className="input" value={f.interval_days} onChange={set("interval_days")} /></Field>
          <Field label={t("fltLastDoneKm")} htmlFor="sc-lk" error={formError?.field("last_done_odometer")}><input id="sc-lk" type="number" min="0" className="input" value={f.last_done_odometer} onChange={set("last_done_odometer")} /></Field>
          <Field label={t("fltLastDoneDate")} htmlFor="sc-ld" error={formError?.field("last_done_date")}><input id="sc-ld" type="date" className="input" value={f.last_done_date} onChange={set("last_done_date")} /></Field>
        </div>
      </Dialog>
    </GlassCard>
  );
}

function Services() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const { lookups } = useFleetLookups();
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<ServiceRecord> | null>(null);
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [confirm, setConfirm] = useState<{ record: ServiceRecord; act: "post" | "cancel" } | null>(null);
  const [f, setF] = useState({ vehicle_id: "", schedule_id: "", service_date: today(), odometer: "", work_done: "", cost: "", invoice_number: "" });
  const [mode, setMode] = useState<PayMode>("supplier");
  const [accountId, setAccountId] = useState("");
  const [supplierId, setSupplierId] = useState("");
  const { busy, error: formError, setError: setFormError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<Paginated<ServiceRecord>>("/erp/fleet/services", { page }).then(setRows).catch((e) => setError(e.message));
  }, [page]);
  useEffect(load, [load]);
  useEffect(() => { api.get<{ data: Schedule[] }>("/erp/fleet/schedules").then((r) => setSchedules(r.data)).catch(() => setSchedules([])); }, []);

  async function save() {
    const r = await run(() => api.post("/erp/fleet/services", {
      ...f, schedule_id: f.schedule_id || null, odometer: f.odometer || null, cost: f.cost || 0,
      account_id: mode === "account" ? accountId || null : null, supplier_id: mode === "supplier" ? supplierId || null : null,
    }));
    if (r) { toast(t("fltServiceSaved"), undefined, "ok"); setCreating(false); load(); }
  }

  async function act() {
    if (!confirm) return;
    const r = await run(() => api.post<{ message: string }>(`/erp/fleet/services/${confirm.record.id}/${confirm.act}`));
    if (r) { toast(r.message, undefined, "ok"); setConfirm(null); load(); }
  }

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const manage = can("fleet.maintenance");

  if (error) return <ErrorState message={error} />;
  if (!rows) return <LoadingBlock />;

  return (
    <GlassCard title={t("fltServiceRecords")} pad={false}
      action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setCreating(true); }}><Icon name="ph-plus" size={15} /> {t("fltNewService")}</button> : undefined}>
      {rows.data.length === 0 ? <EmptyState icon="ph-wrench" title={t("fltNoServices")} /> : (
        <>
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltService")}</th><th>{t("fltVehicle")}</th><th>{t("fltWorkDone")}</th><th>{t("fltGarage")}</th><th className="num">{t("fltCost")}</th><th>{t("fltStatus")}</th>{manage && <th />}</tr></thead>
            <tbody>{rows.data.map((s) => (
              <tr key={s.id}>
                <td><span className="tnum">{s.number}</span><span className="erp-cell-sub">{formatDate(s.service_date, locale)}{s.odometer ? ` · ${km(s.odometer)} km` : ""}</span></td>
                <td><Link href={`/erp/fleet/vehicles/${s.vehicle_id}`}>{s.vehicle?.registration_number}</Link></td>
                <td>{s.work_done}{s.schedule && <span className="erp-cell-sub">{s.schedule.title}</span>}</td>
                <td>{s.supplier?.name ?? "-"}{s.invoice_number && <span className="erp-cell-sub">{s.invoice_number}</span>}</td>
                <td className="num">{amount(s.cost)}</td>
                <td><Badge tone={s.status === "posted" ? "ok" : s.status === "draft" ? "info" : "neutral"}>{t(s.status === "posted" ? "fltPosted" : s.status === "draft" ? "fltDraft" : "fltStatusCancelled")}</Badge></td>
                {manage && <td>{s.status === "draft" && <span style={{ display: "inline-flex", gap: 6 }}>
                  <button className="btn btn-primary btn-sm" onClick={() => setConfirm({ record: s, act: "post" })}>{t("fltPost")}</button>
                  <button className="btn btn-secondary btn-sm" onClick={() => setConfirm({ record: s, act: "cancel" })}>{t("fltCancelDraft")}</button>
                </span>}</td>}
              </tr>
            ))}</tbody>
          </table></div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <Dialog open={creating} wide title={t("fltNewService")} onClose={() => setCreating(false)} busy={busy} icon="ph-wrench" sub={t("fltServiceDraftHint")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setCreating(false)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
        </>}>
        <FormError error={formError} />
        <div className="erp-form-grid">
          <VehicleSelect id="sv-veh" value={f.vehicle_id} onChange={(v) => setF((p) => ({ ...p, vehicle_id: v, schedule_id: "" }))} error={formError?.field("vehicle_id")} />
          <Field label={t("fltSchedule")} htmlFor="sv-sch" error={formError?.field("schedule_id")}>
            <select id="sv-sch" className="input" value={f.schedule_id} onChange={set("schedule_id")}>
              <option value="">{t("fltNone")}</option>
              {schedules.filter((s) => String(s.vehicle_id) === f.vehicle_id).map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
            </select>
          </Field>
          <Field label={t("fltDate")} htmlFor="sv-date" required error={formError?.field("service_date")}><input id="sv-date" type="date" className="input" value={f.service_date} onChange={set("service_date")} /></Field>
          <Field label={t("fltOdometer")} htmlFor="sv-odo" error={formError?.field("odometer")}><input id="sv-odo" type="number" min="0" className="input" value={f.odometer} onChange={set("odometer")} /></Field>
          <Field label={t("fltCost")} htmlFor="sv-cost" error={formError?.field("cost")}><input id="sv-cost" type="number" min="0" className="input" value={f.cost} onChange={set("cost")} /></Field>
          <Field label={t("fltInvoiceNumber")} htmlFor="sv-inv" error={formError?.field("invoice_number")}><input id="sv-inv" className="input" value={f.invoice_number} onChange={set("invoice_number")} /></Field>
          <PaymentFields idPrefix="sv" lookups={lookups} mode={mode} setMode={setMode} accountId={accountId} setAccountId={setAccountId} supplierId={supplierId} setSupplierId={setSupplierId} error={formError} />
        </div>
        <Field label={t("fltWorkDone")} htmlFor="sv-work" required error={formError?.field("work_done")}><textarea id="sv-work" className="input" rows={2} value={f.work_done} onChange={set("work_done")} /></Field>
      </Dialog>

      <Dialog open={confirm !== null} title={confirm ? fill(t(confirm.act === "post" ? "fltPostServiceQ" : "fltCancelServiceQ"), { number: confirm.record.number }) : ""}
        onClose={() => setConfirm(null)} busy={busy} icon={confirm?.act === "post" ? "ph-check-circle" : "ph-x-circle"} tone={confirm?.act === "post" ? "info" : "warn"}
        sub={confirm?.act === "post" ? t("fltPostServiceSub") : undefined}
        summary={confirm ? [{ label: t("fltVehicle"), value: confirm.record.vehicle?.registration_number ?? "" }, { label: t("fltCost"), value: amount(confirm.record.cost) }] : []}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("fltBack")}</button>
          <button className={confirm?.act === "post" ? "btn btn-primary" : "btn btn-danger"} onClick={act} disabled={busy}>{confirm?.act === "post" ? t("fltPost") : t("fltCancelDraft")}</button>
        </>}>
        <FormError error={formError} />
      </Dialog>
    </GlassCard>
  );
}

function Tyres() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [state, setState] = useState<"fitted" | "removed">("fitted");
  const [rows, setRows] = useState<Tyre[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [fitting, setFitting] = useState(false);
  const [removing, setRemoving] = useState<Tyre | null>(null);
  const [f, setF] = useState({ vehicle_id: "", position: "", serial_number: "", brand: "", size: "", cost: "", fitted_date: today(), fitted_odometer: "" });
  const [r, setR] = useState({ removed_date: today(), removed_odometer: "", removal_reason: "" });
  const { busy, error: formError, setError: setFormError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: Tyre[] }>("/erp/fleet/tyres", { state }).then((x) => setRows(x.data)).catch((e) => setError(e.message));
  }, [state]);
  useEffect(load, [load]);

  async function fit() {
    const res = await run(() => api.post("/erp/fleet/tyres", { ...f, cost: f.cost || 0, fitted_odometer: f.fitted_odometer || null }));
    if (res) { toast(t("fltTyreFitted"), f.serial_number, "ok"); setFitting(false); load(); }
  }
  async function remove() {
    if (!removing) return;
    const res = await run(() => api.post(`/erp/fleet/tyres/${removing.id}/remove`, { ...r, removed_odometer: r.removed_odometer || null }));
    if (res) { toast(t("fltTyreRemoved"), removing.serial_number, "ok"); setRemoving(null); load(); }
  }

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const manage = can("fleet.maintenance");

  if (error) return <ErrorState message={error} />;

  return (
    <GlassCard title={t("fltTyres")} pad={false}
      action={<span style={{ display: "inline-flex", gap: 8, flexWrap: "wrap" }}>
        <select className="input" aria-label={t("fltStatus")} value={state} onChange={(e) => setState(e.target.value as "fitted" | "removed")} style={{ maxWidth: 160 }}>
          <option value="fitted">{t("fltOnVehicle")}</option>
          <option value="removed">{t("fltRemoved")}</option>
        </select>
        {manage && <button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setFitting(true); }}><Icon name="ph-plus" size={15} /> {t("fltFitTyre")}</button>}
      </span>}>
      {!rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-circle-dashed" title={t("fltNoTyres")} /> : (
        <div className="vf-table-wrap"><table className="table vf-table">
          <thead><tr><th>{t("fltVehicle")}</th><th>{t("fltPosition")}</th><th>{t("fltSerial")}</th><th>{t("fltFitted")}</th><th>{t("fltRemoved")}</th><th className="num">{t("fltKmRun")}</th>{manage && state === "fitted" && <th />}</tr></thead>
          <tbody>{rows.map((x) => (
            <tr key={x.id}>
              <td><Link href={`/erp/fleet/vehicles/${x.vehicle_id}`}>{x.vehicle?.registration_number}</Link></td>
              <td>{x.position}</td>
              <td className="tnum">{x.serial_number}<span className="erp-cell-sub">{[x.brand, x.size].filter(Boolean).join(" ")}</span></td>
              <td className="tnum">{formatDate(x.fitted_date, locale)} · {km(x.fitted_odometer)} km</td>
              <td>{x.removed_date ? <>{formatDate(x.removed_date, locale)}<span className="erp-cell-sub">{x.removal_reason}</span></> : "-"}</td>
              <td className="num">{km(Number(x.removed_odometer ?? x.vehicle?.odometer ?? x.fitted_odometer) - Number(x.fitted_odometer))}</td>
              {manage && state === "fitted" && <td><button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setR({ removed_date: today(), removed_odometer: String(Number(x.vehicle?.odometer ?? "")), removal_reason: "" }); setRemoving(x); }}>{t("fltRemoveTyre")}</button></td>}
            </tr>
          ))}</tbody>
        </table></div>
      )}

      <Dialog open={fitting} wide title={t("fltFitTyre")} onClose={() => setFitting(false)} busy={busy} icon="ph-circle-dashed"
        actions={<>
          <button className="btn btn-secondary" onClick={() => setFitting(false)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-primary" onClick={fit} disabled={busy}>{t("fltSave")}</button>
        </>}>
        <FormError error={formError} />
        <div className="erp-form-grid">
          <VehicleSelect id="ty-veh" value={f.vehicle_id} onChange={(v) => setF((p) => ({ ...p, vehicle_id: v }))} error={formError?.field("vehicle_id")} />
          <Field label={t("fltPosition")} htmlFor="ty-pos" required error={formError?.field("position")}><input id="ty-pos" className="input" value={f.position} onChange={set("position")} placeholder={t("fltPositionExample")} /></Field>
          <Field label={t("fltSerial")} htmlFor="ty-ser" required error={formError?.field("serial_number")}><input id="ty-ser" className="input" value={f.serial_number} onChange={set("serial_number")} /></Field>
          <Field label={t("fltBrand")} htmlFor="ty-br" error={formError?.field("brand")}><input id="ty-br" className="input" value={f.brand} onChange={set("brand")} /></Field>
          <Field label={t("fltSize")} htmlFor="ty-sz" error={formError?.field("size")}><input id="ty-sz" className="input" value={f.size} onChange={set("size")} /></Field>
          <Field label={t("fltCost")} htmlFor="ty-c" error={formError?.field("cost")}><input id="ty-c" type="number" min="0" className="input" value={f.cost} onChange={set("cost")} /></Field>
          <Field label={t("fltDate")} htmlFor="ty-d" error={formError?.field("fitted_date")}><input id="ty-d" type="date" className="input" value={f.fitted_date} onChange={set("fitted_date")} /></Field>
          <Field label={t("fltOdometer")} htmlFor="ty-o" hint={t("fltOdometerDefault")} error={formError?.field("fitted_odometer")}><input id="ty-o" type="number" min="0" className="input" value={f.fitted_odometer} onChange={set("fitted_odometer")} /></Field>
        </div>
      </Dialog>

      <Dialog open={removing !== null} title={t("fltRemoveTyre")} onClose={() => setRemoving(null)} busy={busy} icon="ph-circle-dashed" tone="warn"
        summary={removing ? [{ label: t("fltSerial"), value: removing.serial_number }, { label: t("fltPosition"), value: removing.position }] : []}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setRemoving(null)} disabled={busy}>{t("fltBack")}</button>
          <button className="btn btn-primary" onClick={remove} disabled={busy || r.removal_reason.trim().length < 2}>{t("fltRemoveTyre")}</button>
        </>}>
        <FormError error={formError} />
        <div className="erp-form-grid">
          <Field label={t("fltDate")} htmlFor="tr-d" error={formError?.field("removed_date")}><input id="tr-d" type="date" className="input" value={r.removed_date} onChange={(e) => setR({ ...r, removed_date: e.target.value })} /></Field>
          <Field label={t("fltOdometer")} htmlFor="tr-o" error={formError?.field("removed_odometer")}><input id="tr-o" type="number" min="0" className="input" value={r.removed_odometer} onChange={(e) => setR({ ...r, removed_odometer: e.target.value })} /></Field>
        </div>
        <Field label={t("fltReason")} htmlFor="tr-r" required error={formError?.field("removal_reason")}><input id="tr-r" className="input" value={r.removal_reason} onChange={(e) => setR({ ...r, removal_reason: e.target.value })} /></Field>
      </Dialog>
    </GlassCard>
  );
}

function Downtimes() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [rows, setRows] = useState<Downtime[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [ending, setEnding] = useState<Downtime | null>(null);
  const [f, setF] = useState({ vehicle_id: "", reason: "maintenance", description: "" });
  const { busy, error: formError, setError: setFormError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: Downtime[] }>("/erp/fleet/downtimes").then((x) => setRows(x.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  async function start() {
    const res = await run(() => api.post("/erp/fleet/downtimes", f));
    if (res) { toast(t("fltDowntimeStarted"), undefined, "ok"); setStarting(false); load(); }
  }
  async function end() {
    if (!ending) return;
    const res = await run(() => api.post(`/erp/fleet/downtimes/${ending.id}/end`));
    if (res) { toast(t("fltDowntimeEnded"), undefined, "ok"); setEnding(null); load(); }
  }

  const manage = can("fleet.maintenance");
  if (error) return <ErrorState message={error} />;

  return (
    <GlassCard title={t("fltDowntime")} pad={false}
      action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => { setFormError(null); setStarting(true); }}><Icon name="ph-plus" size={15} /> {t("fltStartDowntime")}</button> : undefined}>
      {!rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-clock" title={t("fltNoDowntime")} /> : (
        <div className="vf-table-wrap"><table className="table vf-table">
          <thead><tr><th>{t("fltVehicle")}</th><th>{t("fltReason")}</th><th>{t("fltStarted")}</th><th>{t("fltEnded")}</th><th className="num">{t("fltHours")}</th>{manage && <th />}</tr></thead>
          <tbody>{rows.map((d) => (
            <tr key={d.id}>
              <td><Link href={`/erp/fleet/vehicles/${d.vehicle_id}`}>{d.vehicle?.registration_number}</Link></td>
              <td>{t(DOWNTIME_LABEL[d.reason])}<span className="erp-cell-sub">{d.description}</span></td>
              <td className="tnum">{formatDateTime(d.started_at, locale)}</td>
              <td className="tnum">{d.ended_at ? formatDateTime(d.ended_at, locale) : <Badge tone="warn">{t("fltOpen")}</Badge>}</td>
              <td className="num">{km(d.hours)}</td>
              {manage && <td>{!d.ended_at && <button className="btn btn-primary btn-sm" onClick={() => { setFormError(null); setEnding(d); }}>{t("fltEndDowntime")}</button>}</td>}
            </tr>
          ))}</tbody>
        </table></div>
      )}

      <Dialog open={starting} title={t("fltStartDowntime")} onClose={() => setStarting(false)} busy={busy} icon="ph-clock" tone="warn" sub={t("fltDowntimeHint")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setStarting(false)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-primary" onClick={start} disabled={busy}>{t("fltSave")}</button>
        </>}>
        <FormError error={formError} />
        <VehicleSelect id="dt-veh" value={f.vehicle_id} onChange={(v) => setF((p) => ({ ...p, vehicle_id: v }))} error={formError?.field("vehicle_id")} />
        <Field label={t("fltReason")} htmlFor="dt-r" required error={formError?.field("reason")}>
          <select id="dt-r" className="input" value={f.reason} onChange={(e) => setF((p) => ({ ...p, reason: e.target.value }))}>
            {(Object.keys(DOWNTIME_LABEL) as Downtime["reason"][]).map((k) => <option key={k} value={k}>{t(DOWNTIME_LABEL[k])}</option>)}
          </select>
        </Field>
        <Field label={t("fltDescription")} htmlFor="dt-d" error={formError?.field("description")}><input id="dt-d" className="input" value={f.description} onChange={(e) => setF((p) => ({ ...p, description: e.target.value }))} /></Field>
      </Dialog>

      <Dialog open={ending !== null} title={t("fltEndDowntime")} onClose={() => setEnding(null)} busy={busy} icon="ph-check-circle"
        summary={ending ? [{ label: t("fltVehicle"), value: ending.vehicle?.registration_number ?? "" }, { label: t("fltStarted"), value: formatDateTime(ending.started_at, locale) }] : []}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setEnding(null)} disabled={busy}>{t("fltBack")}</button>
          <button className="btn btn-primary" onClick={end} disabled={busy}>{t("fltEndDowntime")}</button>
        </>}>
        <FormError error={formError} />
      </Dialog>
    </GlassCard>
  );
}
