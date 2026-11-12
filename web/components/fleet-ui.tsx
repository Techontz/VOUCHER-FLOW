"use client";

import { useState, type ReactNode } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { money } from "@/lib/format";
import {
  ENTRY_LABEL, ENTRY_TONE, type EntryStatus, EXPENSE_LABEL, EXPENSE_TYPES, type ExpenseType, type Lookups,
  TRIP_STATUS_LABEL, TRIP_STATUS_TONE, type TripStatus, VEHICLE_STATUS_LABEL, VEHICLE_STATUS_TONE, type VehicleStatus,
} from "@/lib/fleet";
import { Badge, Dialog, Field, Icon } from "@/components/ui";

/*
 * Pieces the fleet screens share: status badges, the "how was it paid"
 * fields, and the fuel and expense dialogs used on a trip, by a fleet
 * officer or by the driver on their own trip.
 */

export function TripStatusBadge({ status }: { status: TripStatus }) {
  const { t } = useApp();
  return <Badge tone={TRIP_STATUS_TONE[status]} dot>{t(TRIP_STATUS_LABEL[status])}</Badge>;
}

export function VehicleStatusBadge({ status }: { status: VehicleStatus }) {
  const { t } = useApp();
  return <Badge tone={VEHICLE_STATUS_TONE[status]} dot>{t(VEHICLE_STATUS_LABEL[status])}</Badge>;
}

export function EntryBadge({ status }: { status: EntryStatus }) {
  const { t } = useApp();
  return <Badge tone={ENTRY_TONE[status]}>{t(ENTRY_LABEL[status])}</Badge>;
}

/** Money in the company's base currency. */
export function useMoney() {
  const { config } = useErp();
  const currency = config?.settings.base_currency ?? "TZS";
  return (value: string | number | null | undefined) => money(Number(value ?? 0), currency);
}

/** Days until a date: negative once it has passed. */
export function daysUntil(date: string | null | undefined): number | null {
  if (!date) return null;
  const d = new Date(`${date.slice(0, 10)}T00:00:00`);
  const today = new Date(); today.setHours(0, 0, 0, 0);
  return Math.round((d.getTime() - today.getTime()) / 86400000);
}

/** An expiry date with a warning tone inside 30 days and a bad tone once past. */
export function ExpiryBadge({ date }: { date: string | null | undefined }) {
  const { t, locale } = useApp();
  const days = daysUntil(date);
  if (days === null || !date) return <span className="erp-muted">-</span>;
  const label = new Date(`${date.slice(0, 10)}T00:00:00`).toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { day: "numeric", month: "short", year: "numeric" });
  if (days < 0) return <Badge tone="bad">{label} · {t("fltExpired")}</Badge>;
  if (days <= 30) return <Badge tone="warn">{label} · {days} {t("fltDaysLeft")}</Badge>;
  return <span className="tnum">{label}</span>;
}

export type PayMode = "account" | "supplier";

/** Paid from a cash or bank account, or owed to a supplier. */
export function PaymentFields({ lookups, mode, setMode, accountId, setAccountId, supplierId, setSupplierId, error, idPrefix }: {
  lookups: Lookups | null; mode: PayMode; setMode: (m: PayMode) => void;
  accountId: string; setAccountId: (v: string) => void; supplierId: string; setSupplierId: (v: string) => void;
  error?: ApiError | null; idPrefix: string;
}) {
  const { t } = useApp();
  return (
    <>
      <Field label={t("fltPaidHow")} htmlFor={`${idPrefix}-mode`}>
        <select id={`${idPrefix}-mode`} className="input" value={mode} onChange={(e) => setMode(e.target.value as PayMode)}>
          <option value="account">{t("fltPaidFromAccount")}</option>
          <option value="supplier">{t("fltPaidOnCredit")}</option>
        </select>
      </Field>
      {mode === "account" ? (
        <Field label={t("fltCashAccount")} htmlFor={`${idPrefix}-acc`} required error={error?.field("account_id")}>
          <select id={`${idPrefix}-acc`} className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">{t("fltChoose")}</option>
            {lookups?.accounts.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
          </select>
        </Field>
      ) : (
        <Field label={t("fltSupplier")} htmlFor={`${idPrefix}-sup`} required error={error?.field("supplier_id")}>
          <select id={`${idPrefix}-sup`} className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
            <option value="">{t("fltChoose")}</option>
            {lookups?.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
      )}
    </>
  );
}

/** Shared submit state for the fleet dialogs: busy flag, field errors, a top-line message. */
export function useSubmit() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  async function run<T>(fn: () => Promise<T>): Promise<T | null> {
    setBusy(true); setError(null);
    try {
      return await fn();
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, String(e)));
      return null;
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, setError, run };
}

