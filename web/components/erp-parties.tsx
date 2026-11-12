"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, type Party, useErp } from "@/lib/erp";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { Check } from "@/components/erp-ui";

type Kind = "customers" | "suppliers";

const blank = {
  code: "", name: "", contact_person: "", phone: "", email: "", tin: "", address: "", city: "", payment_terms_days: "0", is_active: true,
  customer_group: "", credit_limit: "0", requires_prepayment: true,
  category: "", bank_name: "", bank_account_name: "", bank_account_number: "",
};

/**
 * Customers and suppliers share a screen: the same register, search and form,
 * with credit terms on one side and payment details on the other.
 */
export function PartyRegister({ kind }: { kind: Kind }) {
  const { t, toast } = useApp();
  const { can, config } = useErp();
  const customer = kind === "customers";
  const manage = can(customer ? "customers.manage" : "suppliers.manage");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Party> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Party | null>(null);
  const [form, setForm] = useState<typeof blank | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const currency = config?.settings.base_currency ?? "TZS";

  const load = useCallback(() => {
    api.get<Paginated<Party>>(`/erp/${kind}`, { q: q || undefined, page }).then(setRows).catch((e) => setError(e.message));
  }, [kind, q, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  function open(p: Party | null) {
    setEditing(p); setFormError(null);
    setForm(p ? {
      ...blank,
      ...Object.fromEntries(Object.entries(p).map(([k, v]) => [k, v === null ? "" : typeof v === "boolean" ? v : String(v)])),
      credit_limit: String(Number(p.credit_limit ?? 0)),
    } as typeof blank : { ...blank, payment_terms_days: customer ? "0" : "30" });
  }

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    const common = {
      code: form.code || null, name: form.name, contact_person: form.contact_person || null, phone: form.phone || null,
      email: form.email || null, tin: form.tin || null, address: form.address || null, city: form.city || null,
      payment_terms_days: Number(form.payment_terms_days || 0), is_active: form.is_active,
    };
    const payload = customer
      ? { ...common, customer_group: form.customer_group || null, credit_limit: Number(form.credit_limit || 0), requires_prepayment: form.requires_prepayment }
      : { ...common, category: form.category || null, bank_name: form.bank_name || null, bank_account_name: form.bank_account_name || null, bank_account_number: form.bank_account_number || null };
    try {
      if (editing) await api.put(`/erp/${kind}/${editing.id}`, payload);
      else await api.post(`/erp/${kind}`, payload);
      toast(t("erpSaved"), form.name, "ok");
      setForm(null); load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally { setBusy(false); }
  }

  const set = (k: keyof typeof blank, v: string | boolean) => setForm((f) => (f ? { ...f, [k]: v } : f));
  const text = (k: keyof typeof blank, label: string, type = "text") => (
    <Field label={label} htmlFor={`pt-${k}`} error={formError?.field(k)}>
      <input id={`pt-${k}`} className="input" type={type} value={String(form?.[k] ?? "")} onChange={(e) => set(k, e.target.value)} />
    </Field>
  );

  return (
    <div className="erp-page">
      <PageHeader title={t(customer ? "erpCustomers" : "erpSuppliers")} subtitle={t(customer ? "erpCustomersSub" : "erpSuppliersSub")}
        actions={manage && <button className="btn btn-primary" onClick={() => open(null)}><Icon name="ph-plus" size={18} /> {t(customer ? "erpNewCustomer" : "erpNewSupplier")}</button>} />

      <Toolbar><SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("erpName")}, ${t("erpCode")}, ${t("erpPhone")}`} /></Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? (
        <EmptyState icon={customer ? "ph-users" : "ph-truck"} title={t(customer ? "erpNoCustomers" : "erpNoSuppliers")} />
      ) : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead>
                <tr>
                  <th>{t("erpName")}</th><th>{customer ? t("erpCustomerGroup") : t("erpCategory")}</th><th>{t("erpContact")}</th>
                  {customer ? <th className="num">{t("erpCreditLimit")}</th> : <th>{t("erpBank")}</th>}
                  <th className="num">{t("erpTerms")}</th>{customer && <th>{t("erpCredit")}</th>}
                </tr>
              </thead>
              <tbody>
                {rows.data.map((p) => (
                  <tr key={p.id} className={manage ? "is-clickable" : undefined} onClick={manage ? () => open(p) : undefined}>
                    <td><span className="erp-cell-title">{p.name}</span><span className="erp-cell-sub tnum">{p.code}{p.city ? ` · ${p.city}` : ""}</span>{!p.is_active && <Badge>{t("erpInactive")}</Badge>}</td>
                    <td>{(customer ? p.customer_group : p.category) || "-"}</td>
                    <td>{p.contact_person || "-"}{p.phone && <span className="erp-cell-sub tnum">{p.phone}</span>}</td>
                    {customer ? <td className="num">{currency} {amount(p.credit_limit)}</td> : <td>{p.bank_name || "-"}{p.bank_account_number && <span className="erp-cell-sub tnum">{p.bank_account_number}</span>}</td>}
                    <td className="num">{p.payment_terms_days}</td>
                    {customer && <td>{p.requires_prepayment ? <Badge tone="warn">{t("erpCashFirst")}</Badge> : <Badge tone="ok">{t("erpCredit")}</Badge>}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {form && (
        <Dialog open wide title={editing ? editing.name : t(customer ? "erpNewCustomer" : "erpNewSupplier")} onClose={() => setForm(null)} busy={busy}
          actions={<>
            {editing && <button className="btn btn-danger" style={{ marginRight: "auto" }} disabled={busy}
              onClick={async () => { await api.delete(`/erp/${kind}/${editing.id}`); setForm(null); load(); }}>{t("erpArchive")}</button>}
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.name}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("erpName")} htmlFor="pt-name" required error={formError?.field("name")}>
              <input id="pt-name" className="input" value={form.name} onChange={(e) => set("name", e.target.value)} />
            </Field>
            <Field label={t("erpCode")} htmlFor="pt-code" hint={editing ? undefined : t("erpCodeAuto")} error={formError?.field("code")}>
              <input id="pt-code" className="input" value={form.code} onChange={(e) => set("code", e.target.value.toUpperCase())} />
            </Field>
            {customer ? text("customer_group", t("erpCustomerGroup")) : text("category", t("erpCategory"))}
            {text("contact_person", t("erpContact"))}
            {text("phone", t("erpPhone"), "tel")}
            {text("email", t("erpEmail"), "email")}
            {text("tin", t("erpTin"))}
            {text("city", t("erpCity"))}
            {text("address", t("erpAddress"))}
            {text("payment_terms_days", t("erpTerms"), "number")}
            {customer && text("credit_limit", `${t("erpCreditLimit")} (${currency})`, "number")}
          </div>
          {customer ? (
            <Check label={t("erpPrepayment")} checked={form.requires_prepayment} onChange={(v) => set("requires_prepayment", v)} />
          ) : (
            <>
              <h3 className="erp-subhead">{t("erpPaymentDetails")}</h3>
              <div className="erp-form-grid">
                {text("bank_name", t("erpBank"))}
                {text("bank_account_name", t("erpAccountName"))}
                {text("bank_account_number", t("erpAccountNumber"))}
              </div>
            </>
          )}
          {editing && <Check label={t("erpActive")} checked={form.is_active} onChange={(v) => set("is_active", v)} />}
        </Dialog>
      )}
    </div>
  );
}
