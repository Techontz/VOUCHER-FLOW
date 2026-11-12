"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useQueryValue } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { LoadingOrder } from "@/lib/sales-api";
import { EmptyState, ErrorState, Icon, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";

export default function PrintLoadingPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><PrintGate /></ErpGate>;
}

function PrintGate() {
  const doc = useQueryValue("doc");
  if (doc === undefined) return <LoadingBlock rows={4} />;
  return <PrintSheet doc={doc === "gate-pass" ? "gate-pass" : "delivery-note"} />;
}

/** The delivery note (travels with the goods) or the gate pass (stays at the gate), laid out to print. */
function PrintSheet({ doc }: { doc: "delivery-note" | "gate-pass" }) {
  const { t, locale } = useApp();
  const { id } = useParams<{ id: string }>();
  const [lo, setLo] = useState<LoadingOrder | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: LoadingOrder }>(`/erp/dispatch/loading-orders/${id}`).then((r) => setLo(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!lo) return <LoadingBlock rows={5} />;

  const number = doc === "gate-pass" ? lo.gate_pass_number : lo.delivery_note_number;
  if (!number) return <EmptyState icon="ph-file-dashed" title={t(doc === "gate-pass" ? "salNoGatePassYet" : "salNoDeliveryNoteYet")} />;

  const gate = doc === "gate-pass";

  return (
    <div className="erp-page">
      <div className="sal-noprint sal-doc-bar">
        <Link href={`/erp/dispatch/loading/${lo.id}`} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {lo.number}</Link>
        <button className="btn btn-primary" onClick={() => window.print()}><Icon name="ph-printer" size={17} /> {t("salPrint")}</button>
      </div>

      <article className="sal-sheet">
        <header className="sal-sheet-head">
          <div>
            <div className="sal-sheet-seller">{lo.seller?.name}</div>
            <div className="erp-muted">{lo.seller?.address}</div>
            <div className="erp-muted">{lo.seller?.phone}</div>
          </div>
          <div className="sal-sheet-title">
            <h1>{t(gate ? "salGatePass" : "salDeliveryNote")}</h1>
            <div className="tnum"><strong>{number}</strong></div>
            <div className="erp-muted">{formatDateTime(gate ? lo.gate_pass_issued_at : lo.delivery_note_issued_at, locale)}</div>
          </div>
        </header>

        <section className="sal-sheet-parties">
          <div>
            <div className="sal-sheet-label">{t("salDeliverTo")}</div>
            <strong>{lo.customer?.name}</strong>
            <div>{lo.destination ?? [lo.customer?.address, lo.customer?.city].filter(Boolean).join(", ")}</div>
            {lo.customer?.phone && <div>{lo.customer.phone}</div>}
          </div>
          <div>
            <div className="sal-sheet-label">{t("salTransport")}</div>
            <div>{t("salFrom")}: {lo.warehouse?.name}</div>
            <div>{t("salVehicle")}: {lo.vehicle_number ?? "-"}</div>
            <div>{t("salDriver")}: {lo.driver_confirmed_name ?? lo.driver_name ?? "-"}</div>
            <div className="tnum">{t("salOrder")}: {lo.order?.number} · {t("salLoadingOrder")}: {lo.number}</div>
          </div>
        </section>

        <table className="table vf-table sal-sheet-lines">
          <thead><tr><th>#</th><th>{t("erpProduct")}</th><th className="num">{t("salQtyOrdered")}</th><th className="num">{t("salQtyLoaded")}</th>{!gate && <th className="num">{t("salQtyReceived")}</th>}</tr></thead>
          <tbody>
            {lo.lines?.map((l, i) => (
              <tr key={l.id}>
                <td>{i + 1}</td>
                <td>{l.product?.name}<span className="erp-cell-sub tnum">{l.product?.sku}</span></td>
                <td className="num">{qty(l.quantity_ordered)}</td>
                <td className="num"><strong>{qty(l.quantity_loaded)}</strong> {l.product?.unit?.code}</td>
                {!gate && <td className="num">{l.quantity_received !== null ? qty(l.quantity_received) : <span className="sal-blank" />}</td>}
              </tr>
            ))}
          </tbody>
        </table>

        <section className="sal-signatures">
          <div><span className="sal-sheet-label">{t("salStorekeeper")}</span><span>{lo.loader?.name ?? ""}</span><span className="sal-sign-line" /></div>
          <div><span className="sal-sheet-label">{t("salDriver")}</span><span>{lo.driver_confirmed_name ?? ""}</span><span className="sal-sign-line" /></div>
          <div><span className="sal-sheet-label">{t("salSecurity")}</span><span>{lo.security_confirmed_name ?? ""}</span><span className="sal-sign-line" /></div>
          {!gate && (
            <div><span className="sal-sheet-label">{t("salReceivedBy")}</span><span>{lo.received_by_name ?? ""}{lo.received_date ? ` · ${formatDate(lo.received_date, locale)}` : ""}</span><span className="sal-sign-line" /></div>
          )}
        </section>
        {gate && <p className="erp-muted">{t("salGatePassFoot")}</p>}
      </article>
    </div>
  );
}