/** The message of an error that no single field explains. */
export function FormError({ error }: { error: ApiError | null }) {
  if (!error || Object.keys(error.errors).length) return null;
  return <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error.message}</div>;
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Records fuel on a trip. `base` is /erp/fleet/trips or /erp/fleet/my-trips. */
export function FuelDialog({ open, onClose, onSaved, tripId, base, lookups }: {
  open: boolean; onClose: () => void; onSaved: () => void; tripId: number; base: string; lookups: Lookups | null;
}) {
  const { t, toast } = useApp();
  const fmt = useMoney();
  const { busy, error, setError, run } = useSubmit();
  const [f, setF] = useState({ issue_date: today(), litres: "", price_per_litre: "", station: "", receipt_number: "", odometer: "" });
  const [mode, setMode] = useState<PayMode>("account");
  const [accountId, setAccountId] = useState("");
  const [supplierId, setSupplierId] = useState("");
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  async function save() {
    const r = await run(() => api.post<{ message: string }>(`${base}/${tripId}/fuel`, {
      ...f, odometer: f.odometer || null,
      account_id: mode === "account" ? accountId || null : null, supplier_id: mode === "supplier" ? supplierId || null : null,
    }));
    if (r) { toast(r.message, undefined, "ok"); onSaved(); onClose(); }
  }

  return (
    <Dialog open={open} wide title={t("fltRecordFuel")} onClose={() => { setError(null); onClose(); }} busy={busy} icon="ph-gas-pump"
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("fltCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
      </>}>
      <FormError error={error} />
      <div className="erp-form-grid">
        <Field label={t("fltDate")} htmlFor="fu-date" error={error?.field("issue_date")}><input id="fu-date" type="date" className="input" value={f.issue_date} onChange={set("issue_date")} /></Field>
        <Field label={t("fltLitres")} htmlFor="fu-l" required error={error?.field("litres")}><input id="fu-l" type="number" min="0" step="0.1" inputMode="decimal" className="input" value={f.litres} onChange={set("litres")} /></Field>
        <Field label={t("fltPricePerLitre")} htmlFor="fu-p" required error={error?.field("price_per_litre")}><input id="fu-p" type="number" min="0" inputMode="decimal" className="input" value={f.price_per_litre} onChange={set("price_per_litre")} /></Field>
        <Field label={t("fltStation")} htmlFor="fu-s" error={error?.field("station")}><input id="fu-s" className="input" value={f.station} onChange={set("station")} /></Field>
        <Field label={t("fltReceipt")} htmlFor="fu-r" error={error?.field("receipt_number")}><input id="fu-r" className="input" value={f.receipt_number} onChange={set("receipt_number")} /></Field>
        <Field label={t("fltOdometer")} htmlFor="fu-o" error={error?.field("odometer")}><input id="fu-o" type="number" min="0" className="input" value={f.odometer} onChange={set("odometer")} /></Field>
        <PaymentFields idPrefix="fu" lookups={lookups} mode={mode} setMode={setMode} accountId={accountId} setAccountId={setAccountId} supplierId={supplierId} setSupplierId={setSupplierId} error={error} />
      </div>
      {Number(f.litres) > 0 && Number(f.price_per_litre) > 0 && (
        <p className="erp-muted">{t("fltAmount")}: <strong className="tnum">{fmt(Number(f.litres) * Number(f.price_per_litre))}</strong></p>
      )}
    </Dialog>
  );
}

