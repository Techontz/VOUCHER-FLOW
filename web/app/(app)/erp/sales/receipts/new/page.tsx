"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Invoice, type Lookups, METHOD_LABEL, num, RECEIPT_METHODS, useSalesLookups } from "@/lib/sales-api";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Money, useCurrency } from "@/components/sales-ui";

export default function NewReceiptPage() {
  return <ErpGate module="sales" permission="sales.receipt"><NewReceiptGate /></ErpGate>;
}

function NewReceiptGate() {
  const invoice = useQueryValue("invoice");
  const { lookups, error } = useSalesLookups();
  if (error) return <ErrorState message={error} />;
  if (!lookups || invoice === undefined) return <LoadingBlock rows={5} />;
  return <NewReceipt lookups={lookups} invoiceId={invoice} />;
}

/**
 * Records money received and applies it to the customer's open invoices.
 * Nothing reaches the books until someone else in finance verifies it.
 */
function NewReceipt({ lookups, invoiceId }: { lookups: Lookups; invoiceId: string | null }) {
  const { t, toast, locale } = useApp();
  const router = useRouter();
  const currency = useCurrency();
  const [customerId, setCustomerId] = useState("");
  const [accountId, setAccountId] = useState(String(lookups.cash_accounts.find((a) => a.code === "1200")?.id ?? lookups.cash_accounts[0]?.id ?? ""));
  const [method, setMethod] = useState<(typeof RECEIPT_METHODS)[number]>("bank_transfer");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [open, setOpen] = useState<Invoice[] | null>(null);
  const [alloc, setAlloc] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const loadOpen = useCallback((customer: string, preselect?: number) => {
    setOpen(null);
    api.get<Paginated<Invoice>>("/erp/sales/invoices", { customer_id: customer, open_only: 1, per_page: 200 }).then((r) => {
      setOpen(r.data);
      setAlloc(preselect ? { [preselect]: String(r.data.find((i) => i.id === preselect)?.balance ?? "") } : {});
    }).catch(() => setOpen([]));
  }, []);

  useEffect(() => {
    if (!invoiceId) return;
    api.get<{ data: Invoice }>(`/erp/sales/invoices/${invoiceId}`).then((r) => {
      setCustomerId(String(r.data.customer_id));
      loadOpen(String(r.data.customer_id), r.data.id);
    }).catch(() => undefined);
  }, [invoiceId, loadOpen]);

  const total = Object.values(alloc).reduce((s, v) => s + num(v), 0);

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ message: string }>("/erp/sales/receipts", {
        customer_id: Number(customerId), account_id: Number(accountId), method, receipt_date: date,
        reference: reference || null, notes: notes || null,
        allocations: Object.entries(alloc).filter(([, v]) => num(v) > 0).map(([k, v]) => ({ sales_invoice_id: Number(k), amount: Number(v) })),
      });
      toast(r.message, undefined, "ok");
      router.push("/erp/sales/receipts");
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="erp-page">
      <PageHeader back={<Link href="/erp/sales/receipts" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salReceipts")}</Link>}
        title={t("salRecordReceipt")} subtitle={t("salRecordReceiptSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("salCustomer")} htmlFor="r-cust" required error={formError?.field("customer_id")}>
            <select id="r-cust" className="input" value={customerId} onChange={(e) => { setCustomerId(e.target.value); if (e.target.value) loadOpen(e.target.value); else setOpen(null); }}>
              <option value="">{t("salPickCustomer")}</option>
              {lookups.customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </Field>
          <Field label={t("salIntoAccount")} htmlFor="r-acc" required error={formError?.field("account_id")}>
            <select id="r-acc" className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              {lookups.cash_accounts.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
            </select>
          </Field>
          <Field label={t("salMethod")} htmlFor="r-method">
            <select id="r-method" className="input" value={method} onChange={(e) => setMethod(e.target.value as typeof method)}>
              {RECEIPT_METHODS.map((m) => <option key={m} value={m}>{t(METHOD_LABEL[m])}</option>)}
            </select>
          </Field>
          <Field label={t("erpDate")} htmlFor="r-date" error={formError?.field("receipt_date")}>
            <input id="r-date" className="input" type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label={t("erpReference")} htmlFor="r-ref" hint={t("salReferenceHint")}>
            <input id="r-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)} />
          </Field>
        </div>
      </GlassCard>

      <GlassCard title={t("salApplyToInvoices")} pad={false}>
        {!customerId ? <EmptyState icon="ph-user" title={t("salPickCustomerFirst")} /> : open === null ? <LoadingBlock rows={2} /> : open.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("salNothingOwed")} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("salInvoice")}</th><th>{t("salDue")}</th><th className="num">{t("salBalance")}</th><th className="num" style={{ width: 170 }}>{t("salApply")}</th></tr></thead>
              <tbody>
                {open.map((i) => (
                  <tr key={i.id}>
                    <td><span className="erp-cell-title tnum">{i.number}</span>{i.order && <span className="erp-cell-sub">{i.order.number}</span>}</td>
                    <td className="tnum">{formatDate(i.due_date, locale)}</td>
                    <td className="num"><Money value={i.balance} /></td>
                    <td className="num">
                      <input className="input tnum" type="number" min={0} max={i.balance} step="any" aria-label={t("salApply")} value={alloc[i.id] ?? ""} onChange={(e) => setAlloc((a) => ({ ...a, [i.id]: e.target.value }))} />
                      <button type="button" className="btn btn-sm btn-secondary" style={{ marginTop: 4 }} onClick={() => setAlloc((a) => ({ ...a, [i.id]: String(i.balance) }))}>{t("salFull")}</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="erp-lines-foot"><span /><span className="tnum"><span className="erp-muted">{t("salReceiptTotal")}</span> <strong>{currency} {amount(total)}</strong></span></div>
      </GlassCard>

      <GlassCard>
        <Field label={t("salNotes")} htmlFor="r-notes" hint={t("erpOptional")}>
          <textarea id="r-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href="/erp/sales/receipts">{t("erpCancel")}</Link>
        <button className="btn btn-primary" disabled={busy || !customerId || !accountId || total <= 0} onClick={save}><Icon name="ph-floppy-disk" size={18} /> {t("salRecord")}</button>
      </div>
    </div>
  );
}
