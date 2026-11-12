"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { Comparison, Order, Rfq } from "@/lib/procurement-api";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type ActionSpec, ActionDialog, BackLink, Facts, ProcStatus, useMoney } from "@/components/procurement-ui";

export default function RfqPage() {
  return <ErpGate module="procurement" permission="procurement.view"><RfqDetail /></ErpGate>;
}

function RfqDetail() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [rfq, setRfq] = useState<Rfq | null>(null);
  const [cmp, setCmp] = useState<Comparison | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionSpec | null>(null);
  const [quoting, setQuoting] = useState<number | null>(null);
  const [awarding, setAwarding] = useState<number | null>(null);
  const [ordering, setOrdering] = useState(false);

  const load = useCallback(() => {
    api.get<{ data: Rfq }>(`/erp/procurement/rfqs/${id}`).then((r) => setRfq(r.data)).catch((e) => setError(e.message));
    api.get<{ data: Comparison }>(`/erp/procurement/rfqs/${id}/comparison`).then((r) => setCmp(r.data)).catch(() => undefined);
  }, [id]);
  useEffect(load, [load]);

  async function raiseOrder() {
    if (!rfq?.selected_quotation_id) return;
    setOrdering(true);
    try {
      const r = await api.post<{ data: Order }>("/erp/procurement/orders", { supplier_quotation_id: rfq.selected_quotation_id });
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/procurement/orders/${r.data.id}`);
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e), undefined, "bad");
    } finally {
      setOrdering(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!rfq || !cmp) return <LoadingBlock rows={6} />;

  const base = `/erp/procurement/rfqs/${rfq.id}`;
  const mayQuote = can("procurement.quote");
  const quoted = new Set(cmp.quotations.map((q) => q.supplier.id));

  return (
    <div className="erp-page">
      <PageHeader
        back={<BackLink href="/erp/procurement/rfqs" label={t("prcRfqs")} />}
        kicker={rfq.requisition ? `${t("prcRequisition")} ${rfq.requisition.number}` : t("prcRfq")}
        title={<span className="tnum">{rfq.number}</span>}
        subtitle={<>{rfq.title} · {formatDate(rfq.issue_date, locale)}{rfq.closing_date ? ` → ${formatDate(rfq.closing_date, locale)}` : ""}</>}
        actions={<>
          <ProcStatus status={rfq.status} />
          {rfq.status === "draft" && mayQuote && (
            <button className="btn btn-primary" onClick={() => setAction({ key: "send", label: t("prcSendRfq"), title: fill(t("prcSendRfqQ"), { number: rfq.number }), icon: "ph-paper-plane-tilt", path: `${base}/send` })}>
              <Icon name="ph-paper-plane-tilt" size={17} /> {t("prcSendRfq")}
            </button>
          )}
          {rfq.status === "awarded" && can("procurement.order") && (
            <button className="btn btn-primary" disabled={ordering} onClick={raiseOrder}><Icon name="ph-shopping-cart" size={17} /> {t("prcRaiseOrder")}</button>
          )}
          {["draft", "sent"].includes(rfq.status) && mayQuote && (
            <button className="btn btn-secondary" onClick={() => setAction({ key: "cancel", label: t("prcCancelDoc"), title: fill(t("prcCancelQ"), { number: rfq.number }), icon: "ph-x-circle", tone: "warn", path: `${base}/cancel`, danger: true })}>
              {t("prcCancelDoc")}
            </button>
          )}
        </>}
      />

      <GlassCard title={t("prcComparison")} subtitle={t("prcComparisonSub")} pad={false}>
        {cmp.quotations.length === 0 ? <EmptyState icon="ph-scales" title={t("prcNoQuotesYet")} body={rfq.status === "draft" ? t("prcSendFirst") : undefined} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead>
                <tr>
                  <th>{t("prcItem")}</th>
                  <th className="num">{t("erpQuantity")}</th>
                  {cmp.quotations.map((q) => (
                    <th key={q.id} className="num">
                      {q.supplier.name}
                      {q.status === "selected" && <> <Badge tone="ok">{t("prcStSelected")}</Badge></>}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {cmp.lines.map((l) => (
                  <tr key={l.id}>
                    <td>{l.description}</td>
                    <td className="num">{qty(l.quantity)}</td>
                    {l.prices.map((p) => (
                      <td key={p.quotation_id} className="num" style={p.lowest ? { fontWeight: 700, color: "var(--st-ok-fg)" } : undefined}>
                        {p.unit_price === null ? "-" : amount(p.unit_price)}
                        {p.lowest && <span className="erp-cell-sub">{t("prcLowest")}</span>}
                      </td>
                    ))}
                  </tr>
                ))}
                <tr>
                  <th colSpan={2}>{t("prcSubtotal")}</th>
                  {cmp.quotations.map((q) => <td key={q.id} className="num">{money(q.subtotal)}</td>)}
                </tr>
                <tr>
                  <th colSpan={2}>{t("prcVat")}</th>
                  {cmp.quotations.map((q) => <td key={q.id} className="num">{money(q.vat_amount)}</td>)}
                </tr>
                <tr>
                  <th colSpan={2}>{t("erpTotal")}</th>
                  {cmp.quotations.map((q) => (
                    <td key={q.id} className="num" style={q.lowest ? { fontWeight: 700, color: "var(--st-ok-fg)" } : { fontWeight: 600 }}>
                      {money(q.total)}{q.lowest && <span className="erp-cell-sub">{t("prcLowestTotal")}</span>}
                    </td>
                  ))}
                </tr>
                <tr>
                  <th colSpan={2}>{t("prcLeadTime")}</th>
                  {cmp.quotations.map((q) => <td key={q.id} className="num">{q.lead_time_days !== null ? fill(t("prcDays"), { n: q.lead_time_days }) : "-"}</td>)}
                </tr>
                <tr>
                  <th colSpan={2}>{t("prcPaymentTerms")}</th>
                  {cmp.quotations.map((q) => <td key={q.id} className="num">{q.payment_terms ?? "-"}</td>)}
                </tr>
                <tr>
                  <th colSpan={2}>{t("prcDeliveryTerms")}</th>
                  {cmp.quotations.map((q) => <td key={q.id} className="num">{q.delivery_terms ?? "-"}</td>)}
                </tr>
                {rfq.status === "sent" && mayQuote && (
                  <tr>
                    <th colSpan={2} />
                    {cmp.quotations.map((q) => (
                      <td key={q.id} className="num">
                        <button className="btn btn-primary btn-sm" onClick={() => setAwarding(q.id)}>{t("prcSelectWinner")}</button>
                      </td>
                    ))}
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prcInvitedSuppliers")} pad={false}>
          <ul className="erp-list">
            {cmp.invited.map((s) => (
              <li key={s.id} className="erp-list-row" style={{ cursor: "default" }}>
                <span className="erp-list-icon"><Icon name="ph-truck" size={18} /></span>
                <span className="erp-list-main"><span className="erp-list-title">{s.name}</span><span className="erp-list-sub">{s.code}</span></span>
                {quoted.has(s.id) ? <Badge tone="ok">{t("prcQuoted")}</Badge> : <Badge tone="neutral">{t("prcAwaitingQuote")}</Badge>}
                {rfq.status === "sent" && mayQuote && (
                  <button className="btn btn-secondary btn-sm" onClick={() => setQuoting(s.id)}>{quoted.has(s.id) ? t("erpEdit") : t("prcRecordQuote")}</button>
                )}
              </li>
            ))}
          </ul>
        </GlassCard>
        <GlassCard title={t("erpStatus")}>
          <Facts rows={[
            [t("erpPrepared"), rfq.creator?.name],
            [t("prcRequisition"), rfq.requisition ? <Link className="tnum" href={`/erp/procurement/requisitions/${rfq.requisition.id}`}>{rfq.requisition.number}</Link> : null],
            [t("prcAwardedBy"), rfq.awarder ? `${rfq.awarder.name} · ${formatDateTime(rfq.awarded_at, locale)}` : null],
            [t("prcSelectionReason"), rfq.selection_reason],
            [t("erpNotes"), rfq.notes],
          ]} />
        </GlassCard>
      </div>

      {quoting !== null && <QuoteDialog rfq={rfq} supplierId={quoting} onClose={() => setQuoting(null)} onDone={() => { setQuoting(null); toast(t("prcQuoteRecorded"), undefined, "ok"); load(); }} />}
      <AwardDialog rfq={rfq} quotationId={awarding} comparison={cmp} onClose={() => setAwarding(null)} onDone={(m) => { setAwarding(null); toast(m, undefined, "ok"); load(); }} />
      <ActionDialog action={action} onClose={() => setAction(null)} onDone={(m) => { toast(m, undefined, "ok"); setAction(null); load(); }} />
    </div>
  );
}

function QuoteDialog({ rfq, supplierId, onClose, onDone }: { rfq: Rfq; supplierId: number; onClose: () => void; onDone: () => void }) {
  const { t } = useApp();
  const existing = rfq.quotations?.find((q) => q.supplier_id === supplierId);
  const supplier = rfq.suppliers?.find((s) => s.id === supplierId);
  const [reference, setReference] = useState(existing?.reference ?? "");
  const [lead, setLead] = useState(existing?.lead_time_days != null ? String(existing.lead_time_days) : "");
  const [validUntil, setValidUntil] = useState(existing?.valid_until?.slice(0, 10) ?? "");
  const [payment, setPayment] = useState(existing?.payment_terms ?? "");
  const [delivery, setDelivery] = useState(existing?.delivery_terms ?? "");
  const [prices, setPrices] = useState<Record<number, { price: string; vat: string }>>(() => Object.fromEntries((rfq.lines ?? []).map((l) => {
    const q = existing?.lines?.find((x) => x.purchase_rfq_line_id === l.id);
    return [l.id, { price: q ? String(Number(q.unit_price)) : "", vat: q ? String(Number(q.vat_rate)) : "18" }];
  })));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  async function save() {
    setBusy(true); setError(null);
    try {
      await api.post(`/erp/procurement/rfqs/${rfq.id}/quotations`, {
        supplier_id: supplierId, reference: reference || null, lead_time_days: lead === "" ? null : Number(lead),
        valid_until: validUntil || null, payment_terms: payment || null, delivery_terms: delivery || null,
        lines: (rfq.lines ?? []).map((l) => ({ purchase_rfq_line_id: l.id, unit_price: prices[l.id]?.price === "" ? null : Number(prices[l.id]?.price), vat_rate: Number(prices[l.id]?.vat || 0) })),
      });
      onDone();
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open wide onClose={onClose} busy={busy} icon="ph-currency-circle-dollar" title={fill(t("prcQuoteFrom"), { supplier: supplier?.name ?? "" })}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpBack")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || Object.values(prices).some((p) => p.price === "")}>{t("prcSaveQuote")}</button>
      </>}>
      <div className="erp-form-grid">
        <Field label={t("erpReference")} htmlFor="q-ref"><input id="q-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)} /></Field>
        <Field label={t("prcLeadTimeDays")} htmlFor="q-lead" error={error?.field("lead_time_days")}><input id="q-lead" className="input" type="number" min={0} value={lead} onChange={(e) => setLead(e.target.value)} /></Field>
        <Field label={t("prcValidUntil")} htmlFor="q-valid"><input id="q-valid" className="input" type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} /></Field>
        <Field label={t("prcPaymentTerms")} htmlFor="q-pay"><input id="q-pay" className="input" value={payment} onChange={(e) => setPayment(e.target.value)} /></Field>
        <Field label={t("prcDeliveryTerms")} htmlFor="q-del"><input id="q-del" className="input" value={delivery} onChange={(e) => setDelivery(e.target.value)} /></Field>
      </div>
      <div className="vf-table-wrap">
        <table className="table vf-table">
          <thead><tr><th>{t("prcItem")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("prcUnitPrice")}</th><th className="num">{t("prcVatRate")}</th></tr></thead>
          <tbody>
            {(rfq.lines ?? []).map((l) => (
              <tr key={l.id}>
                <td>{l.description}</td>
                <td className="num">{qty(l.quantity)}</td>
                <td className="num"><input className="input tnum" type="number" min={0} step="any" aria-label={t("prcUnitPrice")} value={prices[l.id]?.price ?? ""} onChange={(e) => setPrices((p) => ({ ...p, [l.id]: { ...p[l.id], price: e.target.value } }))} /></td>
                <td className="num"><input className="input tnum" type="number" min={0} max={100} step="any" aria-label={t("prcVatRate")} value={prices[l.id]?.vat ?? ""} onChange={(e) => setPrices((p) => ({ ...p, [l.id]: { ...p[l.id], vat: e.target.value } }))} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error.message}</div>}
    </Dialog>
  );
}

function AwardDialog({ rfq, quotationId, comparison, onClose, onDone }: {
  rfq: Rfq; quotationId: number | null; comparison: Comparison; onClose: () => void; onDone: (message: string) => void;
}) {
  const { t } = useApp();
  const money = useMoney();
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const q = comparison.quotations.find((x) => x.id === quotationId);

  async function award() {
    setBusy(true); setError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/procurement/rfqs/${rfq.id}/award`, { quotation_id: quotationId, reason });
      setReason("");
      onDone(r.message);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={quotationId !== null} onClose={onClose} busy={busy} icon="ph-trophy" tone="ok" title={fill(t("prcAwardQ"), { supplier: q?.supplier.name ?? "" })}
      sub={q && !q.lowest ? t("prcNotLowestWarning") : undefined}
      summary={q ? [{ label: t("erpTotal"), value: money(q.total) }, { label: t("prcLeadTime"), value: q.lead_time_days !== null ? fill(t("prcDays"), { n: q.lead_time_days }) : "-" }] : undefined}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpBack")}</button>
        <button className="btn btn-primary" onClick={award} disabled={busy || reason.trim().length < 3}>{t("prcSelectWinner")}</button>
      </>}>
      <Field label={t("prcSelectionReason")} htmlFor="award-reason" required>
        <textarea id="award-reason" className="input" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
      </Field>
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error}</div>}
    </Dialog>
  );
}
