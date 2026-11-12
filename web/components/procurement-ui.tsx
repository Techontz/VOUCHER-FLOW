"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { amount, type Paginated, qty, useErp } from "@/lib/erp";
import { formatDateTime } from "@/lib/format";
import type { Approval, LineType, Lookups, PAYMENT_METHODS } from "@/lib/procurement-api";
import { Badge, Dialog, Field, Icon, Meter, type Tone } from "@/components/ui";

/*
 * Pieces the procurement screens share: status badges, the approval trail,
 * the line editor used by requisitions and orders, a confirm-with-comment
 * dialog, and a paginated list loader.
 */

const STATUS: Record<string, [MessageKey, Tone]> = {
  draft: ["prcStDraft", "info"],
  submitted: ["prcStSubmitted", "warn"],
  approved: ["prcStApproved", "ok"],
  rejected: ["prcStRejected", "bad"],
  ordered: ["prcStOrdered", "ok"],
  cancelled: ["prcStCancelled", "neutral"],
  sent: ["prcStSent", "info"],
  awarded: ["prcStAwarded", "ok"],
  partially_received: ["prcStPartiallyReceived", "warn"],
  received: ["prcStReceived", "ok"],
  closed: ["prcStClosed", "neutral"],
  awaiting_approval: ["prcStAwaitingApproval", "warn"],
  posted: ["prcStPosted", "ok"],
  paid: ["prcStPaid", "ok"],
  partially_paid: ["prcStPartiallyPaid", "warn"],
  unpaid: ["prcStUnpaid", "bad"],
  matched: ["prcStMatched", "ok"],
  variance: ["prcStVariance", "bad"],
  selected: ["prcStSelected", "ok"],
  not_selected: ["prcStNotSelected", "neutral"],
};

export const METHOD_LABEL: Record<(typeof PAYMENT_METHODS)[number], MessageKey> = {
  bank_transfer: "prcMethodBank", cheque: "prcMethodCheque", cash: "prcMethodCash", mobile_money: "prcMethodMobile",
};

export function ProcStatus({ status }: { status: string | null | undefined }) {
  const { t } = useApp();
  if (!status) return null;
  const [label, tone] = STATUS[status] ?? (["prcStDraft", "neutral"] as [MessageKey, Tone]);
  return <Badge tone={tone} dot>{t(label)}</Badge>;
}

/** "TZS 1,250,000" with the company's currency. */
export function useMoney() {
  const { config } = useErp();
  const currency = config?.settings.base_currency ?? "TZS";
  return (value: string | number | null | undefined) => `${currency} ${amount(value)}`;
}

export function ApprovalTrail({ approvals, required }: { approvals?: Approval[]; required?: number }) {
  const { t, locale } = useApp();
  if (!approvals?.length) {
    return <p className="erp-muted">{required && required > 1 ? t("prcTwoApprovalsNeeded") : t("prcNoDecisionsYet")}</p>;
  }
  return (
    <ul className="erp-list">
      {approvals.map((a) => (
        <li key={a.id} className="erp-list-row">
          <span className="erp-list-icon"><Icon name={a.decision === "approved" ? "ph-check-circle" : "ph-x-circle"} size={18} /></span>
          <span className="erp-list-main">
            <span className="erp-list-title">{a.user?.name ?? "-"} · {t(a.decision === "approved" ? "prcStApproved" : "prcStRejected")} ({t("prcLevel")} {a.level})</span>
            <span className="erp-list-sub">{formatDateTime(a.created_at, locale)}{a.comment ? ` · ${a.comment}` : ""}</span>
          </span>
        </li>
      ))}
    </ul>
  );
}

/** A labelled pair for a detail card. */
export function Facts({ rows }: { rows: [string, ReactNode][] }) {
  return (
    <dl className="erp-review">
      {rows.filter(([, v]) => v !== null && v !== undefined && v !== "").map(([k, v]) => <FactRow key={k} label={k} value={v} />)}
    </dl>
  );
}

function FactRow({ label, value }: { label: string; value: ReactNode }) {
  return <><dt>{label}</dt><dd>{value}</dd></>;
}

