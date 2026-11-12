"use client";

import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type BankAccount, type BankType, today } from "@/lib/finance-api";
import { Dialog, Field } from "@/components/ui";
import { BANK_TYPE_LABEL } from "@/components/finance-ui";

/** Adds a bank, mobile money or cash account, or edits one's details. */
export function BankAccountDialog({ bank, onClose, onSaved }: { bank: BankAccount | null; onClose: () => void; onSaved: (b: BankAccount) => void }) {
  const { t, toast } = useApp();
  const [form, setForm] = useState({
    name: bank?.name ?? "", type: (bank?.type ?? "bank") as BankType, bank_name: bank?.bank_name ?? "", branch: bank?.branch ?? "",
    account_name: bank?.account_name ?? "", account_number: bank?.account_number ?? "", currency: bank?.currency ?? "TZS",
    notes: bank?.notes ?? "", opening_balance: "", opening_date: today(), code: "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));

  async function save() {
    setBusy(true); setError(null);
    try {
      const body = {
        name: form.name, type: form.type, bank_name: form.bank_name || null, branch: form.branch || null,
        account_name: form.account_name || null, account_number: form.account_number || null, currency: form.currency, notes: form.notes || null,
        ...(bank ? {} : { opening_balance: form.opening_balance || 0, opening_date: form.opening_date, code: form.code || null }),
      };
      const r = bank
        ? await api.put<{ data: BankAccount }>(`/erp/finance/bank-accounts/${bank.id}`, body)
        : await api.post<{ data: BankAccount }>("/erp/finance/bank-accounts", body);
      toast(t("erpSaved"), r.data.name, "ok");
      onSaved(r.data);
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <Dialog open title={bank ? bank.name : t("finAddBank")} onClose={onClose} busy={busy} wide sub={bank ? undefined : t("finAddBankHint")}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.name}>{t("erpSave")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <div className="erp-form-grid">
        <Field label={t("erpName")} htmlFor="b-name" required error={error?.field("name")}>
          <input id="b-name" className="input" value={form.name} onChange={(e) => set({ name: e.target.value })} placeholder="NMB Bank: operations" />
        </Field>
        <Field label={t("erpType")} htmlFor="b-type" error={error?.field("type")}>
          <select id="b-type" className="input" value={form.type} onChange={(e) => set({ type: e.target.value as BankType })}>
            {(Object.keys(BANK_TYPE_LABEL) as BankType[]).map((k) => <option key={k} value={k}>{t(BANK_TYPE_LABEL[k])}</option>)}
          </select>
        </Field>
        <Field label={t("finBankName")} htmlFor="b-bank" error={error?.field("bank_name")}>
          <input id="b-bank" className="input" value={form.bank_name} onChange={(e) => set({ bank_name: e.target.value })} />
        </Field>
        <Field label={t("finBranch")} htmlFor="b-branch" error={error?.field("branch")}>
          <input id="b-branch" className="input" value={form.branch} onChange={(e) => set({ branch: e.target.value })} />
        </Field>
        <Field label={t("finAccountName")} htmlFor="b-holder" error={error?.field("account_name")}>
          <input id="b-holder" className="input" value={form.account_name} onChange={(e) => set({ account_name: e.target.value })} />
        </Field>
        <Field label={t("finAccountNumber")} htmlFor="b-number" error={error?.field("account_number")}>
          <input id="b-number" className="input tnum" value={form.account_number} onChange={(e) => set({ account_number: e.target.value })} />
        </Field>
        <Field label={t("finCurrency")} htmlFor="b-cur" error={error?.field("currency")}>
          <input id="b-cur" className="input" maxLength={3} value={form.currency} onChange={(e) => set({ currency: e.target.value.toUpperCase() })} />
        </Field>
        {!bank && <>
          <Field label={t("finOpeningBalance")} htmlFor="b-open" hint={t("finOpeningHint")} error={error?.field("opening_balance")}>
            <input id="b-open" className="input tnum" inputMode="decimal" value={form.opening_balance} onChange={(e) => set({ opening_balance: e.target.value })} />
          </Field>
          <Field label={t("finOpeningDate")} htmlFor="b-odate" error={error?.field("opening_date")}>
            <input id="b-odate" type="date" className="input" value={form.opening_date} max={today()} onChange={(e) => set({ opening_date: e.target.value })} />
          </Field>
          <Field label={t("finLedgerCode")} htmlFor="b-code" hint={t("finLedgerCodeHint")} error={error?.field("code")}>
            <input id="b-code" className="input tnum" inputMode="numeric" value={form.code} onChange={(e) => set({ code: e.target.value })} placeholder="1210" />
          </Field>
        </>}
        <Field label={t("finNotes")} htmlFor="b-notes" error={error?.field("notes")}>
          <input id="b-notes" className="input" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </Field>
      </div>
    </Dialog>
  );
}
