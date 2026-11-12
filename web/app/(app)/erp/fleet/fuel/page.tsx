"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { ENTRY_LABEL, type EntryStatus, EXPENSE_LABEL, type FuelIssue, type FuelStandard, km, type TripExpense, useFleetLookups } from "@/lib/fleet";
import { Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Tabs, Toolbar } from "@/components/app-ui";
import { Check, ErpGate, FilterChips } from "@/components/erp-ui";
import { EntryBadge, FormError, useSubmit } from "@/components/fleet-ui";

type Tab = "log" | "pending" | "standards";

export default function FuelPage() {
  return <ErpGate module="fleet" permission="fleet.view"><Fuel /></ErpGate>;
}

function Fuel() {
  const { t } = useApp();
  const { can } = useErp();
  const [tab, setTab] = useState<Tab>(can("fleet.approve") ? "pending" : "log");

  return (
    <div className="erp-page">
      <PageHeader title={t("fltFuelLog")} subtitle={t("fltFuelLogSub")} />
      <Tabs<Tab> label={t("fltFuel")} value={tab} onChange={setTab} items={[
        ...(can("fleet.approve") ? [{ value: "pending" as Tab, label: t("fltPendingApprovals"), icon: "ph-hourglass" }] : []),
        { value: "log", label: t("fltFuelLog"), icon: "ph-gas-pump" },
        { value: "standards", label: t("fltStandards"), icon: "ph-gauge" },
      ]} />
      {tab === "log" && <FuelLog />}
      {tab === "pending" && <Pending />}
      {tab === "standards" && <Standards />}
    </div>
  );
}

