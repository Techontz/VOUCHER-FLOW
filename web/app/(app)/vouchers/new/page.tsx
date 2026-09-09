"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { dateInputValue, money } from "@/lib/format";
import { Choice, Field, Icon, Note, PageHeader, Spinner } from "@/components/ui";
import { VoucherSheet } from "@/components/voucher-sheet";
import type { Voucher as VoucherModel } from "@/lib/types";
import type { Department, Voucher, VoucherType } from "@/lib/types";

const METHODS = ["Bank Transfer", "Mobile Money", "Cash", "Cheque"];
const CATEGORIES = ["Logistics", "Premises", "Transport", "Capital equipment", "Professional fees", "Staff welfare", "Utilities", "Other"];

export default function CreateVoucherPage() {
  const router = useRouter();
  const { t, user, company, toast, reportError } = useApp();

  const [types, setTypes] = useState<VoucherType[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState<"draft" | "submit" | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  const [form, setForm] = useState({
    kind: "bank" as "bank" | "cash",
    payee_bank: "",
    payee_account_name: "",
    payee_account_number: "",
    payee_bank_branch: "",
    cash_float: "",
    voucher_type_id: 0,
    department_id: "",
    payee: "",
    purpose: "",
    description: "",
    amount: "",
    currency: company?.currency ?? "TZS",
    payment_method: "Bank Transfer",
    account_ref: "",
    category: "Logistics",
    voucher_date: dateInputValue(),
    notes_to_approver: "",
  });

  useEffect(() => {
    api.get<{ data: VoucherType[] }>("/voucher-types").then((r) => {
      setTypes(r.data);
      if (r.data.length) setForm((f) => ({ ...f, voucher_type_id: f.voucher_type_id || r.data[0].id }));
    }).catch(() => undefined);

    api.get<{ data: Department[] }>("/departments").then((r) => {
      setDepartments(r.data);
      setForm((f) => ({ ...f, department_id: f.department_id || String(user?.department_id ?? r.data[0]?.id ?? "") }));
    }).catch(() => undefined);
  }, [user?.department_id]);

  useEffect(() => {
    if (company?.currency) setForm((f) => ({ ...f, currency: company.currency }));
  }, [company?.currency]);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  const selectedType = types.find((x) => x.id === form.voucher_type_id);
  const amountNumber = Number(String(form.amount).replace(/[^0-9.]/g, "")) || 0;

  const words = useMemo(() => amountInWords(amountNumber, form.currency), [amountNumber, form.currency]);

  /* The preview is a real Voucher shape so the A4 sheet needs no special case. */
  const preview = useMemo<VoucherModel>(() => ({
    id: 0,
    number: selectedType?.next_number_preview ?? "—",
    status: "draft", kind: form.kind,
    status_key: "draft", status_label: t("drafts"), status_label_en: "Draft", status_label_sw: "Rasimu",
    status_tag: "tag-neutral",
    payee: form.payee || "—", purpose: form.purpose || "—",
    description: form.description || null,
    amount: amountNumber, currency: form.currency,
    amount_text: money(amountNumber, form.currency), amount_in_words: words,
    payment_method: form.payment_method, account_ref: form.account_ref || null,
    category: form.category,
    cost_centre: departments.find((d) => String(d.id) === form.department_id)?.cost_centre ?? null,
    voucher_date: form.voucher_date, notes_to_approver: form.notes_to_approver || null,
    verification_code: null,
    voucher_type_id: form.voucher_type_id,
    voucher_type: selectedType ? { id: selectedType.id, name: selectedType.name, label: selectedType.label } : undefined,
    department_id: form.department_id ? Number(form.department_id) : null,
    department: departments.find((d) => String(d.id) === form.department_id)
      ? { id: Number(form.department_id), name: departments.find((d) => String(d.id) === form.department_id)!.name }
      : null,
    requester_id: user?.id ?? 0,
    requester: user ? { id: user.id, name: user.name, initials: user.initials, job_title: user.job_title } : null,
    workflow_id: null, current_step_position: null, current_step: null,
    is_signed_at_current_step: false, is_editable: true, is_terminal: false,
    submitted_at: null, approved_at: null, rejected_at: null,
    paid_at: null, payment_reference: null, paid_by: null,
    payee_bank: form.payee_bank || null,
    payee_account_name: form.payee_account_name || null,
    payee_account_number: form.payee_account_number || null,
    payee_bank_branch: form.payee_bank_branch || null,
    cheque_number: null,
    cash_float: form.cash_float || null,
    received_by: null,
    created_at: null, updated_at: null, timeline: [],
  }), [form, amountNumber, words, selectedType, departments, user, t]);

  async function save(mode: "draft" | "submit") {
    setBusy(mode);
    setError(null);
    try {
      const created = await api.post<{ data: Voucher }>("/vouchers", {
        ...form,
        department_id: form.department_id || null,
        amount: amountNumber,
      });
      const voucher = created.data;

      if (files.length) {
        const body = new FormData();
        files.forEach((file) => body.append("files[]", file));
        await request(`/vouchers/${voucher.id}/attachments`, { method: "POST", form: body });
      }

      if (mode === "submit") {
        const submitted = await api.post<{ data: Voucher }>(`/vouchers/${voucher.id}/submit`);
        toast("Voucher submitted", `${submitted.data.number} — ${submitted.data.status_label}`, "ok");
      } else {
        toast("Draft saved", `${voucher.number} is in your drafts.`, "warn");
      }

      router.push(`/vouchers/${voucher.id}`);
    } catch (err) {
      if (err instanceof ApiError) setError(err);
      reportError(err, "Could not save the voucher");
      setBusy(null);
    }
  }

  const fe = (name: string) => error?.field(name);

  return (
    <div style={{ maxWidth: 1200 }}>
      <PageHeader
        kicker={`${t("newVoucher")}${selectedType ? ` · ${selectedType.next_number_preview}` : ""}`}
        title={t("createVoucher")}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => save("draft")} disabled={busy !== null}>
              {busy === "draft" ? <Spinner /> : t("saveDraft")}
            </button>
            <button className="btn btn-primary" onClick={() => save("submit")} disabled={busy !== null}>
              {busy === "submit" ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={15} /> {t("submitApproval")}</>}
            </button>
          </>
        }
      />

      <div className="vf-split">
        <form onSubmit={(e) => { e.preventDefault(); save("submit"); }} noValidate>
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 10 }}>
            {t("voucherKind")}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-6)" }}>
            <Choice
              selected={form.kind === "bank"} icon="ph-bank" label={t("bankVoucher")}
              sub="Transfer or cheque to a bank account"
              onSelect={() => setForm((f) => ({ ...f, kind: "bank", payment_method: "Bank Transfer" }))}
            />
            <Choice
              selected={form.kind === "cash"} icon="ph-money" label={t("cashVoucher")}
              sub="Notes released from a petty cash float"
              onSelect={() => setForm((f) => ({ ...f, kind: "cash", payment_method: "Cash" }))}
            />
          </div>

          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 10 }}>
            {t("voucherType")}
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: "var(--space-6)" }}>
            {types.map((type) => {
              const on = form.voucher_type_id === type.id;
              return (
                <button key={type.id} type="button" onClick={() => setForm((f) => ({ ...f, voucher_type_id: type.id }))}
                  aria-pressed={on}
                  style={{
                    border: `1px solid ${on ? "var(--color-accent-500)" : "var(--vf-line)"}`,
                    background: on ? "color-mix(in srgb, var(--color-accent-500) 12%, transparent)" : "var(--vf-elev-1)",
                    color: on ? "var(--color-accent-600)" : "var(--color-text)",
                    fontFamily: "var(--font-body)", fontSize: 14.5, padding: "7px 13px",
                    borderRadius: 10, cursor: "pointer", fontWeight: on ? 600 : 400,
                  }}>
                  {type.label}
                </button>
              );
            })}
          </div>

          <div style={{ display: "grid", gap: "var(--space-3)" }}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)" }}>
              <Field label={t("date")} htmlFor="voucher_date" error={fe("voucher_date")}>
                <input id="voucher_date" className="input" type="date" value={form.voucher_date} onChange={set("voucher_date")} />
              </Field>
              <Field label={t("requester")} htmlFor="requester">
                <input id="requester" className="input" value={user?.name ?? ""} readOnly />
              </Field>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)" }}>
              <Field label={t("department")} htmlFor="department_id" error={fe("department_id")}>
                <select id="department_id" className="input" value={form.department_id} onChange={set("department_id")}>
                  <option value="">—</option>
                  {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                </select>
              </Field>
              <Field label={t("expenseCategory")} htmlFor="category">
                <select id="category" className="input" value={form.category} onChange={set("category")}>
                  {CATEGORIES.map((c) => <option key={c}>{c}</option>)}
                </select>
              </Field>
            </div>

            <Field label={t("payee")} htmlFor="payee" error={fe("payee")} required>
              <input id="payee" className="input" value={form.payee} onChange={set("payee")} placeholder="Supplier or staff name" required />
            </Field>

            <Field label={t("paymentPurpose")} htmlFor="purpose" error={fe("purpose")} required
              hint="One line, as it will appear on the voucher">
              <input id="purpose" className="input" value={form.purpose} onChange={set("purpose")} required />
            </Field>

            <Field label={t("description")} htmlFor="description" error={fe("description")}>
              <textarea id="description" className="input" value={form.description} onChange={set("description")} style={{ minHeight: 96 }} />
            </Field>

            <div style={{ display: "grid", gridTemplateColumns: "1.3fr .7fr 1fr", gap: "var(--space-3)" }}>
              <Field label={t("amount")} htmlFor="amount" error={fe("amount")} required>
                <input id="amount" className="input" inputMode="decimal" value={form.amount} onChange={set("amount")}
                  style={{ fontVariantNumeric: "tabular-nums" }} placeholder="0" required />
              </Field>
              <Field label={t("currency")} htmlFor="currency">
                <select id="currency" className="input" value={form.currency} onChange={set("currency")}>
                  <option>TZS</option><option>USD</option><option>KES</option><option>EUR</option>
                </select>
              </Field>
              <Field label={t("paymentMethod")} htmlFor="payment_method">
                <select id="payment_method" className="input" value={form.payment_method} onChange={set("payment_method")}>
                  {METHODS.map((m) => <option key={m}>{m}</option>)}
                </select>
              </Field>
            </div>

            <Field label={t("accountRef")} htmlFor="account_ref" error={fe("account_ref")}
              hint="Invoice, quotation or receipt number">
              <input id="account_ref" className="input" value={form.account_ref} onChange={set("account_ref")}
                placeholder="INV-88213" />
            </Field>

            {/* The two formats settle differently, so they ask for different
                things. A bank voucher needs an account to pay into; a cash
                voucher needs the float it comes out of. */}
            {form.kind === "bank" ? (
              <fieldset style={{
                border: "1px solid var(--vf-line)", borderRadius: 14, padding: "var(--space-4)",
                background: "var(--vf-elev-1)", margin: 0,
              }}>
                <legend style={{
                  fontSize: 11.5, letterSpacing: ".1em", textTransform: "uppercase",
                  color: "var(--color-neutral-600)", padding: "0 6px",
                }}>{t("payeeBankDetails")}</legend>

                <div style={{ display: "grid", gap: "var(--space-3)" }}>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-3)" }}>
                    <Field label={t("bank")} htmlFor="payee_bank">
                      <input id="payee_bank" className="input" value={form.payee_bank}
                        onChange={set("payee_bank")} placeholder="CRDB Bank" />
                    </Field>
                    <Field label={t("branch")} htmlFor="payee_bank_branch">
                      <input id="payee_bank_branch" className="input" value={form.payee_bank_branch}
                        onChange={set("payee_bank_branch")} placeholder="Tower Branch" />
                    </Field>
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-3)" }}>
                    <Field label={t("accountName")} htmlFor="payee_account_name">
                      <input id="payee_account_name" className="input" value={form.payee_account_name}
                        onChange={set("payee_account_name")} placeholder={form.payee || "Account holder"} />
                    </Field>
                    <Field label={t("accountNo")} htmlFor="payee_account_number">
                      <input id="payee_account_number" className="input" value={form.payee_account_number}
                        onChange={set("payee_account_number")} style={{ fontVariantNumeric: "tabular-nums" }}
                        placeholder="0150000000000" />
                    </Field>
                  </div>
                  {company?.bank_account_number && (
                    <Note>
                      {t("drawnOn")}: {company.bank_name} · {company.bank_account_number}
                      {company.bank_branch ? ` · ${company.bank_branch}` : ""}
                    </Note>
                  )}
                </div>
              </fieldset>
            ) : (
              <fieldset style={{
                border: "1px solid var(--vf-line)", borderRadius: 14, padding: "var(--space-4)",
                background: "var(--vf-elev-1)", margin: 0,
              }}>
                <legend style={{
                  fontSize: 11.5, letterSpacing: ".1em", textTransform: "uppercase",
                  color: "var(--color-neutral-600)", padding: "0 6px",
                }}>{t("cashDetails")}</legend>

                <Field label={t("payFrom")} htmlFor="cash_float" hint="The float the notes come out of">
                  <input id="cash_float" className="input" value={form.cash_float}
                    onChange={set("cash_float")} placeholder="Kibada plant petty cash float" />
                </Field>
                <div style={{ marginTop: "var(--space-3)" }}>
                  <Note>{t("cashReceiptNote")}</Note>
                </div>
              </fieldset>
            )}

            <div>
              <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 8 }}>
                {t("supportingDocs")}
              </div>
              <label style={{
                display: "block", border: "1px dashed var(--vf-line-strong)", borderRadius: 14,
                background: "var(--vf-elev-1)", padding: "var(--space-5)", textAlign: "center", cursor: "pointer",
              }}>
                <input type="file" multiple accept="application/pdf,image/*" style={{ display: "none" }}
                  onChange={(e) => setFiles((f) => [...f, ...Array.from(e.target.files ?? [])])} />
                <Icon name="ph-paperclip" size={26} color="var(--color-neutral-500)" />
                <div style={{ fontSize: 14.5, marginTop: 6 }}>
                  Drop invoices, quotations or receipts · PDF, JPG, PNG up to 10 MB
                </div>
                <span className="btn btn-secondary" style={{ marginTop: 10 }}>{t("browseFiles")}</span>
              </label>
              {files.length > 0 && (
                <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
                  {files.map((file, i) => (
                    <span key={`${file.name}-${i}`} className="tag tag-neutral" style={{ fontSize: 13 }}>
                      <Icon name={file.type.startsWith("image/") ? "ph-image" : "ph-file-pdf"} size={14} />
                      {file.name}
                      <button type="button" onClick={() => setFiles((f) => f.filter((_, j) => j !== i))}
                        aria-label={`Remove ${file.name}`}
                        style={{ border: 0, background: "transparent", cursor: "pointer", color: "inherit", padding: 0, marginLeft: 4 }}>
                        <Icon name="ph-x" size={12} />
                      </button>
                    </span>
                  ))}
                </div>
              )}
            </div>

            <Field label={t("notesApprover")} htmlFor="notes_to_approver">
              <textarea id="notes_to_approver" className="input" value={form.notes_to_approver} onChange={set("notes_to_approver")}
                placeholder={t("optional")} style={{ minHeight: 68 }} />
            </Field>
          </div>
        </form>

        {/* Live A4 preview — literally the sheet that prints. */}
        <div className="vf-sticky">
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 10 }}>
            {t("livePreview")}
          </div>
          <div style={{ overflow: "hidden", borderRadius: 8 }}>
            <div style={{ width: 794, transform: "scale(.52)", transformOrigin: "top left", height: 1123 * 0.52 }}>
              <VoucherSheet voucher={preview} company={company} />
            </div>
          </div>
          <div style={{ marginTop: 10 }}>
            <Note>{t("previewNote")}</Note>
          </div>
        </div>
      </div>
    </div>
  );
}

