"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Invoice, PAYMENT_METHODS, type Payment, useLookups } from "@/lib/procurement-api";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { BackLink, METHOD_LABEL, useMoney } from "@/components/procurement-ui";

export default function NewPaymentPage() {
  return <ErpGate module="procurement" permission="procurement.pay"><NewPaymentLoader /></ErpGate>;
}

function NewPaymentLoader() {
  const supplier = useQueryValue("supplier");
  const invoice = useQueryValue("invoice");
  if (supplier === undefined || invoice === undefined) return <LoadingBlock rows={5} />;
  return <NewPayment initialSupplier={supplier ?? ""} initialInvoice={invoice ? Number(invoice) : null} />;
}

/**
 * Pays a supplier from a cash or bank account, allocated to its posted
 * invoices. The allocations must add up to the amount; each is capped at what
 * the invoice still owes.
 */
function NewPayment({ initialSupplier, initialInvoice }: { initialSupplier: string; initialInvoice: number | null }) {
  const { t, toast, locale } = useApp();
  const router = useRouter();
  const money = useMoney();
  const { lookups, error } = useLookups();
  const [supplierId, setSupplierId] = useState(initialSupplier);
  const [invoices, setInvoices] = useState<Invoice[] | null>(null);
  const [alloc, setAlloc] = useState<Record<number, string>>({});
  const [accountId, setAccountId] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState<(typeof PAYMENT_METHODS)[number]>("bank_transfer");
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => {
    if (!supplierId) return;
    api.get<Paginated<Invoice>>("/erp/procurement/invoices", { status: "unpaid", supplier_id: supplierId, per_page: 200 }).then((r) => {
      setInvoices(r.data);
      setAlloc(Object.fromEntries(r.data.map((i) => [i.id, initialInvoice === i.id ? String(i.outstanding) : ""])));
    }).catch(() => setInvoices([]));
  }, [supplierId, initialInvoice]);

  const total = Object.values(alloc).reduce((s, v) => s + Number(v || 0), 0);

  async function save(post: boolean) {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: Payment }>("/erp/procurement/payments", {
        supplier_id: Number(supplierId), account_id: accountId ? Number(accountId) : null, payment_date: date, method,
        reference: reference || null, notes: notes || null, amount: Math.round(total * 100) / 100, post,
        allocations: Object.entries(alloc).filter(([, v]) => Number(v) > 0).map(([id, v]) => ({ supplier_invoice_id: Number(id), amount: Number(v) })),
      });
      toast(t(post ? "prcPaymentPosted" : "erpSaved"), r.data.number, "ok");
      router.push(`/erp/procurement/payments/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!lookups) return <LoadingBlock rows={5} />;

  return (
    <div className="erp-page">
      <PageHeader back={<BackLink href="/erp/procurement/payments" label={t("prcPayments")} />} title={t("prcNewPayment")} subtitle={t("prcPaymentFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("erpSupplier")} htmlFor="sp-sup" required error={formError?.field("supplier_id")}>
            <select id="sp-sup" className="input" value={supplierId} onChange={(e) => { setSupplierId(e.target.value); setInvoices(null); }}>
              <option value="">{t("prcPickSupplier")}</option>
              {lookups.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </Field>
          <Field label={t("prcPaidFrom")} htmlFor="sp-acc" required hint={t("prcPaidFromHint")} error={formError?.field("account_id")}>
            <select id="sp-acc" className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              <option value="">{t("prcPickAccount")}</option>
              {lookups.payment_accounts.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
            </select>
          </Field>
          <Field label={t("erpDate")} htmlFor="sp-date" error={formError?.field("payment_date")}>
            <input id="sp-date" className="input" type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label={t("prcMethod")} htmlFor="sp-method">
            <select id="sp-method" className="input" value={method} onChange={(e) => setMethod(e.target.value as typeof method)}>
              {PAYMENT_METHODS.map((m) => <option key={m} value={m}>{t(METHOD_LABEL[m])}</option>)}
            </select>
          </Field>
          <Field label={t("erpReference")} htmlFor="sp-ref" hint={t("prcPaymentRefHint")}>
            <input id="sp-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)} />
          </Field>
        </div>
        <Field label={t("erpNotes")} htmlFor="sp-notes" hint={t("erpOptional")}>
          <textarea id="sp-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      {supplierId && (
        <GlassCard title={t("prcAllocate")} subtitle={t("prcAllocateSub")} pad={false}>
          {!invoices ? <LoadingBlock rows={2} /> : invoices.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("prcNothingOwed")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("prcSupplierInvoiceNo")}</th><th>{t("prcDueDate")}</th><th className="num">{t("erpTotal")}</th><th className="num">{t("prcOutstanding")}</th><th className="num" style={{ width: 160 }}>{t("prcPayNow")}</th></tr></thead>
                <tbody>
                  {invoices.map((i) => (
                    <tr key={i.id}>
                      <td><span className="erp-cell-title tnum">{i.supplier_invoice_number}</span><span className="erp-cell-sub tnum">{i.number}</span></td>
                      <td className="tnum">{formatDate(i.due_date, locale)}</td>
                      <td className="num">{money(i.total)}</td>
                      <td className="num">{money(i.outstanding)}</td>
                      <td className="num">
                        <input className="input tnum" type="number" min={0} max={i.outstanding} step="any" aria-label={t("prcPayNow")} value={alloc[i.id] ?? ""} onChange={(e) => setAlloc((a) => ({ ...a, [i.id]: e.target.value }))} />
                        <button type="button" className="btn btn-sm btn-secondary" style={{ marginTop: 4 }} onClick={() => setAlloc((a) => ({ ...a, [i.id]: String(i.outstanding) }))}>{t("prcPayInFull")}</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="erp-lines-foot"><span /><span className="tnum"><span className="erp-muted">{t("prcPaymentAmount")}</span> <strong>{money(total)}</strong></span></div>
        </GlassCard>
      )}

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>{t("erpCancel")}</button>
        <button type="button" className="btn btn-secondary" disabled={busy || !supplierId || !accountId || total <= 0} onClick={() => save(false)}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
        <button type="button" className="btn btn-primary" disabled={busy || !supplierId || !accountId || total <= 0} onClick={() => save(true)}>
          <Icon name="ph-check-circle" size={18} /> {t("prcSaveAndPost")}
        </button>
      </div>
    </div>
  );
}
