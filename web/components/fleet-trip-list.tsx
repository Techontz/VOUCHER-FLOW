"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp } from "@/lib/erp";
import { formatDateTime } from "@/lib/format";
import { COST_OPTION_LABEL, COST_OPTIONS, type CostOption, type Trip, TRIP_STATUS_LABEL, TRIP_STATUSES, type TripStatus } from "@/lib/fleet";
import { Badge, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { TripStatusBadge, useMoney } from "@/components/fleet-ui";

/** Every trip for the fleet office, or a driver's own (mine). */
export function TripList({ mine = false }: { mine?: boolean }) {
  const { t, locale } = useApp();
  const { can } = useErp();
  const fmt = useMoney();
  const [status, setStatus] = useState<TripStatus | "">("");
  const [option, setOption] = useState<CostOption | "">("");
  const [over, setOver] = useState(false);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Trip> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<Trip>>(mine ? "/erp/fleet/my-trips" : "/erp/fleet/trips", {
        status: status || undefined, cost_option: option || undefined, over_standard: over ? 1 : undefined, q: q || undefined, page,
      }).then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [mine, status, option, over, q, page]);

  const href = (id: number) => (mine ? `/erp/fleet/my-trips/${id}` : `/erp/fleet/trips/${id}`);

  return (
    <div className="erp-page">
      <PageHeader title={mine ? t("fltMyTrips") : t("fltTrips")} subtitle={mine ? t("fltMyTripsSub") : t("fltTripsSub")}
        actions={!mine && can("fleet.trips") && <Link className="btn btn-primary" href="/erp/fleet/trips/new"><Icon name="ph-plus" size={18} /> {t("fltPlanTrip")}</Link>} />

      <Toolbar end={!mine && (
        <select className="input" aria-label={t("fltCostOption")} value={option} onChange={(e) => { setOption(e.target.value as CostOption | ""); setPage(1); }} style={{ maxWidth: 240 }}>
          <option value="">{t("fltAllOptions")}</option>
          {COST_OPTIONS.map((o) => <option key={o} value={o}>{t(COST_OPTION_LABEL[o])}</option>)}
        </select>
      )}>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("fltSearchTrips")} />
        <FilterChips<TripStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("fltAll") }, ...TRIP_STATUSES.map((s) => ({ value: s, label: t(TRIP_STATUS_LABEL[s]) })),
        ]} />
        {!mine && (
          <label className="erp-check" style={{ margin: 0 }}>
            <input type="checkbox" checked={over} onChange={(e) => { setOver(e.target.checked); setPage(1); }} />
            <span className="erp-check-label">{t("fltOverStandardOnly")}</span>
          </label>
        )}
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-path" title={t("fltNoTrips")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("fltTrip")}</th><th>{t("fltRoute")}</th><th>{t("fltVehicle")}</th>{!mine && <th>{t("fltDriver")}</th>}<th>{t("fltCustomer")}</th>{!mine && <th className="num">{t("fltTransportCharge")}</th>}<th>{t("fltStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((trip) => (
                  <tr key={trip.id} className="is-clickable">
                    <td><Link href={href(trip.id)} className="erp-cell-link"><span className="erp-cell-title tnum">{trip.number}</span><span className="erp-cell-sub">{formatDateTime(trip.planned_start, locale)}</span></Link></td>
                    <td>{trip.origin} → {trip.destination}<span className="erp-cell-sub">{t(COST_OPTION_LABEL[trip.cost_option])}{trip.source_reference ? ` · ${trip.source_reference}` : ""}</span></td>
                    <td>{trip.vehicle?.registration_number ?? trip.external_vehicle ?? "-"}</td>
                    {!mine && <td>{trip.driver?.user?.name ?? "-"}</td>}
                    <td>{trip.customer?.name ?? "-"}</td>
                    {!mine && <td className="num">{Number(trip.transport_charge) ? fmt(trip.transport_charge) : "-"}</td>}
                    <td><TripStatusBadge status={trip.status} />{trip.fuel_over_standard && <> <Badge tone="bad">{t("fltOverStandard")}</Badge></>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}
