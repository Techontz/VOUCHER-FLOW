"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type LoadingOrder, usePaged } from "@/lib/sales-api";
import type { MessageKey } from "@/lib/i18n";
import { Badge, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { type Act, ActionDialog, SalesBadge } from "@/components/sales-ui";

export type Stage = "" | "open" | "loaded" | "in_transit" | "delivered" | "discrepancies" | "delivery_notes" | "gate_passes";

const STAGES: { value: Stage; label: MessageKey }[] = [
  { value: "", label: "erpAll" }, { value: "open", label: "salStOpen" }, { value: "loaded", label: "salStLoaded" },
  { value: "in_transit", label: "salInTransit" }, { value: "delivered", label: "salStDelivered" }, { value: "discrepancies", label: "salDiscrepancies" },
];

/**
 * Loading orders as a register. The delivery-note and gate-pass screens are
 * the same register narrowed to documents that carry those numbers.
 */
export function LoadingRegister({ title, subtitle, fixed, initial = "", columns = "loading" }: {
  title: MessageKey; subtitle: MessageKey; fixed?: Stage; initial?: Stage; columns?: "loading" | "delivery_notes" | "gate_passes";
}) {
  const { t, locale } = useApp();
  const [stage, setStage] = useState<Stage>(initial);
  const [q, setQ] = useState("");
  const active = fixed ?? stage;
  const query = active === "open" || active === "loaded" || active === "delivered" ? { status: active } : { stage: active || undefined };
  const { rows, error, setPage } = usePaged<LoadingOrder>("/erp/dispatch/loading-orders", query, q);
  const { can } = useErp();

  return (
    <div className="erp-page">
      <PageHeader title={t(title)} subtitle={t(subtitle)} actions={!fixed && can("dispatch.load") && <NewLoading />} />
      <Toolbar>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchLoading")} />
        {!fixed && <FilterChips<Stage> value={stage} onChange={setStage} items={STAGES.map((s) => ({ value: s.value, label: t(s.label) }))} />}
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-truck" title={t("salNoLoadingOrders")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr>
                <th>{columns === "delivery_notes" ? t("salDeliveryNote") : columns === "gate_passes" ? t("salGatePass") : t("salLoadingOrder")}</th>
                <th>{t("salCustomer")}</th><th>{t("erpWarehouse")}</th><th>{t("salVehicle")}</th>
                <th>{columns === "gate_passes" ? t("salLeftGate") : columns === "delivery_notes" ? t("salIssued") : t("salPlannedDate")}</th>
                <th>{t("erpStatus")}</th>
              </tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link className="erp-cell-link" href={columns === "loading" ? `/erp/dispatch/loading/${r.id}` : `/erp/dispatch/loading/${r.id}/print?doc=${columns === "gate_passes" ? "gate-pass" : "delivery-note"}`}>
                        <span className="erp-cell-title tnum">{columns === "delivery_notes" ? r.delivery_note_number : columns === "gate_passes" ? r.gate_pass_number : r.number}</span>
                        <span className="erp-cell-sub tnum">{columns === "loading" ? r.order?.number : r.number}</span>
                      </Link>
                    </td>
                    <td>{r.customer?.name}</td>
                    <td>{r.warehouse?.name}</td>
                    <td>{r.vehicle_number ?? "-"}{r.driver_name && <span className="erp-cell-sub">{r.driver_name}</span>}</td>
                    <td className="tnum">{formatDate(columns === "gate_passes" ? r.gate_pass_issued_at : columns === "delivery_notes" ? r.delivery_note_issued_at : r.planned_date, locale)}</td>
                    <td>
                      <SalesBadge status={r.status} />
                      {r.discrepancy_status && <> <Badge tone={r.discrepancy_status === "open" ? "bad" : "neutral"}>{t(r.discrepancy_status === "open" ? "salShortOpen" : r.discrepancy_status === "returned" ? "salShortReturned" : "salShortWrittenOff")}</Badge></>}
                    </td>
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

interface ReadyOrder { id: number; number: string; status: string; warehouse_id: number | null; delivery_address: string | null; customer?: { name: string } }

/**
 * Starts a loading order for everything still to load on a released order.
 * Partial loads are set from the order screen; here the warehouse and the
 * truck are all that is asked.
 */
function NewLoading() {
  const { t } = useApp();
  const router = useRouter();
  const [act, setAct] = useState<Act | null>(null);
  const [data, setData] = useState<{ warehouses: { id: number; name: string }[]; ready_orders: ReadyOrder[] } | null>(null);
  const [form, setForm] = useState({ sales_order_id: "", warehouse_id: "", vehicle_number: "", driver_name: "" });

  useEffect(() => {
    if (!act || data) return;
    api.get<{ data: { warehouses: { id: number; name: string }[]; ready_orders: ReadyOrder[] } }>("/erp/dispatch/lookups").then((r) => {
      setData(r.data);
      setForm((f) => ({ ...f, warehouse_id: f.warehouse_id || String(r.data.warehouses[0]?.id ?? "") }));
    }).catch(() => setData({ warehouses: [], ready_orders: [] }));
  }, [act, data]);

  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));

  return (
    <>
      <button className="btn btn-primary" onClick={() => setAct({ key: "new", path: "/erp/dispatch/loading-orders", label: t("salCreateLoading"), icon: "ph-truck", title: t("salCreateLoading"), sub: t("salNewLoadingSub"), then: (r) => router.push(`/erp/dispatch/loading/${r.data.id}`) })}>
        <Icon name="ph-plus" size={18} /> {t("salCreateLoading")}
      </button>
      <ActionDialog act={act} onClose={() => setAct(null)} onDone={() => undefined}
        body={() => ({ sales_order_id: Number(form.sales_order_id), warehouse_id: Number(form.warehouse_id), vehicle_number: form.vehicle_number || null, driver_name: form.driver_name || null })}>
        {!data ? <LoadingBlock rows={2} /> : (
          <div className="erp-form-grid">
            <Field label={t("salOrder")} htmlFor="nl-order" required>
              <select id="nl-order" className="input" value={form.sales_order_id} onChange={(e) => {
                const o = data.ready_orders.find((x) => String(x.id) === e.target.value);
                set({ sales_order_id: e.target.value, ...(o?.warehouse_id ? { warehouse_id: String(o.warehouse_id) } : {}) });
              }}>
                <option value="">{data.ready_orders.length ? t("salPickOrder") : t("salNothingReady")}</option>
                {data.ready_orders.map((o) => <option key={o.id} value={o.id}>{o.number} · {o.customer?.name}</option>)}
              </select>
            </Field>
            <Field label={t("erpWarehouse")} htmlFor="nl-wh" required>
              <select id="nl-wh" className="input" value={form.warehouse_id} onChange={(e) => set({ warehouse_id: e.target.value })}>
                {data.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </Field>
            <Field label={t("salVehicle")} htmlFor="nl-veh"><input id="nl-veh" className="input" value={form.vehicle_number} onChange={(e) => set({ vehicle_number: e.target.value })} placeholder="T 123 ABC" /></Field>
            <Field label={t("salDriver")} htmlFor="nl-drv"><input id="nl-drv" className="input" value={form.driver_name} onChange={(e) => set({ driver_name: e.target.value })} /></Field>
          </div>
        )}
      </ActionDialog>
    </>
  );
}
