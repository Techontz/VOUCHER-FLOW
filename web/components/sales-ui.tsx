"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import type { MessageKey } from "@/lib/i18n";
import { lineAmounts, type Lookups, num, type Quotation, type SalesOrder, type SalesStatus, STATUS_LABEL, statusTone, type Totals, useSalesLookups } from "@/lib/sales-api";
import { Badge, Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";

/*
 * Pieces the sales and dispatch screens share: the status badge, money, the
 * totals block, a confirm-with-reason dialog and the quotation/order form.
 */

export function SalesBadge({ status }: { status: SalesStatus }) {
  const { t } = useApp();
  return <Badge tone={statusTone(status)} dot>{t(STATUS_LABEL[status] ?? "salStDraft")}</Badge>;
}

export function useCurrency(): string {
  const { config } = useErp();
  return config?.settings.base_currency ?? "TZS";
}

export function Money({ value, strong }: { value: string | number | null | undefined; strong?: boolean }) {
  const currency = useCurrency();
  const body = <>{currency} {amount(num(value))}</>;
  return <span className="tnum">{strong ? <strong>{body}</strong> : body}</span>;
}

export function TotalsBlock({ totals, extra }: { totals: Totals; extra?: { label: string; value: ReactNode }[] }) {
  const { t } = useApp();
  return (
    <dl className="erp-review sal-totals">
      <dt>{t("salSubtotal")}</dt><dd><Money value={totals.subtotal} /></dd>
      {num(totals.discount_total) > 0 && <><dt>{t("salDiscount")}</dt><dd>- <Money value={totals.discount_total} /></dd></>}
      <dt>{t("salVat")}</dt><dd><Money value={totals.tax_total} /></dd>
      <dt>{t("salTotal")}</dt><dd><Money value={totals.total} strong /></dd>
      {extra?.map((row) => <span key={row.label} style={{ display: "contents" }}><dt>{row.label}</dt><dd>{row.value}</dd></span>)}
    </dl>
  );
}

export interface Act {
  key: string; path: string; label: string; icon: string; tone?: "info" | "warn";
  title: string; sub?: string; reason?: { label: string; required: boolean; min?: number };
  /** Builds the body from the typed reason, when the endpoint names it differently. */
  body?: (reason: string) => unknown;
  then?: (data: { message: string; data: { id: number } }) => void;
}

/**
 * One confirmation dialog for every state change on a sales document. The
 * API's sentence is shown as-is when it refuses, so the person reads exactly
 * why (credit limit, payment not verified, not enough stock).
 */
export function ActionDialog({ act, onClose, onDone, children, body }: {
  act: Act | null; onClose: () => void; onDone: () => void; children?: ReactNode;
  /** Builds the request from the screen's current inputs; wins over act.body. */
  body?: (reason: string) => unknown;
}) {
  const { t, toast } = useApp();
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    if (!act) return;
    setBusy(true); setError(null);
    try {
      const build = body ?? act.body;
      const payload = build ? build(reason) : act.reason ? { reason } : undefined;
      const r = await api.post<{ message: string; data: { id: number } }>(act.path, payload);
      toast(r.message, undefined, "ok");
      setReason("");
      if (act.then) act.then(r); else onDone();
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const min = act?.reason?.min ?? 3;
  return (
    <Dialog open={act !== null} onClose={() => { setError(null); onClose(); }} busy={busy} icon={act?.icon} tone={act?.tone ?? "info"}
      title={act?.title ?? ""} sub={act?.sub}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpBack")}</button>
        <button className={act?.tone === "warn" ? "btn btn-danger" : "btn btn-primary"} onClick={run}
          disabled={busy || (!!act?.reason?.required && reason.trim().length < min)}>{act?.label}</button>
      </>}>
      {children}
      {act?.reason && (
        <Field label={act.reason.label} htmlFor="sal-reason" required={act.reason.required}>
          <textarea id="sal-reason" className="input" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
        </Field>
      )}
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error}</div>}
    </Dialog>
  );
}