/* Mirrors the server's own words rendering so the preview matches the PDF. */
const UNITS = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
  "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
const TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
const MAJOR: Record<string, string> = { TZS: "shillings", KES: "shillings", USD: "dollars", EUR: "euros", GBP: "pounds" };

function underThousand(n: number): string {
  if (n < 20) return UNITS[n];
  if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? `-${UNITS[n % 10]}` : "");
  return `${UNITS[Math.floor(n / 100)]} hundred${n % 100 ? ` ${underThousand(n % 100)}` : ""}`;
}

function amountInWords(amount: number, currency: string): string {
  const major = MAJOR[currency] ?? "units";
  const whole = Math.floor(Math.abs(amount));
  const cents = Math.round((Math.abs(amount) - whole) * 100);
  if (!whole && !cents) return `Zero ${major} only`;

  const parts: string[] = [];
  let rest = whole;
  for (const [value, label] of [[1e9, "billion"], [1e6, "million"], [1e3, "thousand"]] as const) {
    if (rest >= value) { parts.push(`${underThousand(Math.floor(rest / value))} ${label}`); rest %= value; }
  }
  if (rest > 0) parts.push(underThousand(rest));

  let text = `${parts.join(" ") || "Zero"} ${major}`;
  if (cents > 0) text += ` and ${underThousand(cents)} cents`;
  return `${text} only`;
}
