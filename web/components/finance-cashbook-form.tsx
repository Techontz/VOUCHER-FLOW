"use client";

import { useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount } from "@/lib/erp";
import { type AccountRef, type BankAccount, type CashbookEntry, type CashbookType, today } from "@/lib/finance-api";
import { Dialog, Field } from "@/components/ui";
import { ACCOUNT_TYPE_LABEL } from "@/components/erp-ui";

/** A general receipt or payment, as a draft. Posting is a separate step. */
export function CashbookDialog({ entry, type, onClose, onSaved }: {
  entry: CashbookEntry | null; type: CashbookType; onClose: () => void; onSaved: (e: CashbookEntry) => void;
}) {
  const { t, toast } = useApp();
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [accounts, setAccounts] = useState<AccountRef[]>([]);
  const [form, setForm] = useState({
    entry_date: entry?.entry_date.slice(0, 10) ?? today(), bank_account_id: String(entry?.bank_account_id ?? ""),
    account_id: String(entry?.account_id ?? ""), amount: entry?.amount ?? "", description: entry?.description ?? "",
    counterparty: entry?.counterparty ?? "", reference: entry?.reference ?? "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));
  const kind = entry?.type ?? type;

  useEffect(() => {
    api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts", { active: 1 }).then((r) => setBanks(r.data)).catch(() => setBanks([]));
    api.get<{ data: AccountRef[] }>("/erp/finance/cashbook/accounts").then((r) => setAccounts(r.data)).catch(() => setAccounts([]));
  }, []);

  // Receipts usually credit income or equity; payments debit expenses. All stay choosable.
  const grouped = useMemo(() => {
    const order = kind === "receipt" ? ["income", "equity", "liability", "asset", "expense"] : ["expense", "liability", "asset", "equity", "income"];
    return order.map((type) => ({ type, rows: accounts.filter((a) => a.type === type) })).filter((g) => g.rows.length);
  }, [accounts, kind]);

  async function save() {
    setBusy(true); setError(null);
    try {
      const body = { ...form, counterparty: form.counterparty || null, reference: form.reference || null };
      const r = entry
        ? await api.put<{ data: CashbookEntry }>(`/erp/finance/cashbook/${entry.id}`, body)
        : await api.post<{ data: CashbookEntry }>("/erp/finance/cashbook", { ...body, type: kind });
      toast(t("erpSaved"), r.data.number, "ok");
      onSaved(r.data);
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <Dialog open title={entry ? entry.number : t(kind === "receipt" ? "finNewReceipt" : "finNewPayment")}
      sub={t(kind === "receipt" ? "finReceiptHint" : "finPaymentHint")} onClose={onClose} busy={busy} wide
      icon={kind === "receipt" ? "ph-arrow-down-left" : "ph-arrow-up-right"}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.bank_account_id || !form.account_id || !form.amount || !form.description}>{t("finSaveDraft")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <div className="erp-form-grid">
        <Field label={t(kind === "receipt" ? "finIntoAccount" : "finFromAccount")} htmlFor="c-bank" required error={error?.field("bank_account_id")}>
          <select id="c-bank" className="input" value={form.bank_account_id} onChange={(e) => set({ bank_account_id: e.target.value })}>
            <option value="">{t("finChoose")}</option>
            {banks.map((b) => <option key={b.id} value={b.id}>{b.name} ({amount(b.balance)})</option>)}
          </select>
        </Field>
        <Field label={t(kind === "receipt" ? "finIncomeAccount" : "finExpenseAccount")} htmlFor="c-acct" required error={error?.field("account_id")}>
          <select id="c-acct" className="input" value={form.account_id} onChange={(e) => set({ account_id: e.target.value })}>
            <option value="">{t("finChoose")}</option>
            {grouped.map((g) => (
              <optgroup key={g.type} label={t(ACCOUNT_TYPE_LABEL[g.type as keyof typeof ACCOUNT_TYPE_LABEL])}>
                {g.rows.map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
              </optgroup>
            ))}
          </select>
        </Field>
        <Field label={t("erpDate")} htmlFor="c-date" required error={error?.field("entry_date")}>
          <input id="c-date" type="date" className="input" max={today()} value={form.entry_date} onChange={(e) => set({ entry_date: e.target.value })} />
        </Field>
        <Field label={t("finAmount")} htmlFor="c-amt" required error={error?.field("amount")}>
          <input id="c-amt" className="input tnum" inputMode="decimal" value={form.amount} onChange={(e) => set({ amount: e.target.value })} />
        </Field>
        <Field label={t("finDescription")} htmlFor="c-desc" required error={error?.field("description")}>
          <input id="c-desc" className="input" value={form.description} onChange={(e) => set({ description: e.target.value })} />
        </Field>
        <Field label={t(kind === "receipt" ? "finReceivedFrom" : "finPaidTo")} htmlFor="c-party" error={error?.field("counterparty")}>
          <input id="c-party" className="input" value={form.counterparty} onChange={(e) => set({ counterparty: e.target.value })} />
        </Field>
        <Field label={t("erpReference")} htmlFor="c-ref" error={error?.field("reference")}>
          <input id="c-ref" className="input" value={form.reference} onChange={(e) => set({ reference: e.target.value })} />
        </Field>
      </div>
    </Dialog>
  );
}
