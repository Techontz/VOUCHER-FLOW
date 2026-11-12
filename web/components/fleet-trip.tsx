"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import {
  COST_OPTION_HINT, COST_OPTION_LABEL, COST_OPTIONS, type CostOption, EXPENSE_LABEL, HIRE_BASIS_LABEL, km, localInput,
  type Trip, useFleetLookups,
} from "@/lib/fleet";
import { Badge, Banner, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { fill } from "@/components/erp-ui";
import { EntryBadge, ExpenseDialog, FormError, FuelDialog, Row, TripStatusBadge, useMoney, useSubmit } from "@/components/fleet-ui";

type Action = "dispatch" | "complete" | "close" | "cancel";

/**
 * One trip, for the fleet office or (mine) for the driver who drives it.
 * Every button here maps to one endpoint, shown only when the caller's
 * permissions and the trip's status allow it.
 */
export function TripDetail({ id, mine = false }: { id: string; mine?: boolean }) {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const fmt = useMoney();
  const base = mine ? "/erp/fleet/my-trips" : "/erp/fleet/trips";
  const { lookups } = useFleetLookups(mine);
  const [trip, setTrip] = useState<Trip | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<Action | null>(null);
  const [form, setForm] = useState({ odometer: "", at: "", text: "" });
  const [entryDialog, setEntryDialog] = useState<"fuel" | "expense" | null>(null);
  const [rejecting, setRejecting] = useState<{ kind: "fuel" | "expenses"; id: number } | null>(null);
  const { busy, error: actionError, setError: setActionError, run } = useSubmit();

  const load = useCallback(() => {
    api.get<{ data: Trip }>(`${base}/${id}`).then((r) => setTrip(r.data)).catch((e) => setError(e.message));
  }, [base, id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!trip) return <LoadingBlock rows={6} />;

  const open = trip.status !== "closed" && trip.status !== "cancelled";
  const costsAllowed = open && trip.cost_option !== "customer_vehicle";
  const wetHire = trip.cost_option === "hired" && !!trip.vehicle?.hire_includes_fuel;
  const mayFuel = costsAllowed && !wetHire && (mine || can("fleet.fuel"));
  const mayExpense = costsAllowed && (mine || can("fleet.expenses"));
  const mayApprove = !mine && can("fleet.approve") && open;
  const mayRun = !mine && can("fleet.trips");
  const costs = trip.costs;

  function openAction(a: Action) {
    setActionError(null);
    setForm({
      odometer: a === "dispatch" ? String(trip?.vehicle?.odometer ?? "") : a === "complete" ? "" : "",
      at: localInput(), text: "",
    });
    setAction(a);
  }

  async function act() {
    if (!action || !trip) return;
    const body = action === "dispatch" ? { odometer_out: form.odometer || null, at: form.at || null }
      : action === "complete" ? { odometer_in: form.odometer || null, at: form.at || null }
        : action === "close" ? { note: form.text || null } : { reason: form.text };
    const r = await run(() => api.post<{ message: string; data: Trip }>(`/erp/fleet/trips/${trip.id}/${action}`, body));
    if (r) { toast(r.message, undefined, "ok"); setTrip(r.data); setAction(null); }
  }

  async function decide(kind: "fuel" | "expenses", entryId: number, decision: "approve" | "reject", reason?: string) {
    const r = await run(() => api.post<{ message: string }>(`/erp/fleet/${kind}/${entryId}/decision`, { decision, reason }));
    if (r) { toast(r.message, undefined, "ok"); setRejecting(null); load(); }
  }

  const route = `${trip.origin} → ${trip.destination}`;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={mine ? "/erp/fleet/my-trips" : "/erp/fleet/trips"} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {mine ? t("fltMyTrips") : t("fltTrips")}</Link>}
        kicker={t(COST_OPTION_LABEL[trip.cost_option])}
        title={<span className="erp-inline-icon tnum"><Icon name="ph-path" size={32} /> {trip.number}</span>}
        subtitle={<>{route} · {formatDateTime(trip.planned_start, locale)}</>}
        actions={<>
          <TripStatusBadge status={trip.status} />
          {mayRun && trip.status === "planned" && <Link className="btn btn-secondary" href={`/erp/fleet/trips/${trip.id}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("fltEdit")}</Link>}
          {mayRun && trip.status === "planned" && <button className="btn btn-primary" onClick={() => openAction("dispatch")}><Icon name="ph-truck" size={18} /> {t("fltDispatch")}</button>}
          {mayRun && trip.status === "dispatched" && <button className="btn btn-primary" onClick={() => openAction("complete")}><Icon name="ph-flag-checkered" size={18} /> {t("fltComplete")}</button>}
          {mayRun && trip.status === "completed" && <button className="btn btn-primary" onClick={() => openAction("close")}><Icon name="ph-check-circle" size={18} /> {t("fltCloseTrip")}</button>}
          {mayRun && (trip.status === "planned" || trip.status === "dispatched") && <button className="btn btn-secondary" onClick={() => openAction("cancel")}>{t("fltCancelTrip")}</button>}
        </>}
      />

      {trip.fuel_over_standard && trip.status === "completed" && (
        <Banner tone="warn" icon="ph-gas-pump" title={t("fltOverStandardTitle")}>
          {fill(t("fltOverStandardBody"), { actual: km(trip.actual_litres), standard: km(trip.standard_litres), pct: Number(trip.fuel_variance_percent ?? 0).toFixed(1) })}
          {!can("fleet.approve") && !mine && <> {t("fltNeedsApprover")}</>}
        </Banner>
      )}
      {trip.status === "cancelled" && trip.cancel_reason && <Banner tone="warn" icon="ph-x-circle" title={t("fltStatusCancelled")}>{trip.cancel_reason}</Banner>}

      <div className="erp-grid">
        <GlassCard title={t("fltTripDetails")}>
          <dl className="erp-review">
            <Row label={t("fltVehicle")}>{trip.vehicle ? (mine ? trip.vehicle.registration_number : <Link href={`/erp/fleet/vehicles/${trip.vehicle.id}`}>{trip.vehicle.registration_number}</Link>) : (trip.external_vehicle ?? t("fltCustomerTruck"))}</Row>
            <Row label={t("fltDriver")}>{trip.driver?.user?.name ?? "-"}</Row>
            <Row label={t("fltCustomer")}>{trip.customer?.name ?? "-"}</Row>
            {trip.source_reference && <Row label={t("fltSourceDoc")}>{trip.source_reference}{trip.source_type ? <span className="erp-cell-sub">{trip.source_type.replace(/_/g, " ")}</span> : null}</Row>}
            {trip.cargo_description && <Row label={t("fltCargo")}>{trip.cargo_description}</Row>}
            <Row label={t("fltDistance")}>{km(costs?.distance_km ?? trip.distance_km)} km</Row>
            <Row label={t("fltOdometerOutIn")}>{trip.odometer_out ? km(trip.odometer_out) : "-"} / {trip.odometer_in ? km(trip.odometer_in) : "-"}</Row>
            <Row label={t("fltActualTimes")}>{formatDateTime(trip.actual_start, locale)} · {formatDateTime(trip.actual_end, locale)}</Row>
            {trip.cost_option === "hired" && trip.vehicle && <Row label={t("fltHireTerms")}>{trip.vehicle.hire_rate_basis ? `${fmt(trip.vehicle.hire_rate)} ${t(HIRE_BASIS_LABEL[trip.vehicle.hire_rate_basis])}` : "-"}{wetHire ? ` · ${t("fltWetHire")}` : ""}</Row>}
            {trip.notes && <Row label={t("fltNotes")}>{trip.notes}</Row>}
          </dl>
        </GlassCard>

        <GlassCard title={t("fltCosts")}>
          {costs && (
            <dl className="erp-review">
              <Row label={t("fltRevenue")}><span className="tnum">{fmt(costs.revenue)}</span></Row>
              <Row label={t("fltFuel")}><span className="tnum">{fmt(costs.fuel)}</span></Row>
              <Row label={t("fltExpenses")}><span className="tnum">{fmt(costs.expenses)}</span></Row>
              {costs.hire > 0 && <Row label={t("fltHire")}><span className="tnum">{fmt(costs.hire)}</span></Row>}
              <Row label={t("fltFixedShare")}><span className="tnum">{fmt(costs.fixed)}</span>{trip.status !== "closed" && trip.cost_option !== "hired" && <span className="erp-cell-sub">{t("fltFixedAtClose")}</span>}</Row>
              <Row label={t("fltTotalCost")}><strong className="tnum">{fmt(costs.total_cost)}</strong></Row>
              <Row label={t("fltProfit")}><strong className="tnum" style={{ color: costs.profit < 0 ? "var(--st-bad-fg)" : "var(--st-ok-fg)" }}>{fmt(costs.profit)}</strong></Row>
              {costs.pending > 0 && <Row label={t("fltPendingAmount")}><Badge tone="warn">{fmt(costs.pending)}</Badge></Row>}
            </dl>
          )}
        </GlassCard>

        <GlassCard title={t("fltFuelVsStandard")}>
          <dl className="erp-review">
            <Row label={t("fltStandard")}>{trip.standard ? `${km(trip.standard.litres)} L ${trip.standard.basis === "per_trip" ? t("fltPerTrip") : t("fltPer100")}` : t("fltNoStandard")}</Row>
            <Row label={t("fltAllowedLitres")}>{trip.standard_litres ? `${km(trip.standard_litres)} L` : "-"}</Row>
            <Row label={t("fltActualLitres")}>{trip.actual_litres ? `${km(trip.actual_litres)} L` : "-"}</Row>
            <Row label={t("fltVariance")}>
              {trip.fuel_variance_percent !== null
                ? <Badge tone={trip.fuel_over_standard ? "bad" : "ok"}>{Number(trip.fuel_variance_percent) > 0 ? "+" : ""}{Number(trip.fuel_variance_percent).toFixed(1)}% · {t("fltTolerance")} {Number(trip.fuel_tolerance_percent ?? 0)}%</Badge>
                : "-"}
            </Row>
            {trip.variance_approved_at && <Row label={t("fltVarianceApproved")}>{trip.variance_approver?.name} · {formatDateTime(trip.variance_approved_at, locale)}{trip.variance_note ? <span className="erp-cell-sub">{trip.variance_note}</span> : null}</Row>}
          </dl>
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("fltFuel")} pad={false}
          action={mayFuel ? <button className="btn btn-secondary btn-sm" onClick={() => setEntryDialog("fuel")}><Icon name="ph-plus" size={15} /> {t("fltRecordFuel")}</button> : undefined}>
          {!trip.fuel_issues?.length ? <EmptyState icon="ph-gas-pump" title={wetHire ? t("fltWetHireNoFuel") : t("fltNoFuel")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltDate")}</th><th>{t("fltStation")}</th><th className="num">{t("fltLitres")}</th><th className="num">{t("fltPricePerLitre")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltPaidHow")}</th><th>{t("fltRecordedBy")}</th><th>{t("fltStatus")}</th>{mayApprove && <th />}</tr></thead>
                <tbody>
                  {trip.fuel_issues.map((f) => (
                    <tr key={f.id}>
                      <td className="tnum">{formatDate(f.issue_date, locale)}</td>
                      <td>{f.station ?? "-"}{f.receipt_number && <span className="erp-cell-sub">{f.receipt_number}</span>}</td>
                      <td className="num">{km(f.litres)}</td>
                      <td className="num">{amount(f.price_per_litre)}</td>
                      <td className="num">{amount(f.amount)}</td>
                      <td>{f.account ? `${f.account.code} ${f.account.name}` : f.supplier?.name}</td>
                      <td>{f.recorder?.name ?? "-"}</td>
                      <td><EntryBadge status={f.status} />{f.rejection_reason && <span className="erp-cell-sub">{f.rejection_reason}</span>}</td>
                      {mayApprove && <td>{f.status === "pending" && <EntryActions busy={busy} onApprove={() => decide("fuel", f.id, "approve")} onReject={() => setRejecting({ kind: "fuel", id: f.id })} />}</td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("fltExpenses")} pad={false}
          action={mayExpense ? <button className="btn btn-secondary btn-sm" onClick={() => setEntryDialog("expense")}><Icon name="ph-plus" size={15} /> {t("fltRecordExpense")}</button> : undefined}>
          {!trip.expenses?.length ? <EmptyState icon="ph-receipt" title={t("fltNoExpenses")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltDate")}</th><th>{t("fltExpenseType")}</th><th className="num">{t("fltQuantity")}</th><th className="num">{t("fltRate")}</th><th className="num">{t("fltAmount")}</th><th>{t("fltPaidHow")}</th><th>{t("fltStatus")}</th>{mayApprove && <th />}</tr></thead>
                <tbody>
                  {trip.expenses.map((x) => (
                    <tr key={x.id}>
                      <td className="tnum">{formatDate(x.expense_date, locale)}</td>
                      <td>{t(EXPENSE_LABEL[x.type])}{x.description && <span className="erp-cell-sub">{x.description}</span>}</td>
                      <td className="num">{km(x.quantity)}</td>
                      <td className="num">{amount(x.rate)}</td>
                      <td className="num">{amount(x.amount)}</td>
                      <td>{x.account ? `${x.account.code} ${x.account.name}` : x.supplier?.name}</td>
                      <td><EntryBadge status={x.status} />{x.rejection_reason && <span className="erp-cell-sub">{x.rejection_reason}</span>}</td>
                      {mayApprove && <td>{x.status === "pending" && <EntryActions busy={busy} onApprove={() => decide("expenses", x.id, "approve")} onReject={() => setRejecting({ kind: "expenses", id: x.id })} />}</td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        {!mine && (trip.allocations?.length ?? 0) > 0 && (
          <GlassCard title={t("fltAllocations")} pad={false}>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltPeriod")}</th><th className="num">{t("fltShare")}</th><th className="num">{t("fltAmount")}</th></tr></thead>
                <tbody>
                  {trip.allocations!.map((a) => (
                    <tr key={a.id}><td className="tnum">{a.period}</td><td className="num">{km(a.share)} / {km(a.period_units)} {a.basis === "km" ? "km" : t("fltDays")}</td><td className="num">{amount(a.amount)}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          </GlassCard>
        )}

        {!mine && (trip.journals?.length ?? 0) > 0 && (
          <GlassCard className="erp-span-2" title={t("fltJournals")} pad={false}>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("fltJournal")}</th><th>{t("fltAccount")}</th><th className="num">{t("fltDebit")}</th><th className="num">{t("fltCredit")}</th></tr></thead>
                <tbody>
                  {trip.journals!.flatMap((j) => (j.lines ?? []).map((l, i) => (
                    <tr key={`${j.id}-${l.id}`}>
                      <td className="tnum">{i === 0 ? j.number : ""}</td>
                      <td>{l.account?.code} {l.account?.name}{l.description && <span className="erp-cell-sub">{l.description}</span>}</td>
                      <td className="num">{Number(l.debit) ? amount(l.debit) : ""}</td>
                      <td className="num">{Number(l.credit) ? amount(l.credit) : ""}</td>
                    </tr>
                  )))}
                </tbody>
              </table>
            </div>
          </GlassCard>
        )}

        {!mine && (trip.timeline?.length ?? 0) > 0 && (
          <GlassCard title={t("fltTimeline")}>
            <ol className="erp-review" style={{ listStyle: "none", padding: 0, gridTemplateColumns: "minmax(0,1fr)" }}>
              {trip.timeline!.map((e) => (
                <li key={e.id}><span>{e.description}</span><span className="erp-cell-sub">{e.actor_name} · {formatDateTime(e.created_at, locale)}</span></li>
              ))}
            </ol>
          </GlassCard>
        )}
      </div>

      <FuelDialog key={`fuel-${entryDialog === "fuel"}`} open={entryDialog === "fuel"} onClose={() => setEntryDialog(null)} onSaved={load} tripId={trip.id} base={base} lookups={lookups} />
      <ExpenseDialog key={`exp-${entryDialog === "expense"}`} open={entryDialog === "expense"} onClose={() => setEntryDialog(null)} onSaved={load} tripId={trip.id} base={base} lookups={lookups} dailyAllowance={trip.driver?.daily_allowance} />

      <Dialog open={rejecting !== null} title={t("fltReject")} onClose={() => setRejecting(null)} busy={busy} icon="ph-x-circle" tone="warn"
        actions={<>
          <button className="btn btn-secondary" onClick={() => setRejecting(null)} disabled={busy}>{t("fltCancel")}</button>
          <button className="btn btn-danger" disabled={busy || form.text.trim().length < 3} onClick={() => rejecting && decide(rejecting.kind, rejecting.id, "reject", form.text)}>{t("fltReject")}</button>
        </>}>
        <Field label={t("fltReason")} htmlFor="rej-reason" required>
          <input id="rej-reason" className="input" value={form.text} onChange={(e) => setForm({ ...form, text: e.target.value })} autoFocus />
        </Field>
        <FormError error={actionError} />
      </Dialog>

      <Dialog open={action !== null} onClose={() => setAction(null)} busy={busy}
        icon={action === "cancel" ? "ph-x-circle" : action === "close" ? "ph-check-circle" : "ph-truck"} tone={action === "cancel" ? "warn" : "info"}
        title={action ? fill(t(action === "dispatch" ? "fltDispatchQ" : action === "complete" ? "fltCompleteQ" : action === "close" ? "fltCloseQ" : "fltCancelQ"), { number: trip.number }) : ""}
        sub={action === "close" ? t("fltCloseSub") : undefined}
        summary={[
          { label: t("fltRoute"), value: route },
          { label: t("fltVehicle"), value: trip.vehicle?.registration_number ?? trip.external_vehicle ?? "-" },
          ...(action === "close" && costs ? [{ label: t("fltTotalCost"), value: fmt(costs.total_cost) }, { label: t("fltRevenue"), value: fmt(costs.revenue) }] : []),
        ]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setAction(null)} disabled={busy}>{t("fltBack")}</button>
          <button className={action === "cancel" ? "btn btn-danger" : "btn btn-primary"} onClick={act}
            disabled={busy || (action === "cancel" && form.text.trim().length < 3)}>
            {action === "dispatch" ? t("fltDispatch") : action === "complete" ? t("fltComplete") : action === "close" ? t("fltCloseTrip") : t("fltCancelTrip")}
          </button>
        </>}>
        {(action === "dispatch" || action === "complete") && (
          <div className="erp-form-grid">
            {trip.vehicle && (
              <Field label={action === "dispatch" ? t("fltOdometerOut") : t("fltOdometerIn")} htmlFor="act-odo" required={action === "complete" && trip.cost_option !== "hired"}
                error={actionError?.field(action === "dispatch" ? "odometer_out" : "odometer_in")}>
                <input id="act-odo" type="number" min="0" className="input" value={form.odometer} onChange={(e) => setForm({ ...form, odometer: e.target.value })} />
              </Field>
            )}
            <Field label={action === "dispatch" ? t("fltDepartedAt") : t("fltReturnedAt")} htmlFor="act-at" error={actionError?.field("at")}>
              <input id="act-at" type="datetime-local" className="input" value={form.at} onChange={(e) => setForm({ ...form, at: e.target.value })} />
            </Field>
          </div>
        )}
        {action === "close" && trip.fuel_over_standard && (
          <Field label={t("fltVarianceNote")} htmlFor="act-note" hint={t("fltVarianceNoteHint")}>
            <input id="act-note" className="input" value={form.text} onChange={(e) => setForm({ ...form, text: e.target.value })} />
          </Field>
        )}
        {action === "cancel" && (
          <Field label={t("fltReason")} htmlFor="act-reason" required>
            <input id="act-reason" className="input" value={form.text} onChange={(e) => setForm({ ...form, text: e.target.value })} autoFocus />
          </Field>
        )}
        <FormError error={actionError} />
      </Dialog>
    </div>
  );
}

function EntryActions({ busy, onApprove, onReject }: { busy: boolean; onApprove: () => void; onReject: () => void }) {
  const { t } = useApp();
  return (
    <span style={{ display: "inline-flex", gap: 6 }}>
      <button className="btn btn-primary btn-sm" disabled={busy} onClick={onApprove}>{t("fltApprove")}</button>
      <button className="btn btn-secondary btn-sm" disabled={busy} onClick={onReject}>{t("fltReject")}</button>
    </span>
  );
}

/** Plans a trip, or edits one still planned. */
export function TripForm({ trip }: { trip?: Trip }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const { lookups, error: lookupError } = useFleetLookups();
  const { busy, error, run } = useSubmit();
  const [f, setF] = useState({
    cost_option: (trip?.cost_option ?? "charged") as CostOption,
    vehicle_id: trip?.vehicle_id ? String(trip.vehicle_id) : "",
    driver_id: trip?.driver_id ? String(trip.driver_id) : "",
    external_vehicle: trip?.external_vehicle ?? "",
    customer_id: trip?.customer_id ? String(trip.customer_id) : "",
    origin: trip?.origin ?? "Dar es Salaam",
    destination: trip?.destination ?? "",
    distance_km: trip?.distance_km ? String(Number(trip.distance_km)) : "",
    planned_start: localInput(trip?.planned_start),
    planned_end: trip?.planned_end ? localInput(trip.planned_end) : "",
    transport_charge: trip && Number(trip.transport_charge) ? String(Number(trip.transport_charge)) : "",
    source_type: trip?.source_type ?? "",
    source_id: trip?.source_id ? String(trip.source_id) : "",
    source_reference: trip?.source_reference ?? "",
    cargo_description: trip?.cargo_description ?? "",
    notes: trip?.notes ?? "",
  });
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((prev) => ({ ...prev, [k]: e.target.value }));

  if (lookupError) return <ErrorState message={lookupError} />;
  if (!lookups) return <LoadingBlock rows={6} />;

  const option = f.cost_option;
  const vehicles = (lookups.vehicles ?? []).filter((v) => (option === "hired" ? v.ownership === "hired" : v.ownership === "owned"));
  const charged = option === "charged" || option === "hired";

  function pickVehicle(id: string) {
    const assigned = lookups?.drivers?.find((d) => String(d.vehicle_id) === id);
    setF((prev) => ({ ...prev, vehicle_id: id, driver_id: assigned && !prev.driver_id ? String(assigned.id) : prev.driver_id }));
  }

  async function save() {
    const body = {
      ...f,
      vehicle_id: option === "customer_vehicle" ? null : f.vehicle_id || null,
      driver_id: option === "customer_vehicle" ? null : f.driver_id || null,
      customer_id: f.customer_id || null,
      distance_km: f.distance_km || 0,
      planned_end: f.planned_end || null,
      transport_charge: charged ? f.transport_charge || 0 : 0,
      source_type: f.source_type || null, source_id: f.source_id || null,
    };
    const r = await run(() => trip
      ? api.put<{ data: Trip }>(`/erp/fleet/trips/${trip.id}`, body)
      : api.post<{ data: Trip }>("/erp/fleet/trips", body));
    if (r) {
      toast(trip ? t("fltTripSaved") : t("fltTripPlanned"), r.data.number, "ok");
      router.push(`/erp/fleet/trips/${r.data.id}`);
    }
  }

  const err = (k: string) => (error instanceof ApiError ? error.field(k) : undefined);

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={trip ? `/erp/fleet/trips/${trip.id}` : "/erp/fleet/trips"} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {trip ? trip.number : t("fltTrips")}</Link>}
        title={trip ? fill(t("fltEditTrip"), { number: trip.number }) : t("fltPlanTrip")}
        subtitle={t("fltPlanTripSub")}
      />
      <GlassCard title={t("fltCostOption")}>
        <div className="erp-actions" role="radiogroup" aria-label={t("fltCostOption")}>
          {COST_OPTIONS.map((o) => (
            <label key={o} className="erp-action" style={{ cursor: "pointer" }}>
              <input type="radio" name="cost_option" value={o} checked={option === o} onChange={() => setF((prev) => ({ ...prev, cost_option: o, vehicle_id: "", driver_id: prev.driver_id }))} />
              <span className="erp-action-text"><span>{t(COST_OPTION_LABEL[o])}</span><span className="erp-muted">{t(COST_OPTION_HINT[o])}</span></span>
            </label>
          ))}
        </div>
      </GlassCard>

      <GlassCard title={t("fltTripDetails")}>
        <FormError error={error} />
        <div className="erp-form-grid">
          {option === "customer_vehicle" ? (
            <Field label={t("fltCustomerTruckReg")} htmlFor="tf-ext" error={err("external_vehicle")}>
              <input id="tf-ext" className="input" value={f.external_vehicle} onChange={set("external_vehicle")} />
            </Field>
          ) : (
            <>
              <Field label={t("fltVehicle")} htmlFor="tf-veh" required error={err("vehicle_id")}>
                <select id="tf-veh" className="input" value={f.vehicle_id} onChange={(e) => pickVehicle(e.target.value)}>
                  <option value="">{t("fltChoose")}</option>
                  {vehicles.map((v) => <option key={v.id} value={v.id} disabled={v.status === "out_of_service"}>{v.registration_number} {v.make ?? ""} {v.model ?? ""}{v.status !== "available" ? ` (${v.status.replace(/_/g, " ")})` : ""}</option>)}
                </select>
              </Field>
              <Field label={t("fltDriver")} htmlFor="tf-drv" required={option !== "hired"} hint={option === "hired" ? t("fltHiredDriverHint") : undefined} error={err("driver_id")}>
                <select id="tf-drv" className="input" value={f.driver_id} onChange={set("driver_id")}>
                  <option value="">{option === "hired" ? t("fltOwnersDriver") : t("fltChoose")}</option>
                  {lookups.drivers?.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                </select>
              </Field>
            </>
          )}
          <Field label={t("fltCustomer")} htmlFor="tf-cus" required={option === "charged" || option === "customer_vehicle"} error={err("customer_id")}>
            <select id="tf-cus" className="input" value={f.customer_id} onChange={set("customer_id")}>
              <option value="">{t("fltNone")}</option>
              {lookups.customers?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </Field>
          {charged && (
            <Field label={t("fltTransportCharge")} htmlFor="tf-chg" required={option === "charged"} error={err("transport_charge")}>
              <input id="tf-chg" type="number" min="0" inputMode="decimal" className="input" value={f.transport_charge} onChange={set("transport_charge")} />
            </Field>
          )}
          <Field label={t("fltOrigin")} htmlFor="tf-o" required error={err("origin")}><input id="tf-o" className="input" value={f.origin} onChange={set("origin")} /></Field>
          <Field label={t("fltDestination")} htmlFor="tf-d" required error={err("destination")}><input id="tf-d" className="input" value={f.destination} onChange={set("destination")} /></Field>
          <Field label={t("fltDistanceKm")} htmlFor="tf-km" error={err("distance_km")}><input id="tf-km" type="number" min="0" className="input" value={f.distance_km} onChange={set("distance_km")} /></Field>
          <Field label={t("fltPlannedStart")} htmlFor="tf-ps" required error={err("planned_start")}><input id="tf-ps" type="datetime-local" className="input" value={f.planned_start} onChange={set("planned_start")} /></Field>
          <Field label={t("fltPlannedEnd")} htmlFor="tf-pe" error={err("planned_end")}><input id="tf-pe" type="datetime-local" className="input" value={f.planned_end} onChange={set("planned_end")} /></Field>
          <Field label={t("fltSourceType")} htmlFor="tf-st" hint={t("fltSourceHint")} error={err("source_type")}>
            <select id="tf-st" className="input" value={f.source_type} onChange={set("source_type")}>
              <option value="">{t("fltNone")}</option>
              <option value="loading_order">{t("fltLoadingOrder")}</option>
              <option value="sales_order">{t("fltSalesOrder")}</option>
              <option value="delivery_note">{t("fltDeliveryNote")}</option>
              <option value="purchase_order">{t("fltPurchaseOrder")}</option>
            </select>
          </Field>
          <Field label={t("fltSourceRef")} htmlFor="tf-sr" error={err("source_reference")}><input id="tf-sr" className="input" value={f.source_reference} onChange={set("source_reference")} placeholder="LO-2026-000123" /></Field>
          <Field label={t("fltSourceId")} htmlFor="tf-si" error={err("source_id")}><input id="tf-si" type="number" min="1" className="input" value={f.source_id} onChange={set("source_id")} /></Field>
        </div>
        <Field label={t("fltCargo")} htmlFor="tf-cargo" error={err("cargo_description")}><textarea id="tf-cargo" className="input" rows={2} value={f.cargo_description} onChange={set("cargo_description")} /></Field>
        <Field label={t("fltNotes")} htmlFor="tf-notes" error={err("notes")}><textarea id="tf-notes" className="input" rows={2} value={f.notes} onChange={set("notes")} /></Field>
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap" }}>
          <Link className="btn btn-secondary" href={trip ? `/erp/fleet/trips/${trip.id}` : "/erp/fleet/trips"}>{t("fltCancel")}</Link>
          <button className="btn btn-primary" onClick={save} disabled={busy}><Icon name="ph-check" size={17} /> {trip ? t("fltSave") : t("fltPlanTrip")}</button>
        </div>
      </GlassCard>
    </div>
  );
}