function FuelLog() {
  const { t, locale } = useApp();
  const [status, setStatus] = useState<EntryStatus | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<FuelIssue> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<FuelIssue>>("/erp/fleet/fuel", { status: status || undefined, q: q || undefined, page }).then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [status, q, page]);

  return (
    <>
      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("fltSearchFuel")} />
        <FilterChips<EntryStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("fltAll") }, ...(["pending", "approved", "rejected"] as EntryStatus[]).map((s) => ({ value: s, label: t(ENTRY_LABEL[s]) })),
        ]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-gas-pump" title={t("fltNoFuel")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("fltDate")}</th><th>{t("fltTrip")}</th><th>{t("fltVehicle")}</th><th>{t("fltStation")}</th><th className="num">{t("fltLitres")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltRecordedBy")}</th><th>{t("fltStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((f) => (
                  <tr key={f.id}>
                    <td className="tnum">{formatDate(f.issue_date, locale)}</td>
                    <td>{f.trip ? <Link href={`/erp/fleet/trips/${f.trip.id}`} className="tnum">{f.trip.number}</Link> : "-"}<span className="erp-cell-sub">{f.trip?.origin} → {f.trip?.destination}</span></td>
                    <td>{f.vehicle?.registration_number ?? "-"}</td>
                    <td>{f.station ?? "-"}{f.receipt_number && <span className="erp-cell-sub">{f.receipt_number}</span>}</td>
                    <td className="num">{km(f.litres)}</td>
                    <td className="num">{amount(f.amount)}</td>
                    <td>{f.recorder?.name ?? "-"}</td>
                    <td><EntryBadge status={f.status} /></td>
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

function Pending() {
  const { t, locale, toast } = useApp();
  const [data, setData] = useState<{ fuel: FuelIssue[]; expenses: TripExpense[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<{ kind: "fuel" | "expenses"; id: number } | null>(null);
  const [reason, setReason] = useState("");
  const { busy, error: actionError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: { fuel: FuelIssue[]; expenses: TripExpense[] } }>("/erp/fleet/pending").then((r) => setData(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  async function decide(kind: "fuel" | "expenses", id: number, decision: "approve" | "reject") {
    const r = await run(() => api.post<{ message: string }>(`/erp/fleet/${kind}/${id}/decision`, { decision, reason: decision === "reject" ? reason : undefined }));
    if (r) { toast(r.message, undefined, "ok"); setRejecting(null); setReason(""); load(); }
  }

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock />;
  if (!data.fuel.length && !data.expenses.length) return <EmptyState icon="ph-check-circle" tone="ok" title={t("fltNothingPending")} />;

  const buttons = (kind: "fuel" | "expenses", id: number) => (
    <span style={{ display: "inline-flex", gap: 6 }}>
      <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => decide(kind, id, "approve")}>{t("fltApprove")}</button>
      <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => setRejecting({ kind, id })}>{t("fltReject")}</button>
    </span>
  );

  return (
    <>
      <FormError error={rejecting ? null : actionError} />
      {data.fuel.length > 0 && (
        <GlassCard title={t("fltFuel")} pad={false}>
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltTrip")}</th><th>{t("fltDate")}</th><th>{t("fltStation")}</th><th className="num">{t("fltLitres")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltRecordedBy")}</th><th /></tr></thead>
            <tbody>{data.fuel.map((f) => (
              <tr key={f.id}>
                <td><Link href={`/erp/fleet/trips/${f.trip_id}`} className="tnum">{f.trip?.number}</Link><span className="erp-cell-sub">{f.vehicle?.registration_number}</span></td>
                <td className="tnum">{formatDate(f.issue_date, locale)}</td>
                <td>{f.station ?? "-"}{f.receipt_number && <span className="erp-cell-sub">{f.receipt_number}</span>}</td>
                <td className="num">{km(f.litres)}</td><td className="num">{amount(f.amount)}</td><td>{f.recorder?.name}</td>
                <td>{buttons("fuel", f.id)}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </GlassCard>
      )}
      {data.expenses.length > 0 && (
        <GlassCard title={t("fltExpenses")} pad={false}>
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltTrip")}</th><th>{t("fltDate")}</th><th>{t("fltExpenseType")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltRecordedBy")}</th><th /></tr></thead>
            <tbody>{data.expenses.map((x) => (
              <tr key={x.id}>
                <td><Link href={`/erp/fleet/trips/${x.trip_id}`} className="tnum">{x.trip?.number}</Link></td>
                <td className="tnum">{formatDate(x.expense_date, locale)}</td>
                <td>{t(EXPENSE_LABEL[x.type])}{x.description && <span className="erp-cell-sub">{x.description}</span>}</td>
                <td className="num">{amount(x.amount)}</td><td>{x.recorder?.name}</td>
                <td>{buttons("expenses", x.id)}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </GlassCard>
      )}
      <Dialog open={rejecting !== null} title={t("fltReject")} onClose={() => setRejecting(null)} busy={busy} icon="ph-x-circle" tone="warn"
        actions={<>
          <button className="btn btn-secondary" onClick={() => setRejecting(null)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-danger" disabled={busy || reason.trim().length < 3} onClick={() => rejecting && decide(rejecting.kind, rejecting.id, "reject")}>{t("fltReject")}</button>
        </>}>
        <Field label={t("fltReason")} htmlFor="pr-reason" required><input id="pr-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>
        <FormError error={actionError} />
      </Dialog>
    </>
  );
}

function Standards() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const { lookups } = useFleetLookups();
  const [rows, setRows] = useState<FuelStandard[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<FuelStandard | "new" | null>(null);
  const [removing, setRemoving] = useState<FuelStandard | null>(null);
  const { busy, error: formError, setError: setFormError, run } = useSubmit();
  const [f, setF] = useState({ vehicle_id: "", origin: "", destination: "", basis: "per_100km", litres: "", tolerance_percent: "10", notes: "" });
  const [active, setActive] = useState(true);

  const load = useCallback(() => {
    api.get<{ data: FuelStandard[] }>("/erp/fleet/standards").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  function open(s: FuelStandard | "new") {
    setFormError(null);
    const x = s === "new" ? null : s;
    setF({
      vehicle_id: x?.vehicle_id ? String(x.vehicle_id) : "", origin: x?.origin ?? "", destination: x?.destination ?? "",
      basis: x?.basis ?? "per_100km", litres: x ? String(Number(x.litres)) : "", tolerance_percent: x ? String(Number(x.tolerance_percent)) : "10", notes: x?.notes ?? "",
    });
    setActive(x?.is_active ?? true);
    setEditing(s);
  }

  async function save() {
    const body = { ...f, vehicle_id: f.vehicle_id || null, origin: f.origin || null, destination: f.destination || null, is_active: active };
    const r = await run(() => editing && editing !== "new" ? api.put(`/erp/fleet/standards/${editing.id}`, body) : api.post("/erp/fleet/standards", body));
    if (r) { toast(t("fltStandardSaved"), undefined, "ok"); setEditing(null); load(); }
  }

  async function remove() {
    if (!removing) return;
    const r = await run(() => api.delete(`/erp/fleet/standards/${removing.id}`));
    if (r) { toast(t("fltStandardRemoved"), undefined, "ok"); setRemoving(null); load(); }
  }

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const manage = can("fleet.manage");

  if (error) return <ErrorState message={error} />;
  if (!rows) return <LoadingBlock />;

  return (
    <>
      <GlassCard title={t("fltStandards")} subtitle={t("fltStandardsSub")} pad={false}
        action={manage ? <button className="btn btn-secondary btn-sm" onClick={() => open("new")}><Icon name="ph-plus" size={15} /> {t("fltNewStandard")}</button> : undefined}>
        {rows.length === 0 ? <EmptyState icon="ph-gauge" title={t("fltNoStandards")} /> : (
          <div className="vf-table-wrap"><table className="table vf-table">
            <thead><tr><th>{t("fltVehicle")}</th><th>{t("fltRoute")}</th><th className="num">{t("fltLitres")}</th><th className="num">{t("fltTolerance")}</th>{manage && <th />}</tr></thead>
            <tbody>{rows.map((s) => (
              <tr key={s.id}>
                <td>{s.vehicle?.registration_number ?? t("fltAnyVehicle")}{!s.is_active && <span className="erp-cell-sub">{t("fltInactive")}</span>}</td>
                <td>{s.origin ? `${s.origin} ↔ ${s.destination}` : t("fltAnyRoute")}{s.notes && <span className="erp-cell-sub">{s.notes}</span>}</td>
                <td className="num">{km(s.litres)} L {s.basis === "per_trip" ? t("fltPerTrip") : t("fltPer100")}</td>
                <td className="num">{Number(s.tolerance_percent)}%</td>
                {manage && <td><span style={{ display: "inline-flex", gap: 6 }}>
                  <button className="btn btn-secondary btn-sm" onClick={() => open(s)}>{t("fltEdit")}</button>
                  <button className="btn btn-secondary btn-sm" onClick={() => setRemoving(s)} aria-label={t("fltRemove")}><Icon name="ph-trash" size={15} /></button>
                </span></td>}
              </tr>
            ))}</tbody>
          </table></div>
        )}
      </GlassCard>

      <Dialog open={editing !== null} wide title={editing === "new" ? t("fltNewStandard") : t("fltEdit")} onClose={() => setEditing(null)} busy={busy} icon="ph-gauge"
        actions={<>
          <button className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
        </>}>
        <FormError error={formError} />
        <p className="erp-muted">{t("fltStandardHint")}</p>
        <div className="erp-form-grid">
          <Field label={t("fltVehicle")} htmlFor="st-veh" error={formError?.field("vehicle_id")}>
            <select id="st-veh" className="input" value={f.vehicle_id} onChange={set("vehicle_id")}>
              <option value="">{t("fltAnyVehicle")}</option>
              {lookups?.vehicles?.map((v) => <option key={v.id} value={v.id}>{v.registration_number}</option>)}
            </select>
          </Field>
          <Field label={t("fltOrigin")} htmlFor="st-o" error={formError?.field("origin")}><input id="st-o" className="input" value={f.origin} onChange={set("origin")} /></Field>
          <Field label={t("fltDestination")} htmlFor="st-d" error={formError?.field("destination")}><input id="st-d" className="input" value={f.destination} onChange={set("destination")} /></Field>
          <Field label={t("fltBasis")} htmlFor="st-b" error={formError?.field("basis")}>
            <select id="st-b" className="input" value={f.basis} onChange={set("basis")}>
              <option value="per_100km">{t("fltPer100")}</option>
              <option value="per_trip">{t("fltPerTrip")}</option>
            </select>
          </Field>
          <Field label={t("fltLitres")} htmlFor="st-l" required error={formError?.field("litres")}><input id="st-l" type="number" min="0" step="0.1" className="input" value={f.litres} onChange={set("litres")} /></Field>
          <Field label={t("fltTolerancePct")} htmlFor="st-t" error={formError?.field("tolerance_percent")}><input id="st-t" type="number" min="0" max="100" className="input" value={f.tolerance_percent} onChange={set("tolerance_percent")} /></Field>
          <Field label={t("fltNotes")} htmlFor="st-n" error={formError?.field("notes")}><input id="st-n" className="input" value={f.notes} onChange={set("notes")} /></Field>
        </div>
        <Check label={t("fltActive")} checked={active} onChange={setActive} />
      </Dialog>

      <Dialog open={removing !== null} title={t("fltRemoveStandardQ")} onClose={() => setRemoving(null)} busy={busy} icon="ph-trash" tone="warn" sub={t("fltRemoveStandardSub")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setRemoving(null)} disabled={busy}>{t("fltBack")}</button>
          <button className="btn btn-danger" onClick={remove} disabled={busy}>{t("fltRemove")}</button>
        </>}>
        <FormError error={formError} />
      </Dialog>
    </>
  );
}