/** Loads one page of a list endpoint, re-reading when the query changes. */
export function usePaged<T>(path: string, query: Record<string, string | number | undefined>, debounce = false) {
  const [rows, setRows] = useState<Paginated<T> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const key = JSON.stringify(query);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<T>>(path, JSON.parse(key)).then((r) => { setRows(r); setError(null); }).catch((e) => setError(e.message));
    }, debounce ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [path, key, debounce]);

  return { rows, error };
}

export interface EditLine {
  line_type: LineType; product_id: string; description: string; quantity: string; price: string; vat_rate: string;
  expense_account_id: string; purchase_requisition_line_id?: number | null;
}

export const blankLine = (vat = ""): EditLine => ({ line_type: "stock", product_id: "", description: "", quantity: "", price: "", vat_rate: vat, expense_account_id: "" });

/**
 * Requisition and order lines: a stock line picks a product, a service line
 * (repairs, rent, insurance) is described in words and may name the expense
 * account it will be charged to.
 */
export function LineEditor({ lines, onChange, lookups, withVat, priceLabel, error, noPrice }: {
  lines: EditLine[]; onChange: (lines: EditLine[]) => void; lookups: Lookups; withVat?: boolean; priceLabel: string; error?: ApiError | null; noPrice?: boolean;
}) {
  const { t } = useApp();
  const money = useMoney();
  const set = (i: number, patch: Partial<EditLine>) => onChange(lines.map((l, j) => (j === i ? { ...l, ...patch } : l)));
  const total = lines.reduce((s, l) => s + Number(l.quantity || 0) * Number(l.price || 0) * (withVat ? 1 + Number(l.vat_rate || 0) / 100 : 1), 0);
  const fieldError = (i: number, name: string) => error?.field(`lines.${i}.${name}`);

  return (
    <>
      <div className="vf-table-wrap">
        <table className="table vf-table erp-lines">
          <thead>
            <tr>
              <th style={{ width: 120 }}>{t("prcLineType")}</th>
              <th style={{ minWidth: 220 }}>{t("prcItem")}</th>
              <th className="num" style={{ width: 110 }}>{t("erpQuantity")}</th>
              {!noPrice && <th className="num" style={{ width: 130 }}>{priceLabel}</th>}
              {withVat && <th className="num" style={{ width: 90 }}>{t("prcVatRate")}</th>}
              <th style={{ minWidth: 170 }}>{t("prcExpenseAccount")}</th>
              <th style={{ width: 48 }} aria-label={t("erpRemove")} />
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={i}>
                <td>
                  <select className="input" aria-label={t("prcLineType")} value={l.line_type}
                    onChange={(e) => set(i, { line_type: e.target.value as LineType, product_id: "", expense_account_id: "" })}>
                    <option value="stock">{t("prcStockLine")}</option>
                    <option value="service">{t("prcServiceLine")}</option>
                  </select>
                </td>
                <td>
                  {l.line_type === "stock" ? (
                    <select className="input" aria-label={t("erpProduct")} value={l.product_id}
                      onChange={(e) => {
                        const p = lookups.products.find((x) => String(x.id) === e.target.value);
                        set(i, { product_id: e.target.value, description: p?.name ?? "", price: l.price || (p ? String(Number(p.cost_price)) : "") });
                      }}>
                      <option value="">{t("erpPickProduct")}</option>
                      {lookups.products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}
                    </select>
                  ) : (
                    <input className="input" aria-label={t("prcServiceDescription")} placeholder={t("prcServicePlaceholder")} value={l.description}
                      onChange={(e) => set(i, { description: e.target.value })} />
                  )}
                  {(fieldError(i, "product_id") || fieldError(i, "description")) && <div className="field-error">{fieldError(i, "product_id") ?? fieldError(i, "description")}</div>}
                </td>
                <td className="num">
                  <input className="input tnum" type="number" min={0} step="any" aria-label={t("erpQuantity")} value={l.quantity} onChange={(e) => set(i, { quantity: e.target.value })} />
                  {fieldError(i, "quantity") && <div className="field-error">{fieldError(i, "quantity")}</div>}
                </td>
                {!noPrice && (
                  <td className="num">
                    <input className="input tnum" type="number" min={0} step="any" aria-label={priceLabel} value={l.price} onChange={(e) => set(i, { price: e.target.value })} />
                    {fieldError(i, "unit_price") && <div className="field-error">{fieldError(i, "unit_price")}</div>}
                  </td>
                )}
                {withVat && (
                  <td className="num">
                    <input className="input tnum" type="number" min={0} max={100} step="any" aria-label={t("prcVatRate")} value={l.vat_rate} onChange={(e) => set(i, { vat_rate: e.target.value })} />
                  </td>
                )}
                <td>
                  {l.line_type === "service" ? (
                    <select className="input" aria-label={t("prcExpenseAccount")} value={l.expense_account_id} onChange={(e) => set(i, { expense_account_id: e.target.value })}>
                      <option value="">{t("prcDefaultExpense")}</option>
                      {lookups.expense_accounts.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
                    </select>
                  ) : <span className="erp-muted">{t("prcStockAccount")}</span>}
                </td>
                <td>
                  <button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={lines.length === 1}
                    onClick={() => onChange(lines.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="erp-lines-foot">
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => onChange([...lines, blankLine(lines[0]?.vat_rate ?? "")])}>
          <Icon name="ph-plus" size={16} /> {t("erpAddLine")}
        </button>
        {total > 0 && <span className="tnum"><span className="erp-muted">{t("erpTotal")}</span> <strong>{money(total)}</strong></span>}
      </div>
    </>
  );
}

/** The payload shape the API expects for a line. */
export function linePayload(l: EditLine, priceKey: "unit_price" | "estimated_unit_price", withVat: boolean) {
  return {
    line_type: l.line_type,
    product_id: l.line_type === "stock" && l.product_id ? Number(l.product_id) : null,
    description: l.description || null,
    quantity: l.quantity === "" ? null : Number(l.quantity),
    [priceKey]: l.price === "" ? null : Number(l.price),
    ...(withVat ? { vat_rate: l.vat_rate === "" ? null : Number(l.vat_rate) } : {}),
    expense_account_id: l.line_type === "service" && l.expense_account_id ? Number(l.expense_account_id) : null,
    purchase_requisition_line_id: l.purchase_requisition_line_id ?? null,
  };
}

export type ActionSpec = {
  key: string; label: string; title: string; sub?: string; icon: string; tone?: Tone;
  path: string; comment?: "optional" | "required"; commentKey?: string; danger?: boolean;
};

/**
 * Confirms one action, optionally with a comment or reason, posts it and
 * reports the API's sentence back.
 */
export function ActionDialog({ action, onClose, onDone, summary }: {
  action: ActionSpec | null; onClose: () => void; onDone: (message: string) => void; summary?: { label: string; value: ReactNode }[];
}) {
  const { t } = useApp();
  const [comment, setComment] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function go() {
    if (!action) return;
    setBusy(true); setError(null);
    try {
      const body = action.comment ? { [action.commentKey ?? "comment"]: comment || null } : undefined;
      const r = await api.post<{ message?: string }>(action.path, body);
      setComment("");
      onDone(r.message ?? t("erpSaved"));
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={action !== null} onClose={() => { setError(null); onClose(); }} busy={busy}
      icon={action?.icon} tone={action?.tone ?? "info"} title={action?.title ?? ""} sub={action?.sub} summary={summary}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpBack")}</button>
        <button className={action?.danger ? "btn btn-danger" : "btn btn-primary"} onClick={go}
          disabled={busy || (action?.comment === "required" && comment.trim().length < 3)}>{action?.label}</button>
      </>}>
      {action?.comment && (
        <Field label={action.comment === "required" ? t("erpReason") : t("prcComment")} htmlFor="prc-comment" required={action.comment === "required"}>
          <textarea id="prc-comment" className="input" rows={3} value={comment} onChange={(e) => setComment(e.target.value)} />
        </Field>
      )}
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error}</div>}
    </Dialog>
  );
}

export function BackLink({ href, label }: { href: string; label: string }) {
  return <Link href={href} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {label}</Link>;
}

/** Received against ordered, as a bar and a fraction. */
export function Progress({ done, of }: { done: number; of: number }) {
  const pct = of > 0 ? Math.min(100, Math.round((done / of) * 100)) : 0;
  return (
    <span style={{ display: "grid", gap: 4, minWidth: 110 }} title={`${pct}%`}>
      <Meter percent={pct} />
      <span className="erp-cell-sub tnum">{qty(done)} / {qty(of)}</span>
    </span>
  );
}