/** Records a toll, parking, loading fee, allowance or other cost on a trip. */
export function ExpenseDialog({ open, onClose, onSaved, tripId, base, lookups, dailyAllowance }: {
  open: boolean; onClose: () => void; onSaved: () => void; tripId: number; base: string; lookups: Lookups | null; dailyAllowance?: string | null;
}) {
  const { t, toast } = useApp();
  const fmt = useMoney();
  const { busy, error, setError, run } = useSubmit();
  const [type, setType] = useState<ExpenseType>("toll");
  const [f, setF] = useState({ expense_date: today(), quantity: "1", rate: "", description: "", receipt_number: "" });
  const [mode, setMode] = useState<PayMode>("account");
  const [accountId, setAccountId] = useState("");
  const [supplierId, setSupplierId] = useState("");
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const rate = f.rate || (type === "allowance" ? dailyAllowance ?? "" : "");

  async function save() {
    const r = await run(() => api.post<{ message: string }>(`${base}/${tripId}/expenses`, {
      type, ...f, rate: f.rate || null, quantity: f.quantity || 1,
      account_id: mode === "account" ? accountId || null : null, supplier_id: mode === "supplier" ? supplierId || null : null,
    }));
    if (r) { toast(r.message, undefined, "ok"); onSaved(); onClose(); }
  }

  return (
    <Dialog open={open} wide title={t("fltRecordExpense")} onClose={() => { setError(null); onClose(); }} busy={busy} icon="ph-receipt"
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("fltCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy}>{t("fltSave")}</button>
      </>}>
      <FormError error={error} />
      <div className="erp-form-grid">
        <Field label={t("fltExpenseType")} htmlFor="ex-type" required error={error?.field("type")}>
          <select id="ex-type" className="input" value={type} onChange={(e) => setType(e.target.value as ExpenseType)}>
            {EXPENSE_TYPES.map((x) => <option key={x} value={x}>{t(EXPENSE_LABEL[x])}</option>)}
          </select>
        </Field>
        <Field label={t("fltDate")} htmlFor="ex-date" error={error?.field("expense_date")}><input id="ex-date" type="date" className="input" value={f.expense_date} onChange={set("expense_date")} /></Field>
        <Field label={type === "allowance" ? t("fltDays") : t("fltQuantity")} htmlFor="ex-q" error={error?.field("quantity")}><input id="ex-q" type="number" min="0" step="0.5" className="input" value={f.quantity} onChange={set("quantity")} /></Field>
        <Field label={type === "allowance" ? t("fltDailyAllowance") : t("fltRate")} htmlFor="ex-r" required={type !== "allowance"} hint={type === "allowance" ? t("fltAllowanceHint") : undefined} error={error?.field("rate")}>
          <input id="ex-r" type="number" min="0" inputMode="decimal" className="input" value={f.rate} placeholder={type === "allowance" ? dailyAllowance ?? "" : ""} onChange={set("rate")} />
        </Field>
        <Field label={t("fltDescription")} htmlFor="ex-d" required={type === "other"} error={error?.field("description")}><input id="ex-d" className="input" value={f.description} onChange={set("description")} /></Field>
        <Field label={t("fltReceipt")} htmlFor="ex-rc" error={error?.field("receipt_number")}><input id="ex-rc" className="input" value={f.receipt_number} onChange={set("receipt_number")} /></Field>
        <PaymentFields idPrefix="ex" lookups={lookups} mode={mode} setMode={setMode} accountId={accountId} setAccountId={setAccountId} supplierId={supplierId} setSupplierId={setSupplierId} error={error} />
      </div>
      {Number(rate) > 0 && <p className="erp-muted">{t("fltAmount")}: <strong className="tnum">{fmt(Number(rate) * Number(f.quantity || 1))}</strong></p>}
    </Dialog>
  );
}

/** A labelled figure in a definition list. */
export function Row({ label, children }: { label: string; children: ReactNode }) {
  return <><dt>{label}</dt><dd>{children}</dd></>;
}
