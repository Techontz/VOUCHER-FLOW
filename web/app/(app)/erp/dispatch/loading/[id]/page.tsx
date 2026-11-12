"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type LoadingOrder, num } from "@/lib/sales-api";
import { Banner, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type Act, ActionDialog, Facts, SalesBadge, Timeline } from "@/components/sales-ui";

export default function LoadingOrderPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><LoadingDetail /></ErpGate>;
}

/**
 * One truck, one warehouse, one order: every step from the loading bay to
 * the customer's signature, each done by the person whose job it is.
 */
function LoadingDetail() {
  const { t, locale, toast } = useApp();
  const { can, has } = useErp();
  const { id } = useParams<{ id: string }>();
  const [lo, setLo] = useState<LoadingOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [act, setAct] = useState<Act | null>(null);
  const [loaded, setLoaded] = useState<Record<number, string>>({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [pod, setPod] = useState({ received_by_name: "", received_date: "", remark: "" });
  const [received, setReceived] = useState<Record<number, string>>({});
  const [decision, setDecision] = useState<"return" | "write_off">("return");

  const apply = useCallback((data: LoadingOrder) => {
    setLo(data);
    setLoaded(Object.fromEntries((data.lines ?? []).map((l) => [l.id, l.quantity_loaded === null ? "" : String(num(l.quantity_loaded))])));
  }, []);
  const load = useCallback(() => {
    api.get<{ data: LoadingOrder }>(`/erp/dispatch/loading-orders/${id}`).then((r) => apply(r.data)).catch((e) => setError(e.message));
  }, [id, apply]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!lo) return <LoadingBlock rows={6} />;

  const path = `/erp/dispatch/loading-orders/${lo.id}`;
  const lines = lo.lines ?? [];
  const open = lo.status === "open";
  const isLoaded = lo.status === "loaded";
  const dirty = lines.some((l) => (l.quantity_loaded === null ? "" : String(num(l.quantity_loaded))) !== (loaded[l.id] ?? ""));
  const allEntered = lines.every((l) => l.quantity_loaded !== null);
  const short = lines.some((l) => l.quantity_received !== null && num(l.quantity_received) < num(l.quantity_loaded));

  async function saveLoaded() {
    setSaving(true); setSaveError(null);
    try {
      const r = await api.put<{ message: string; data: LoadingOrder }>(`${path}/loaded`, { quantities: Object.fromEntries(Object.entries(loaded).map(([k, v]) => [k, v === "" ? null : Number(v)])) });
      apply(r.data);
      toast(r.message, undefined, "ok");
    } catch (e) {
      setSaveError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  function openPod() {
    setPod({ received_by_name: "", received_date: new Date().toISOString().slice(0, 10), remark: "" });
    setReceived(Object.fromEntries(lines.map((l) => [l.id, String(num(l.quantity_loaded))])));
    setAct({ key: "deliver", path: `${path}/deliver`, label: t("salRecordDelivery"), icon: "ph-hand-arrow-down", title: t("salProofOfDelivery"), sub: t("salPodSub") });
  }

  const body = act?.key === "deliver"
    ? () => ({ ...pod, remark: pod.remark || null, quantities: Object.fromEntries(Object.entries(received).map(([k, v]) => [k, Number(v || 0)])) })
    : act?.key === "resolve" ? (note: string) => ({ decision, note })
      : act?.key === "driver" || act?.key === "security" ? (name: string) => ({ name: name || null }) : undefined;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/dispatch/loading" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salLoadingOrders")}</Link>}
        kicker={t("salLoadingOrder")} title={<span className="tnum">{lo.number}</span>}
        subtitle={<>{lo.customer?.name} · {lo.warehouse?.name} · {formatDate(lo.planned_date, locale)}</>}
        actions={<>
          <SalesBadge status={lo.status} />
          {open && can("dispatch.load") && <button className="btn btn-secondary" onClick={() => setAct({ key: "cancel", path: `${path}/cancel`, label: t("salCancelDoc"), icon: "ph-x-circle", tone: "warn", title: fill(t("salCancelLoadingQ"), { number: lo.number }) })}>{t("salCancelDoc")}</button>}
          {open && can("dispatch.load") && (
            <button className="btn btn-primary" disabled={!allEntered || dirty} title={!allEntered || dirty ? t("salSaveLoadedFirst") : undefined}
              onClick={() => setAct({ key: "confirm", path: `${path}/confirm-loading`, label: t("salConfirmLoading"), icon: "ph-package", title: fill(t("salConfirmLoadingQ"), { number: lo.number }), sub: t("salConfirmLoadingSub") })}>
              <Icon name="ph-check-circle" size={18} /> {t("salConfirmLoading")}
            </button>
          )}
          {isLoaded && !lo.driver_confirmed_at && can("dispatch.load") && <button className="btn btn-secondary" onClick={() => setAct({ key: "driver", path: `${path}/confirm-driver`, label: t("salConfirm"), icon: "ph-steering-wheel", title: t("salDriverConfirms"), sub: fill(t("salDriverConfirmsSub"), { name: lo.driver_name ?? "-" }), reason: { label: t("salDriverName"), required: !lo.driver_name, min: 2 } })}>{t("salDriverConfirms")}</button>}
          {isLoaded && !lo.security_confirmed_at && can("dispatch.gatepass") && <button className="btn btn-secondary" onClick={() => setAct({ key: "security", path: `${path}/confirm-security`, label: t("salConfirm"), icon: "ph-shield-check", title: t("salSecurityConfirms"), sub: t("salSecurityConfirmsSub"), reason: { label: t("salSecurityName"), required: false } })}>{t("salSecurityConfirms")}</button>}
          {isLoaded && lo.driver_confirmed_at && lo.security_confirmed_at && !lo.delivery_note_number && can("dispatch.load") && <button className="btn btn-primary" onClick={() => setAct({ key: "dn", path: `${path}/delivery-note`, label: t("salIssueDeliveryNote"), icon: "ph-file-text", title: t("salIssueDeliveryNote") })}><Icon name="ph-file-text" size={18} /> {t("salIssueDeliveryNote")}</button>}
          {isLoaded && lo.delivery_note_number && can("dispatch.gatepass") && <button className="btn btn-primary" onClick={() => setAct({ key: "gp", path: `${path}/gate-pass`, label: t("salIssueGatePass"), icon: "ph-door-open", title: t("salIssueGatePass"), sub: t("salIssueGatePassSub") })}><Icon name="ph-door-open" size={18} /> {t("salIssueGatePass")}</button>}
          {lo.status === "dispatched" && can("dispatch.deliver") && <button className="btn btn-primary" onClick={openPod}><Icon name="ph-hand-arrow-down" size={18} /> {t("salRecordDelivery")}</button>}
          {lo.discrepancy_status === "open" && can("dispatch.resolve") && <button className="btn btn-primary" onClick={() => { setDecision("return"); setAct({ key: "resolve", path: `${path}/resolve`, label: t("salDecide"), icon: "ph-scales", title: t("salResolveShort"), sub: t("salResolveShortSub"), reason: { label: t("salWhatHappened"), required: true } }); }}>{t("salResolveShort")}</button>}
          {lo.delivery_note_number && <Link className="btn btn-secondary" href={`/erp/dispatch/loading/${lo.id}/print?doc=delivery-note`}><Icon name="ph-printer" size={17} /> {t("salDeliveryNote")}</Link>}
          {lo.gate_pass_number && <Link className="btn btn-secondary" href={`/erp/dispatch/loading/${lo.id}/print?doc=gate-pass`}><Icon name="ph-printer" size={17} /> {t("salGatePass")}</Link>}
        </>} />

      {lo.discrepancy_status === "open" && <Banner tone="danger" icon="ph-warning-diamond" title={t("salShortOpen")}>{t("salShortOpenBody")}</Banner>}
      {open && !allEntered && <Banner icon="ph-info" title={t("salEnterLoadedTitle")}>{t("salEnterLoadedBody")}</Banner>}

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} subtitle={t("salFourQuantities")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr>
                <th>{t("erpProduct")}</th><th className="num">{t("salQtyOrdered")}</th><th className="num">{t("salQtyApproved")}</th>
                <th className="num" style={{ width: open ? 130 : undefined }}>{t("salQtyLoaded")}</th><th className="num">{t("salQtyReceived")}</th>
                {open && <th className="num">{t("salAvailableHere")}</th>}
              </tr></thead>
              <tbody>
                {lines.map((l) => {
                  const avail = lo.availability?.[l.product_id]?.[lo.warehouse_id];
                  const gap = l.quantity_received !== null && num(l.quantity_received) < num(l.quantity_loaded);
                  return (
                    <tr key={l.id}>
                      <td><span className="erp-cell-title">{l.product?.name}</span><span className="erp-cell-sub tnum">{l.product?.sku}</span></td>
                      <td className="num">{qty(l.quantity_ordered)}</td>
                      <td className="num">{qty(l.quantity_approved)}</td>
                      <td className="num">
                        {open && can("dispatch.load")
                          ? <input className="input tnum" type="number" min={0} max={num(l.quantity_approved)} step="any" aria-label={t("salQtyLoaded")} value={loaded[l.id] ?? ""} onChange={(e) => setLoaded((x) => ({ ...x, [l.id]: e.target.value }))} />
                          : l.quantity_loaded === null ? "-" : qty(l.quantity_loaded)}
                      </td>
                      <td className="num" style={gap ? { color: "var(--st-bad-fg)", fontWeight: 600 } : undefined}>{l.quantity_received === null ? "-" : qty(l.quantity_received)}</td>
                      {open && <td className="num">{avail ? qty(avail.on_hand) : "0"}</td>}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {open && can("dispatch.load") && (
            <div className="erp-lines-foot">
              {saveError ? <span className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {saveError}</span> : <span className="erp-muted">{t("salLoadedHint")}</span>}
              <button className="btn btn-secondary btn-sm" disabled={saving || !dirty} onClick={saveLoaded}><Icon name="ph-floppy-disk" size={16} /> {t("salSaveLoaded")}</button>
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("salTransport")}>
          <Facts rows={[
            [t("salOrder"), lo.order && (has("sales") && can("sales.view") ? <Link href={`/erp/sales/orders/${lo.order.id}`} className="tnum">{lo.order.number}</Link> : lo.order.number)],
            [t("salVehicle"), lo.vehicle_number],
            [t("salDriver"), lo.driver_name],
            [t("salDestination"), lo.destination],
            [t("salDeliveryNote"), lo.delivery_note_number],
            [t("salGatePass"), lo.gate_pass_number],
            [t("salStockIssue"), lo.stock_document && (can("inventory.view") ? <Link href={`/erp/documents/${lo.stock_document.id}`} className="tnum">{lo.stock_document.number}</Link> : lo.stock_document.number)],
            [t("salNotes"), lo.notes],
          ]} />
        </GlassCard>

        <GlassCard title={t("salTimeline")}>
          <Timeline steps={[
            { label: t("salStepCreated"), at: lo.created_at, who: lo.creator?.name },
            { label: t("salStepLoadedStore"), at: lo.loaded_at, who: lo.loader?.name },
            { label: t("salStepDriver"), at: lo.driver_confirmed_at, who: lo.driver_confirmed_name },
            { label: t("salStepSecurity"), at: lo.security_confirmed_at, who: lo.security_confirmed_name },
            { label: t("salStepDeliveryNote"), at: lo.delivery_note_issued_at, who: lo.delivery_note_number },
            { label: t("salStepGatePass"), at: lo.gate_pass_issued_at, who: lo.gate_pass_issuer?.name },
            { label: t("salStepDelivered"), at: lo.pod_recorded_at, who: lo.received_by_name },
            ...(lo.discrepancy_status && lo.discrepancy_status !== "open" ? [{ label: t(lo.discrepancy_status === "returned" ? "salShortReturned" : "salShortWrittenOff"), at: lo.discrepancy_resolved_at, who: lo.resolver?.name }] : []),
          ]} />
        </GlassCard>

        {lo.status === "delivered" && (
          <GlassCard title={t("salProofOfDelivery")}>
            <Facts rows={[
              [t("salReceivedBy"), lo.received_by_name],
              [t("salReceivedOn"), formatDate(lo.received_date, locale)],
              [t("salRemark"), lo.delivery_remark],
              [t("salShortage"), short ? t(lo.discrepancy_status === "open" ? "salShortOpen" : lo.discrepancy_status === "returned" ? "salShortReturned" : "salShortWrittenOff") : t("salNoShortage")],
              [t("salDecisionNote"), lo.discrepancy_note],
              [t("salReturnDocument"), lo.return_document && (can("inventory.view") ? <Link href={`/erp/documents/${lo.return_document.id}`} className="tnum">{lo.return_document.number}</Link> : lo.return_document.number)],
            ]} />
          </GlassCard>
        )}
      </div>

      <ActionDialog act={act} onClose={() => setAct(null)} onDone={load} body={body}>
        {act?.key === "deliver" && (
          <div className="sal-dialog-lines">
            <div className="erp-form-grid">
              <Field label={t("salReceivedBy")} htmlFor="pod-name" required>
                <input id="pod-name" className="input" value={pod.received_by_name} onChange={(e) => setPod((p) => ({ ...p, received_by_name: e.target.value }))} />
              </Field>
              <Field label={t("salReceivedOn")} htmlFor="pod-date" required>
                <input id="pod-date" className="input" type="date" max={new Date().toISOString().slice(0, 10)} value={pod.received_date} onChange={(e) => setPod((p) => ({ ...p, received_date: e.target.value }))} />
              </Field>
            </div>
            {lines.map((l) => (
              <Field key={l.id} label={`${l.product?.name} (${t("salQtyLoaded")} ${qty(l.quantity_loaded)})`} htmlFor={`rc-${l.id}`}>
                <input id={`rc-${l.id}`} className="input tnum" type="number" min={0} max={num(l.quantity_loaded)} step="any" value={received[l.id] ?? ""} onChange={(e) => setReceived((r) => ({ ...r, [l.id]: e.target.value }))} />
              </Field>
            ))}
            <Field label={t("salRemark")} htmlFor="pod-remark" hint={t("erpOptional")}>
              <input id="pod-remark" className="input" value={pod.remark} onChange={(e) => setPod((p) => ({ ...p, remark: e.target.value }))} />
            </Field>
            {lines.some((l) => num(received[l.id]) < num(l.quantity_loaded)) && <p className="field-error"><Icon name="ph-warning" size={15} /> {t("salShortWarning")}</p>}
          </div>
        )}
        {act?.key === "resolve" && (
          <Field label={t("salDecision")} htmlFor="res-dec">
            <select id="res-dec" className="input" value={decision} onChange={(e) => setDecision(e.target.value as "return" | "write_off")}>
              <option value="return">{t("salDecisionReturn")}</option>
              <option value="write_off">{t("salDecisionWriteOff")}</option>
            </select>
          </Field>
        )}
      </ActionDialog>
    </div>
  );
}
