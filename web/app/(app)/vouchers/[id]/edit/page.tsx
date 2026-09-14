"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { dateInputValue } from "@/lib/format";
import { EmptyState, Field, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import { FormSection } from "@/components/app-ui";
import type { Department, Voucher, VoucherType } from "@/lib/types";

const METHODS = ["Bank Transfer", "Mobile Money", "Cash", "Cheque"];
const CATEGORIES = ["Logistics", "Premises", "Transport", "Capital equipment", "Professional fees", "Staff welfare", "Utilities", "Other"];

export default function EditVoucherPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { t, toast, reportError } = useApp();

  const [voucher, setVoucher] = useState<Voucher | null>(null);
  const [types, setTypes] = useState<VoucherType[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"save" | "submit" | null>(null);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const [form, setForm] = useState({
    voucher_type_id: 0, department_id: "", payee: "", purpose: "", description: "",
    amount: "", currency: "TZS", payment_method: "", account_ref: "", category: "",
    voucher_date: dateInputValue(), notes_to_approver: "",
  });

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher }>(`/vouchers/${params.id}`)
      .then((r) => {
        const v = r.data;
        setVoucher(v);
        setForm({
          voucher_type_id: v.voucher_type_id,
          department_id: v.department_id ? String(v.department_id) : "",
          payee: v.payee, purpose: v.purpose, description: v.description ?? "",
          amount: String(v.amount), currency: v.currency,
          payment_method: v.payment_method ?? "Bank Transfer",
          account_ref: v.account_ref ?? "", category: v.category ?? "Logistics",
          voucher_date: dateInputValue(v.voucher_date), notes_to_approver: v.notes_to_approver ?? "",
        });
      })
      .catch((err) => setError(err.message));
  }, [params.id]);

  useEffect(() => {
    load();
    api.get<{ data: VoucherType[] }>("/voucher-types").then((r) => setTypes(r.data)).catch(() => undefined);
    api.get<{ data: Department[] }>("/departments").then((r) => setDepartments(r.data)).catch(() => undefined);
  }, [load]);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  async function save(mode: "save" | "submit") {
    if (!voucher) return;
    setBusy(mode); setFormError(null);
    try {
      await api.put(`/vouchers/${voucher.id}`, {
        ...form,
        department_id: form.department_id ? Number(form.department_id) : null,
        amount: Number(String(form.amount).replace(/[^0-9.]/g, "")) || 0,
      });
      if (mode === "submit") {
        const res = await api.post<{ data: Voucher }>(`/vouchers/${voucher.id}/submit`);
        toast("Voucher submitted", `${res.data.number} — ${res.data.status_label}`, "ok");
      } else {
        toast("Changes saved", voucher.number, "ok");
      }
      router.push(`/vouchers/${voucher.id}`);
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the voucher");
      setBusy(null);
    }
  }

  if (error) {
    return <EmptyState icon="ph-lock-key" title={t("notAuthorised")} body={error}
      action={<Link className="btn btn-secondary" href="/vouchers">{t("register")}</Link>} />;
  }
  if (!voucher) return <LoadingBlock rows={6} />;

  if (!voucher.actions?.edit) {
    return (
      <EmptyState icon="ph-lock-key" title="This voucher can no longer be edited"
        body={`${voucher.number} is ${voucher.status_label.toLowerCase()}.`}
        action={<Link className="btn btn-secondary" href={`/vouchers/${voucher.id}`}>{t("back")}</Link>} />
    );
  }

  const fe = (name: string) => formError?.field(name);

  return (
    <div className="app-page app-edit">
      <Link className="vf-back" href={`/vouchers/${voucher.id}`}>
        <Icon name="ph-arrow-left" size={14} /> {voucher.number}
      </Link>

      <PageHeader kicker={`${t("edit")} · ${voucher.status_label}`} title={voucher.purpose || voucher.number} sub={voucher.number} />

      <form className="vf-panel app-edit-form" onSubmit={(e) => { e.preventDefault(); save("save"); }} noValidate>
        <div className="vf-panel-pad">
          <FormSection title={t("voucherType")} description={t("detailsSub")}>
            <div className="vf-form-row">
              <Field label={t("voucherType")} htmlFor="e-type">
                <select id="e-type" className="input" value={form.voucher_type_id}
                  onChange={(e) => setForm((f) => ({ ...f, voucher_type_id: Number(e.target.value) }))}>
                  {types.map((type) => <option key={type.id} value={type.id}>{type.label}</option>)}
                </select>
              </Field>
              <Field label={t("date")} htmlFor="e-date">
                <input id="e-date" className="input" type="date" value={form.voucher_date} onChange={set("voucher_date")} />
              </Field>
            </div>
            <div className="vf-form-row">
              <Field label={t("department")} htmlFor="e-dept">
                <select id="e-dept" className="input" value={form.department_id} onChange={set("department_id")}>
                  <option value="">—</option>
                  {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                </select>
              </Field>
              <Field label={t("expenseCategory")} htmlFor="e-cat">
                <select id="e-cat" className="input" value={form.category} onChange={set("category")}>
                  {CATEGORIES.map((c) => <option key={c}>{c}</option>)}
                </select>
              </Field>
            </div>
          </FormSection>

          <FormSection title={t("details")}>
            <Field label={t("payee")} htmlFor="e-payee" error={fe("payee")} required>
              <input id="e-payee" className="input" value={form.payee} onChange={set("payee")} required aria-invalid={!!fe("payee")} />
            </Field>
            <Field label={t("paymentPurpose")} htmlFor="e-purpose" error={fe("purpose")} required>
              <input id="e-purpose" className="input" value={form.purpose} onChange={set("purpose")} required aria-invalid={!!fe("purpose")} />
            </Field>
            <Field label={t("description")} htmlFor="e-desc">
              <textarea id="e-desc" className="input" value={form.description} onChange={set("description")} />
            </Field>
          </FormSection>

          <FormSection title={t("payment")} description={t("paymentSubBank")}>
            <div className="app-edit-amount">
              <Field label={t("amount")} htmlFor="e-amount" error={fe("amount")} required>
                <input id="e-amount" className="input tnum" inputMode="decimal" value={form.amount} onChange={set("amount")} required aria-invalid={!!fe("amount")} />
              </Field>
              <Field label={t("currency")} htmlFor="e-currency">
                <select id="e-currency" className="input" value={form.currency} onChange={set("currency")}>
                  <option>TZS</option><option>USD</option><option>KES</option><option>EUR</option>
                </select>
              </Field>
              <Field label={t("paymentMethod")} htmlFor="e-method">
                <select id="e-method" className="input" value={form.payment_method} onChange={set("payment_method")}>
                  {METHODS.map((m) => <option key={m}>{m}</option>)}
                </select>
              </Field>
            </div>
            <Field label={t("accountRef")} htmlFor="e-ref">
              <input id="e-ref" className="input" value={form.account_ref} onChange={set("account_ref")} />
            </Field>
          </FormSection>

          <FormSection title={t("notesApprover")}>
            <Field label={t("notesApprover")} htmlFor="e-notes" hint={t("optional")}>
              <textarea id="e-notes" className="input" value={form.notes_to_approver} onChange={set("notes_to_approver")} />
            </Field>
          </FormSection>
        </div>

        <div className="app-form-foot">
          <Link className="btn btn-ghost" href={`/vouchers/${voucher.id}`}>{t("cancel")}</Link>
          <div className="app-form-foot-end">
            <button type="button" className="btn btn-secondary" onClick={() => save("save")} disabled={busy !== null}>
              {busy === "save" ? <Spinner /> : t("saveChanges")}
            </button>
            <button type="button" className="btn btn-primary" onClick={() => save("submit")} disabled={busy !== null}>
              {busy === "submit" ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={15} /> {t("submitApproval")}</>}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}
