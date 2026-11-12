"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { addDays, type ProductionOrder, type Receipt, today } from "@/lib/production-api";
import { Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate, fill } from "@/components/erp-ui";
import { OrderStatusBadge, percent, QcDialog, ReceiptStatusBadge } from "@/components/production-ui";
import { RequirementTable } from "@/components/production-requirements";

export default function ProductionOrderPage() {
  return <ErpGate module="production" permission="production.view"><OrderDetail /></ErpGate>;
}

type Action = "release" | "cancel" | "complete" | "close";

interface IssueRow { product_id: number; quantity: string; batch_number: string }

function OrderDetail() {
  const { t, locale, toast } = useApp();
  const { can, config } = useErp();
  const { id } = useParams<{ id: string }>();
  const [order, setOrder] = useState<ProductionOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<Action | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<ApiError | null>(null);
  const [issuing, setIssuing] = useState<IssueRow[] | null>(null);
  const [receiving, setReceiving] = useState(false);
  const [output, setOutput] = useState({ receipt_date: today(), good: "", rejected: "0", wastage: "0", batch_number: "", expiry_date: "", is_final: false, notes: "" });
  const [inspecting, setInspecting] = useState<Receipt | null>(null);

  const load = useCallback(() => {
    api.get<{ data: ProductionOrder }>(`/erp/production/orders/${id}`).then((r) => setOrder(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function run(path: string, body: unknown, after: () => void) {
    setBusy(true); setActionError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/production/orders/${id}/${path}`, body);
      toast(r.message, undefined, "ok");
      after();
      load();
    } catch (e) {
      setActionError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!order) return <LoadingBlock rows={6} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const s = order.status;
  const onFloor = s === "released" || s === "in_progress";
  const hasFinal = order.receipts?.some((r) => r.is_final) ?? false;
  const unit = order.product?.unit?.code ?? "";
  const c = order.costing;
  const produced = Number(order.produced_quantity) > 0;

  function openIssue() {
    if (!order?.requirements) return;
    setActionError(null);
    setIssuing(order.requirements.map((r) => ({
      product_id: r.product_id,
      quantity: r.remaining_quantity > 0 ? String(r.product.allows_decimals ? Math.ceil(r.remaining_quantity * 1000) / 1000 : Math.ceil(r.remaining_quantity)) : "",
      batch_number: "",
    })));
  }

  function openReceive() {
    if (!order) return;
    setActionError(null);
    const prefix = (order.product?.sku ?? "FG").replace(/^FG-/, "").split("-")[0];
    const stamp = today().slice(2).replaceAll("-", "");
    setOutput({
      receipt_date: today(), good: "", rejected: "0", wastage: "0",
      batch_number: order.product?.track_batches ? `${prefix}-${stamp}-${String.fromCharCode(65 + (order.receipts?.length ?? 0))}` : "",
      expiry_date: order.product?.track_expiry ? addDays(today(), 365) : "",
      is_final: false, notes: "",
    });
    setReceiving(true);
  }

  const producedTotal = Number(output.good || 0) + Number(output.rejected || 0) + Number(output.wastage || 0);

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/production/orders" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("prdNavOrders")}</Link>}
        kicker={t("prdOrder")}
        title={<span className="erp-inline-icon tnum"><Icon name="ph-factory" size={34} /> {order.number}</span>}
        subtitle={<>{qty(order.planned_quantity)} {unit} · {order.product?.name} · {order.bom ? `${t("prdVersion")} ${order.bom.version}` : ""} · {formatDate(order.planned_start, locale)}</>}
        actions={<>
          <OrderStatusBadge status={s} />
          {s === "planned" && can("production.plan") && <button className="btn btn-primary" onClick={() => setConfirm("release")}><Icon name="ph-play" size={17} /> {t("prdRelease")}</button>}
          {onFloor && can("production.issue") && <button className="btn btn-secondary" onClick={openIssue}><Icon name="ph-tray-arrow-up" size={17} /> {t("prdIssueMaterials")}</button>}
          {onFloor && !hasFinal && can("production.receive") && <button className="btn btn-primary" onClick={openReceive}><Icon name="ph-package" size={17} /> {t("prdRecordOutput")}</button>}
          {s === "in_progress" && can("production.plan") && <button className="btn btn-secondary" onClick={() => setConfirm("complete")}><Icon name="ph-flag-checkered" size={17} /> {t("prdComplete")}</button>}
          {s === "completed" && can("production.close") && <button className="btn btn-primary" onClick={() => setConfirm("close")}><Icon name="ph-lock-simple" size={17} /> {t("prdClose")}</button>}
          {(s === "planned" || s === "released") && can("production.plan") && <button className="btn btn-secondary" onClick={() => setConfirm("cancel")}>{t("prdCancelOrder")}</button>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard title={t("prdOutput")}>
          <div className="erp-figures">
            <div><span className="erp-muted">{t("prdPlanned")}</span><strong className="tnum">{qty(order.planned_quantity)}</strong></div>
            <div><span className="erp-muted">{t("prdProduced")}</span><strong className="tnum">{qty(order.produced_quantity)}</strong></div>
            <div><span className="erp-muted">{t("prdReleasedQty")}</span><strong className="tnum">{qty(order.released_quantity)}</strong></div>
            <div><span className="erp-muted">{t("prdRejected")}</span><strong className="tnum">{qty(order.rejected_quantity)}</strong></div>
            <div><span className="erp-muted">{t("prdWaste")}</span><strong className="tnum">{qty(order.wastage_quantity)}</strong></div>
            <div><span className="erp-muted">{t("prdYield")}</span><strong className="tnum">{percent(c?.yield_percent)}</strong></div>
          </div>
        </GlassCard>

        {c && (
          <GlassCard title={t("prdCostPanel")} subtitle={s === "closed" ? t("prdCostClosed") : t("prdCostOpen")}>
            <dl className="erp-review">
              <dt>{t("prdStandardUnit")}</dt><dd className="tnum">{currency} {amount(c.standard_unit_cost)}</dd>
              <dt>{t("prdMaterialCost")}</dt><dd className="tnum">{currency} {amount(c.material_cost)}</dd>
              <dt>{t("prdConversionCost")}</dt><dd className="tnum">{currency} {amount(c.conversion_cost)}</dd>
              <dt>{t("prdActualTotal")}</dt><dd className="tnum"><strong>{currency} {amount(c.actual_total)}</strong></dd>
              <dt>{t("prdActualUnit")}</dt><dd className="tnum">{c.actual_unit_cost !== null ? `${currency} ${amount(c.actual_unit_cost)}` : "-"}</dd>
              <dt>{t("prdStandardForReleased")}</dt><dd className="tnum">{currency} {amount(c.standard_total_for_released)}</dd>
              <dt>{t("prdVsStandard")}</dt><dd className="tnum" style={{ color: (c.variance_against_standard ?? 0) > 0 ? "var(--st-bad-fg)" : undefined }}>{c.variance_against_standard !== null ? `${currency} ${amount(c.variance_against_standard)}` : "-"}</dd>
              <dt>{t("prdReceivedValue")}</dt><dd className="tnum">{currency} {amount(c.received_value)}</dd>
              <dt>{t("prdWipBalance")}</dt><dd className="tnum">{currency} {amount(c.wip_balance)}</dd>
              {c.variance_value !== null && <><dt>{t("prdVariancePosted")}</dt><dd className="tnum">{currency} {amount(c.variance_value)}</dd></>}
            </dl>
          </GlassCard>
        )}

        <GlassCard title={t("prdTimeline")}>
          <dl className="erp-review">
            <dt>{t("prdPlannedBy")}</dt><dd>{order.creator?.name ?? "-"} · {formatDateTime(order.created_at, locale)}</dd>
            {order.released_at && <><dt>{t("prdReleasedBy")}</dt><dd>{order.releaser?.name ?? "-"} · {formatDateTime(order.released_at, locale)}</dd></>}
            {order.started_at && <><dt>{t("prdStarted")}</dt><dd>{formatDateTime(order.started_at, locale)}</dd></>}
            {order.completed_at && <><dt>{t("prdCompletedBy")}</dt><dd>{order.completer?.name ?? "-"} · {formatDateTime(order.completed_at, locale)}</dd></>}
            {order.closed_at && <><dt>{t("prdClosedBy")}</dt><dd>{order.closer?.name ?? "-"} · {formatDateTime(order.closed_at, locale)}</dd></>}
            {order.cancelled_at && <><dt>{t("prdCancelledBy")}</dt><dd>{order.canceller?.name ?? "-"} · {formatDateTime(order.cancelled_at, locale)}<span className="erp-cell-sub">{order.cancel_reason}</span></dd></>}
            <dt>{t("prdMaterialsFrom")}</dt><dd>{order.materials_warehouse?.name}</dd>
            <dt>{t("prdOutputTo")}</dt><dd>{order.output_warehouse?.name}</dd>
            {order.bom?.work_centre && <><dt>{t("prdWorkCentre")}</dt><dd>{order.bom.work_centre.code} · {order.bom.work_centre.name}</dd></>}
            {order.reference && <><dt>{t("erpReference")}</dt><dd>{order.reference}</dd></>}
            {order.notes && <><dt>{t("prdNotes")}</dt><dd>{order.notes}</dd></>}
          </dl>
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("prdMaterials")} subtitle={produced ? t("prdMaterialsProducedSub") : t("prdMaterialsSub")} pad={false}
          action={order.bom && <Link className="vf-card-link" href={`/erp/production/boms/${order.bom.id}`}>{t("prdViewBom")}</Link>}>
          <RequirementTable rows={order.requirements ?? []} produced={produced} />
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("prdReceipts")} subtitle={t("prdReceiptsSub")} pad={false}>
          {!order.receipts?.length ? <EmptyState icon="ph-package" title={t("prdNoReceipts")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("prdReceipt")}</th><th>{t("prdBatch")}</th><th className="num">{t("prdProduced")}</th><th className="num">{t("prdGood")}</th><th className="num">{t("prdRejected")}</th><th className="num">{t("prdWaste")}</th><th className="num">{t("prdUnitCost")}</th><th>{t("prdQc")}</th><th>{t("erpStatus")}</th></tr></thead>
                <tbody>
                  {order.receipts.map((r) => (
                    <tr key={r.id}>
                      <td><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{formatDate(r.receipt_date, locale)}{r.is_final ? ` · ${t("prdFinal")}` : ""}</span></td>
                      <td className="tnum">{r.batch_number ?? "-"}{r.expiry_date && <span className="erp-cell-sub">{formatDate(r.expiry_date, locale)}</span>}</td>
                      <td className="num">{qty(r.produced_quantity)}</td>
                      <td className="num">{qty(r.good_quantity)}</td>
                      <td className="num">{qty(r.rejected_quantity)}</td>
                      <td className="num">{qty(r.wastage_quantity)}</td>
                      <td className="num">{r.unit_cost !== null ? amount(r.unit_cost) : "-"}{r.stock_document && <span className="erp-cell-sub">{can("inventory.view") ? <Link href={`/erp/documents/${r.stock_document.id}`}>{r.stock_document.number}</Link> : r.stock_document.number}</span>}</td>
                      <td>{r.qc ? <span>{r.qc.inspector?.name ?? "-"}<span className="erp-cell-sub">{r.qc.parameters.filter((p) => !p.passed).map((p) => p.name).join(", ") || t("prdAllPassed")}</span></span> : "-"}</td>
                      <td>
                        {r.status === "pending_qc" && can("production.qc")
                          ? <button className="btn btn-secondary btn-sm" onClick={() => setInspecting({ ...r, order: { id: order.id, number: order.number, product: order.product } })}><Icon name="ph-seal-check" size={16} /> {t("prdInspect")}</button>
                          : <ReceiptStatusBadge status={r.status} />}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("prdIssues")} pad={false}>
          {!order.issues?.length ? <EmptyState icon="ph-tray-arrow-up" title={t("prdNoIssues")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpReference")}</th><th>{t("erpDate")}</th><th>{t("prdLinesIssued")}</th><th>{t("erpPrepared")}</th><th className="num">{t("erpValue")}</th></tr></thead>
                <tbody>
                  {order.issues.map((d) => (
                    <tr key={d.id}>
                      <td className="tnum">{can("inventory.view") ? <Link href={`/erp/documents/${d.id}`}>{d.number}</Link> : d.number}</td>
                      <td className="tnum">{formatDate(d.document_date, locale)}</td>
                      <td>{d.lines.map((l, i) => <span key={i} className="erp-cell-sub">{l.product?.name} · {qty(l.quantity)}{l.batch_number ? ` · ${l.batch_number}` : ""}</span>)}</td>
                      <td>{d.creator?.name ?? "-"}</td>
                      <td className="num">{currency} {amount(d.value)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      </div>

      <Dialog open={confirm !== null} onClose={() => { setConfirm(null); setActionError(null); }} busy={busy}
        icon={confirm === "cancel" ? "ph-x-circle" : confirm === "close" ? "ph-lock-simple" : "ph-check-circle"}
        tone={confirm === "cancel" ? "warn" : "info"}
        title={confirm ? fill(t(confirm === "release" ? "prdReleaseQ" : confirm === "cancel" ? "prdCancelQ" : confirm === "complete" ? "prdCompleteQ" : "prdCloseQ"), { number: order.number }) : ""}
        sub={confirm === "close" ? fill(t("prdCloseSub"), { amount: `${currency} ${amount(c?.wip_balance ?? 0)}` }) : confirm === "release" ? t("prdReleaseSub") : confirm === "complete" ? t("prdCompleteSub") : undefined}
        summary={[
          { label: t("erpProduct"), value: order.product?.name ?? "" },
          { label: t("prdPlanned"), value: `${qty(order.planned_quantity)} ${unit}` },
          { label: t("prdReleasedQty"), value: `${qty(order.released_quantity)} ${unit}` },
        ]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          <button className={confirm === "cancel" ? "btn btn-danger" : "btn btn-primary"} disabled={busy || (confirm === "cancel" && reason.trim().length < 3)}
            onClick={() => confirm && run(confirm, confirm === "cancel" ? { reason } : undefined, () => { setConfirm(null); setReason(""); })}>
            {confirm === "release" ? t("prdRelease") : confirm === "cancel" ? t("prdCancelOrder") : confirm === "complete" ? t("prdComplete") : t("prdClose")}
          </button>
        </>}>
        {confirm === "cancel" && (
          <Field label={t("erpReason")} htmlFor="po-reason" required>
            <input id="po-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
          </Field>
        )}
        {actionError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {actionError.message}</div>}
      </Dialog>

      <Dialog open={issuing !== null} onClose={() => { setIssuing(null); setActionError(null); }} busy={busy} wide icon="ph-tray-arrow-up"
        title={t("prdIssueMaterials")} sub={fill(t("prdIssueSub"), { warehouse: order.materials_warehouse?.name ?? "" })}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setIssuing(null)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-primary" disabled={busy || !issuing?.some((l) => Number(l.quantity) > 0)}
            onClick={() => issuing && run("issue", {
              lines: issuing.filter((l) => Number(l.quantity) > 0).map((l) => ({ product_id: l.product_id, quantity: Number(l.quantity), batch_number: l.batch_number || null })),
            }, () => setIssuing(null))}>
            <Icon name="ph-check-circle" size={17} /> {t("prdIssueAndPost")}
          </button>
        </>}>
        <div className="vf-table-wrap">
          <table className="table vf-table erp-lines">
            <thead><tr><th>{t("prdComponent")}</th><th className="num">{t("prdRemaining")}</th><th className="num">{t("erpQuantity")}</th><th>{t("prdBatch")}</th></tr></thead>
            <tbody>
              {issuing?.map((l, i) => {
                const r = order.requirements?.find((x) => x.product_id === l.product_id);
                if (!r) return null;
                return (
                  <tr key={l.product_id}>
                    <td><span className="erp-cell-title">{r.product.name}</span><span className="erp-cell-sub">{t("prdAvailable")} {qty(r.available_quantity)} {r.product.unit}</span></td>
                    <td className="num">{qty(r.remaining_quantity)}</td>
                    <td className="num">
                      <input className="input tnum" type="number" min={0} step="any" aria-label={t("erpQuantity")} value={l.quantity}
                        onChange={(e) => setIssuing((all) => all?.map((x, j) => (j === i ? { ...x, quantity: e.target.value } : x)) ?? null)} />
                    </td>
                    <td>
                      {r.product.track_batches ? (
                        <select className="input" aria-label={t("prdBatch")} value={l.batch_number}
                          onChange={(e) => setIssuing((all) => all?.map((x, j) => (j === i ? { ...x, batch_number: e.target.value } : x)) ?? null)}>
                          <option value="">{t("prdBatchAuto")}</option>
                          {r.batches.map((b) => <option key={b.batch_number} value={b.batch_number}>{b.batch_number} · {qty(b.quantity)}{b.expiry_date ? ` · ${formatDate(b.expiry_date, locale)}` : ""}</option>)}
                        </select>
                      ) : <span className="erp-muted">-</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="erp-muted">{t("prdIssueHint")}</p>
        {actionError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {actionError.message}</div>}
      </Dialog>

      <Dialog open={receiving} onClose={() => { setReceiving(false); setActionError(null); }} busy={busy} icon="ph-package"
        title={t("prdRecordOutput")} sub={t("prdRecordOutputSub")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setReceiving(false)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-primary" disabled={busy || producedTotal <= 0}
            onClick={() => run("receipts", {
              receipt_date: output.receipt_date, produced_quantity: producedTotal,
              good_quantity: Number(output.good || 0), rejected_quantity: Number(output.rejected || 0), wastage_quantity: Number(output.wastage || 0),
              batch_number: output.batch_number || null, expiry_date: output.expiry_date || null, is_final: output.is_final, notes: output.notes || null,
            }, () => setReceiving(false))}>
            <Icon name="ph-floppy-disk" size={17} /> {t("prdSaveOutput")}
          </button>
        </>}>
        <div className="erp-form-grid">
          <Field label={t("erpDate")} htmlFor="rc-date" error={actionError?.field("receipt_date")}>
            <input id="rc-date" className="input" type="date" max={today()} value={output.receipt_date} onChange={(e) => setOutput({ ...output, receipt_date: e.target.value })} />
          </Field>
          <Field label={t("prdGood")} htmlFor="rc-good" required error={actionError?.field("good_quantity")} hint={unit}>
            <input id="rc-good" className="input tnum" type="number" min={0} step="any" value={output.good} onChange={(e) => setOutput({ ...output, good: e.target.value })} autoFocus />
          </Field>
          <Field label={t("prdRejected")} htmlFor="rc-rej" error={actionError?.field("rejected_quantity")}>
            <input id="rc-rej" className="input tnum" type="number" min={0} step="any" value={output.rejected} onChange={(e) => setOutput({ ...output, rejected: e.target.value })} />
          </Field>
          <Field label={t("prdWaste")} htmlFor="rc-waste" error={actionError?.field("wastage_quantity")}>
            <input id="rc-waste" className="input tnum" type="number" min={0} step="any" value={output.wastage} onChange={(e) => setOutput({ ...output, wastage: e.target.value })} />
          </Field>
          <Field label={t("prdBatch")} htmlFor="rc-batch" required={order.product?.track_batches} error={actionError?.field("batch_number")}>
            <input id="rc-batch" className="input" value={output.batch_number} onChange={(e) => setOutput({ ...output, batch_number: e.target.value })} />
          </Field>
          <Field label={t("erpExpiry")} htmlFor="rc-exp" required={order.product?.track_expiry} error={actionError?.field("expiry_date")}>
            <input id="rc-exp" className="input" type="date" value={output.expiry_date} onChange={(e) => setOutput({ ...output, expiry_date: e.target.value })} />
          </Field>
        </div>
        <p className="tnum"><span className="erp-muted">{t("prdProduced")}</span> <strong>{qty(producedTotal)} {unit}</strong></p>
        <Check label={t("prdFinalReceipt")} hint={t("prdFinalReceiptHint")} checked={output.is_final} onChange={(v) => setOutput({ ...output, is_final: v })} />
        <Field label={t("prdNotes")} htmlFor="rc-notes" hint={t("erpOptional")}>
          <textarea id="rc-notes" className="input" rows={2} value={output.notes} onChange={(e) => setOutput({ ...output, notes: e.target.value })} />
        </Field>
        {actionError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {actionError.message}</div>}
      </Dialog>

      <QcDialog receipt={inspecting} onClose={() => setInspecting(null)} onDone={() => { setInspecting(null); load(); }} />
    </div>
  );
}
