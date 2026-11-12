"use client";

import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { qty } from "@/lib/erp";
import type { OrderStatus, QcParameter, Receipt, ReceiptStatus } from "@/lib/production-api";
import { Badge, Dialog, Field, Icon, type Tone } from "@/components/ui";

/* Pieces the production screens share: status badges and the quality check dialog. */

export const ORDER_STATUS_LABEL: Record<OrderStatus, MessageKey> = {
  planned: "prdStatusPlanned", released: "prdStatusReleased", in_progress: "prdStatusInProgress",
  completed: "prdStatusCompleted", closed: "prdStatusClosed", cancelled: "prdStatusCancelled",
};

const ORDER_TONE: Record<OrderStatus, Tone> = {
  planned: "neutral", released: "info", in_progress: "warn", completed: "ok", closed: "neutral", cancelled: "bad",
};

export function OrderStatusBadge({ status }: { status: OrderStatus }) {
  const { t } = useApp();
  return <Badge tone={ORDER_TONE[status]} dot>{t(ORDER_STATUS_LABEL[status])}</Badge>;
}

const RECEIPT_LABEL: Record<ReceiptStatus, MessageKey> = {
  pending_qc: "prdRcptPending", released: "prdRcptReleased", rejected: "prdRcptRejected",
};

const RECEIPT_TONE: Record<ReceiptStatus, Tone> = { pending_qc: "warn", released: "ok", rejected: "bad" };

export function ReceiptStatusBadge({ status }: { status: ReceiptStatus }) {
  const { t } = useApp();
  return <Badge tone={RECEIPT_TONE[status]} dot>{t(RECEIPT_LABEL[status])}</Badge>;
}

/** A yield or wastage figure: one decimal and a percent sign, or a dash. */
export function percent(value: number | null | undefined): string {
  return value === null || value === undefined ? "-" : `${value.toLocaleString("en-US", { maximumFractionDigits: 1 })}%`;
}

const DEFAULT_PARAMETERS: QcParameter[] = [
  { name: "pH", target: "6.5 to 8.5", value: "", passed: true },
  { name: "Total dissolved solids", target: "up to 500 mg/L", value: "", passed: true },
  { name: "Fill level", target: "", value: "", passed: true },
  { name: "Cap torque", target: "12 to 18 in-lb", value: "", passed: true },
  { name: "Label and coding", target: "Batch and expiry legible", value: "", passed: true },
];

/**
 * The quality check on one receipt: each parameter with its target, the value
 * measured and pass or fail, then release or reject. A failed parameter
 * blocks release here as it does in the API.
 */
export function QcDialog({ receipt, onClose, onDone }: { receipt: Receipt | null; onClose: () => void; onDone: () => void }) {
  const { t, toast } = useApp();
  const [parameters, setParameters] = useState<QcParameter[]>(DEFAULT_PARAMETERS);
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  const failed = parameters.some((p) => p.name.trim() && !p.passed);
  const set = (i: number, patch: Partial<QcParameter>) => setParameters((all) => all.map((p, j) => (j === i ? { ...p, ...patch } : p)));

  function close() {
    setParameters(DEFAULT_PARAMETERS); setNotes(""); setError(null);
    onClose();
  }

  async function decide(decision: "release" | "reject") {
    if (!receipt) return;
    setBusy(true); setError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/production/receipts/${receipt.id}/qc`, {
        decision, notes: notes || null,
        parameters: parameters.filter((p) => p.name.trim()).map((p) => ({ ...p, target: p.target || null, value: p.value || null })),
      });
      toast(r.message, undefined, decision === "release" ? "ok" : "warn");
      setParameters(DEFAULT_PARAMETERS); setNotes("");
      onDone();
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={receipt !== null} onClose={close} busy={busy} wide icon="ph-seal-check" title={t("prdQcTitle")} sub={t("prdQcSub")}
      summary={receipt ? [
        { label: t("prdReceipt"), value: receipt.number },
        { label: t("prdBatch"), value: receipt.batch_number ?? "-" },
        { label: t("prdGood"), value: qty(receipt.good_quantity) },
        ...(receipt.order ? [{ label: t("prdOrder"), value: `${receipt.order.number} · ${receipt.order.product?.name ?? ""}` }] : []),
      ] : undefined}
      actions={<>
        <button className="btn btn-secondary" onClick={close} disabled={busy}>{t("erpBack")}</button>
        <button className="btn btn-danger" onClick={() => decide("reject")} disabled={busy}><Icon name="ph-x-circle" size={17} /> {t("prdReject")}</button>
        <button className="btn btn-primary" onClick={() => decide("release")} disabled={busy || failed}><Icon name="ph-check-circle" size={17} /> {t("prdRelease")}</button>
      </>}>
      <div className="vf-table-wrap">
        <table className="table vf-table erp-lines">
          <thead><tr><th>{t("prdParameter")}</th><th>{t("prdTarget")}</th><th>{t("prdMeasured")}</th><th>{t("prdPassed")}</th><th aria-label={t("erpRemove")} /></tr></thead>
          <tbody>
            {parameters.map((p, i) => (
              <tr key={i}>
                <td><input className="input" aria-label={t("prdParameter")} value={p.name} onChange={(e) => set(i, { name: e.target.value })} /></td>
                <td><input className="input" aria-label={t("prdTarget")} value={p.target ?? ""} onChange={(e) => set(i, { target: e.target.value })} /></td>
                <td><input className="input" aria-label={t("prdMeasured")} value={p.value ?? ""} onChange={(e) => set(i, { value: e.target.value })} /></td>
                <td>
                  <select className="input" aria-label={t("prdPassed")} value={p.passed ? "1" : "0"} onChange={(e) => set(i, { passed: e.target.value === "1" })}>
                    <option value="1">{t("prdPass")}</option>
                    <option value="0">{t("prdFail")}</option>
                  </select>
                </td>
                <td>
                  <button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={parameters.length === 1}
                    onClick={() => setParameters((all) => all.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="erp-lines-foot">
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => setParameters((all) => [...all, { name: "", target: "", value: "", passed: true }])}>
          <Icon name="ph-plus" size={16} /> {t("prdAddParameter")}
        </button>
        {failed && <span className="erp-muted">{t("prdFailedBlocks")}</span>}
      </div>
      <Field label={t("prdNotes")} htmlFor="qc-notes" hint={t("erpOptional")}>
        <textarea id="qc-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error.message}</div>}
    </Dialog>
  );
}