/** A small "label: value" list for a side card. */
export function Facts({ rows }: { rows: [string, ReactNode][] }) {
  return (
    <dl className="erp-review">
      {rows.filter(([, v]) => v !== null && v !== undefined && v !== "").map(([k, v]) => <span key={k} style={{ display: "contents" }}><dt>{k}</dt><dd>{v}</dd></span>)}
    </dl>
  );
}

/** A dated step in a document's life, shown in a timeline card. */
export function Timeline({ steps }: { steps: { label: string; at: string | null | undefined; who?: string | null; done?: boolean }[] }) {
  const { locale } = useApp();
  return (
    <ol className="sal-timeline">
      {steps.map((s) => (
        <li key={s.label} data-done={s.done ?? !!s.at ? "" : undefined}>
          <span className="sal-timeline-dot" aria-hidden="true" />
          <span className="sal-timeline-label">{s.label}</span>
          <span className="erp-muted">{s.at ? new Date(s.at).toLocaleString(locale === "sw" ? "sw-TZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "-"}{s.who ? ` · ${s.who}` : ""}</span>
        </li>
      ))}
    </ol>
  );
}

/* ───────────────────────────────────────── quotation and order form ── */

interface FormLine { product_id: string; quantity: string; unit_price: string; discount_percent: string; tax_rate: string; description: string }

const blank = (tax: number): FormLine => ({ product_id: "", quantity: "", unit_price: "", discount_percent: "", tax_rate: String(tax), description: "" });

/**
 * Prepares or edits a draft quotation or order. Prices come from the
 * customer's price list as soon as a product is picked (the API applies the
 * same rule if the price is left blank); totals are computed exactly as the
 * server will store them.
 */
export function SalesDocForm({ kind, existing }: { kind: "quotation" | "order"; existing?: Quotation | SalesOrder }) {
  const { lookups, error } = useSalesLookups();
  if (error) return <ErrorState message={error} />;
  if (!lookups) return <LoadingBlock rows={5} />;
  return <SalesDocFormBody kind={kind} existing={existing} lookups={lookups} />;
}

function SalesDocFormBody({ kind, existing, lookups }: { kind: "quotation" | "order"; existing?: Quotation | SalesOrder; lookups: Lookups }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const currency = useCurrency();
  // The screens live at the same paths as the API they call.
  const base = kind === "quotation" ? "/erp/sales/quotations" : "/erp/sales/orders";
  const order = kind === "order" ? (existing as SalesOrder | undefined) : undefined;
  const quote = kind === "quotation" ? (existing as Quotation | undefined) : undefined;

  const [customerId, setCustomerId] = useState(existing ? String(existing.customer_id) : "");
  const [date, setDate] = useState((order?.order_date ?? quote?.quote_date)?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [second, setSecond] = useState((order?.required_date ?? quote?.valid_until)?.slice(0, 10) ?? "");
  const [warehouseId, setWarehouseId] = useState(order?.warehouse_id ? String(order.warehouse_id) : "");
  const [address, setAddress] = useState(order?.delivery_address ?? "");
  const [notes, setNotes] = useState(existing?.notes ?? "");
  const [lines, setLines] = useState<FormLine[]>(() => {
    const src = existing?.lines as (Quotation["lines"] | SalesOrder["lines"]) | undefined;
    if (!src?.length) return [blank(lookups.tax_rate)];
    return src.map((l) => ({
      product_id: String(l.product_id),
      quantity: String(Number("quantity_ordered" in l ? l.quantity_ordered : l.quantity)),
      unit_price: String(Number(l.unit_price)), discount_percent: Number(l.discount_percent) ? String(Number(l.discount_percent)) : "",
      tax_rate: String(Number(l.tax_rate)), description: l.description ?? "",
    }));
  });
  const [prices, setPrices] = useState<Record<string, { price: number; source: string }>>({});
  const [listName, setListName] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const customer = lookups.customers.find((c) => String(c.id) === customerId);
  const products = useMemo(() => new Map(lookups.products.map((p) => [String(p.id), p])), [lookups.products]);

  async function pickCustomer(id: string) {
    setCustomerId(id);
    const c = lookups.customers.find((x) => String(x.id) === id);
    if (c && !address) setAddress([c.address, c.city].filter(Boolean).join(", "));
    if (!id) return;
    try {
      const r = await api.get<{ data: Record<string, { price: number; source: string }>; price_list: { name: string } | null }>("/erp/sales/prices", { customer_id: id, date });
      setPrices(r.data); setListName(r.price_list?.name ?? null);
      setLines((all) => all.map((l) => (l.product_id && r.data[l.product_id] ? { ...l, unit_price: String(r.data[l.product_id].price) } : l)));
    } catch { /* prices stay as typed */ }
  }

  const setLine = (i: number, patch: Partial<FormLine>) => setLines((all) => all.map((l, j) => (j === i ? { ...l, ...patch } : l)));

  const computed = lines.map((l) => lineAmounts(num(l.quantity), num(l.unit_price), num(l.discount_percent), num(l.tax_rate)));
  const totals = computed.reduce((s, a) => ({ subtotal: s.subtotal + a.subtotal, discount: s.discount + a.discount, tax: s.tax + a.tax, total: s.total + a.total }), { subtotal: 0, discount: 0, tax: 0, total: 0 });

  async function save() {
    setBusy(true); setFormError(null);
    const payload: Record<string, unknown> = {
      customer_id: Number(customerId), notes: notes || null,
      lines: lines.filter((l) => l.product_id).map((l) => ({
        product_id: Number(l.product_id), quantity: Number(l.quantity),
        unit_price: l.unit_price === "" ? null : Number(l.unit_price),
        discount_percent: l.discount_percent === "" ? 0 : Number(l.discount_percent),
        tax_rate: l.tax_rate === "" ? null : Number(l.tax_rate), description: l.description || null,
      })),
    };
    if (kind === "quotation") Object.assign(payload, { quote_date: date, valid_until: second || null });
    else Object.assign(payload, { order_date: date, required_date: second || null, warehouse_id: warehouseId ? Number(warehouseId) : null, delivery_address: address || null });
    try {
      const r = existing
        ? await api.put<{ data: { id: number; number: string } }>(`${base}/${existing.id}`, payload)
        : await api.post<{ data: { id: number; number: string } }>(base, payload);
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`${base}/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  const title: MessageKey = kind === "quotation" ? (existing ? "salEditQuotation" : "salNewQuotation") : (existing ? "salEditOrder" : "salNewOrder");

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={existing ? `${base}/${existing.id}` : base} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t(kind === "quotation" ? "salQuotations" : "salOrders")}</Link>}
        kicker={existing?.number} title={t(title)} subtitle={t(kind === "quotation" ? "salQuotationFormSub" : "salOrderFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("salCustomer")} htmlFor="s-cust" required error={formError?.field("customer_id")}>
            <select id="s-cust" className="input" value={customerId} onChange={(e) => void pickCustomer(e.target.value)}>
              <option value="">{t("salPickCustomer")}</option>
              {lookups.customers.map((c) => <option key={c.id} value={c.id}>{c.name} · {c.code}</option>)}
            </select>
          </Field>
          <Field label={t(kind === "quotation" ? "salQuoteDate" : "salOrderDate")} htmlFor="s-date" error={formError?.field(kind === "quotation" ? "quote_date" : "order_date")}>
            <input id="s-date" className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label={t(kind === "quotation" ? "salValidUntil" : "salRequiredDate")} htmlFor="s-date2" hint={t("erpOptional")} error={formError?.field(kind === "quotation" ? "valid_until" : "required_date")}>
            <input id="s-date2" className="input" type="date" value={second} onChange={(e) => setSecond(e.target.value)} />
          </Field>
          {kind === "order" && (
            <>
              <Field label={t("salPreferredWarehouse")} htmlFor="s-wh" hint={t("erpOptional")}>
                <select id="s-wh" className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
                  <option value="">-</option>
                  {lookups.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select>
              </Field>
              <Field label={t("salDeliveryAddress")} htmlFor="s-addr" hint={t("erpOptional")}>
                <input id="s-addr" className="input" value={address} onChange={(e) => setAddress(e.target.value)} />
              </Field>
            </>
          )}
        </div>
        {customer && (
          <p className="erp-muted" style={{ marginTop: 8 }}>
            {customer.requires_prepayment ? t("salPrepaymentCustomer") : `${t("salCreditCustomer")}: ${currency} ${amount(customer.credit_limit)} · ${customer.payment_terms_days} ${t("salDays")}`}
            {" · "}{t("salPriceList")}: {listName ?? t("salProductPrices")}
          </p>
        )}
      </GlassCard>

      <GlassCard title={t("erpLines")} pad={false}>
        <div className="vf-table-wrap">
          <table className="table vf-table erp-lines">
            <thead>
              <tr>
                <th style={{ minWidth: 220 }}>{t("erpProduct")}</th>
                <th className="num" style={{ width: 110 }}>{t("erpQuantity")}</th>
                <th className="num" style={{ width: 130 }}>{t("salUnitPrice")}</th>
                <th className="num" style={{ width: 90 }}>{t("salDiscountPct")}</th>
                <th className="num" style={{ width: 80 }}>{t("salVatPct")}</th>
                <th className="num" style={{ width: 130 }}>{t("salLineTotal")}</th>
                <th style={{ width: 48 }} aria-label={t("erpRemove")} />
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => {
                const p = products.get(l.product_id);
                return (
                  <tr key={i}>
                    <td>
                      <select className="input" aria-label={t("erpProduct")} value={l.product_id}
                        onChange={(e) => {
                          const id = e.target.value;
                          const listed = prices[id]?.price ?? (products.get(id) ? Number(products.get(id)!.sale_price) : "");
                          setLine(i, { product_id: id, unit_price: String(listed) });
                        }}>
                        <option value="">{t("erpPickProduct")}</option>
                        {lookups.products.filter((x) => x.type !== "raw_material" && x.type !== "packaging").map((x) => <option key={x.id} value={x.id}>{x.name} · {x.sku}</option>)}
                      </select>
                      {formError?.field(`lines.${i}.product_id`) && <div className="field-error">{formError.field(`lines.${i}.product_id`)}</div>}
                    </td>
                    <td className="num">
                      <input className="input tnum" type="number" min={0} step="any" aria-label={t("erpQuantity")} value={l.quantity} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                      {p?.unit && <span className="erp-cell-sub">{p.unit.code}</span>}
                      {formError?.field(`lines.${i}.quantity`) && <div className="field-error">{formError.field(`lines.${i}.quantity`)}</div>}
                    </td>
                    <td className="num"><input className="input tnum" type="number" min={0} step="any" aria-label={t("salUnitPrice")} value={l.unit_price} onChange={(e) => setLine(i, { unit_price: e.target.value })} /></td>
                    <td className="num"><input className="input tnum" type="number" min={0} max={100} step="any" aria-label={t("salDiscountPct")} value={l.discount_percent} onChange={(e) => setLine(i, { discount_percent: e.target.value })} /></td>
                    <td className="num"><input className="input tnum" type="number" min={0} max={100} step="any" aria-label={t("salVatPct")} value={l.tax_rate} onChange={(e) => setLine(i, { tax_rate: e.target.value })} /></td>
                    <td className="num tnum">{amount(computed[i].total)}</td>
                    <td><button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={lines.length === 1} onClick={() => setLines((all) => all.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="erp-lines-foot">
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setLines((all) => [...all, blank(lookups.tax_rate)])}><Icon name="ph-plus" size={16} /> {t("erpAddLine")}</button>
          <span className="tnum sal-foot-totals">
            <span className="erp-muted">{t("salSubtotal")}</span> {amount(totals.subtotal - totals.discount)}
            <span className="erp-muted">{t("salVat")}</span> {amount(totals.tax)}
            <span className="erp-muted">{t("salTotal")}</span> <strong>{currency} {amount(totals.total)}</strong>
          </span>
        </div>
      </GlassCard>

      <GlassCard>
        <Field label={t("salNotes")} htmlFor="s-notes" hint={t("erpOptional")}>
          <textarea id="s-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href={existing ? `${base}/${existing.id}` : base}>{t("erpCancel")}</Link>
        <button type="button" className="btn btn-primary" disabled={busy || !customerId || !lines.some((l) => l.product_id && num(l.quantity) > 0)} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
      </div>
    </div>
  );
}
