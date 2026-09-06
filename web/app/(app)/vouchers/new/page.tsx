"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { dateInputValue, money } from "@/lib/format";
import { Field, Icon, PageHeader, Spinner } from "@/components/ui";
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
            {t("voucherType")}
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: "var(--space-6)" }}>
            {types.map((type) => {
              const on = form.voucher_type_id === type.id;
              return (
                <button key={type.id} type="button" onClick={() => setForm((f) => ({ ...f, voucher_type_id: type.id }))}
                  aria-pressed={on}
                  style={{
                    border: `1px solid ${on ? "var(--color-accent-500)" : "var(--color-divider)"}`,
                    background: on ? "var(--color-accent-100)" : "transparent",
                    color: on ? "var(--color-accent-800)" : "var(--color-text)",
                    fontFamily: "var(--font-body)", fontSize: 14.5, padding: "7px 13px",
                    borderRadius: "var(--radius-md)", cursor: "pointer",
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

            <Field label={t("accountRef")} htmlFor="account_ref" error={fe("account_ref")}>
              <input id="account_ref" className="input" value={form.account_ref} onChange={set("account_ref")} placeholder="Invoice or account number" />
            </Field>

            <div>
              <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 8 }}>
                {t("supportingDocs")}
              </div>
              <label style={{
                display: "block", border: "1px dashed var(--color-neutral-400)", borderRadius: "var(--radius-md)",
                padding: "var(--space-4)", textAlign: "center", cursor: "pointer",
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

        {/* Live A4 preview — the same layout the server prints. */}
        <div className="vf-sticky">
          <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 10 }}>
            {t("livePreview")}
          </div>
          <div style={{ background: "#fff", color: "#201e1d", border: "1px solid var(--color-neutral-400)", boxShadow: "var(--shadow-lg)", padding: 28, fontSize: 13.5 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", borderBottom: "3px solid #201e1d", paddingBottom: 12, gap: 12 }}>
              <div style={{ minWidth: 0 }}>
                {company?.logo_url && <img src={company.logo_url} alt="" style={{ maxHeight: 34, marginBottom: 6 }} />}
                <div style={{ fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 18 }}>{company?.name ?? "Your company"}</div>
                <div style={{ color: "#605d5d", fontSize: 12 }}>
                  {[company?.address, company?.phone].filter(Boolean).join(" · ")}
                </div>
              </div>
              <div style={{ textAlign: "right", flex: "none" }}>
                <div style={{ fontSize: 11, letterSpacing: ".12em", textTransform: "uppercase", color: "#605d5d" }}>{selectedType?.label}</div>
                <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 15, fontVariantNumeric: "tabular-nums" }}>
                  {selectedType?.next_number_preview}
                </div>
              </div>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px 20px", padding: "14px 0", borderBottom: "1px solid #d7d3d3" }}>
              <PreviewCell label={t("date")} value={form.voucher_date} />
              <PreviewCell label={t("department")} value={departments.find((d) => String(d.id) === form.department_id)?.name ?? "—"} />
              <PreviewCell label={t("payee")} value={form.payee || "—"} />
              <PreviewCell label={t("requester")} value={user?.name ?? "—"} />
            </div>

            <div style={{ padding: "14px 0", borderBottom: "1px solid #d7d3d3" }}>
              <div style={{ fontSize: 11, textTransform: "uppercase", letterSpacing: ".08em", color: "#605d5d" }}>{t("paymentPurpose")}</div>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 16, margin: "2px 0 6px" }}>{form.purpose || "—"}</div>
              <div style={{ color: "#444141", lineHeight: 1.5 }}>{form.description}</div>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "14px 0", borderBottom: "3px solid #201e1d", gap: 12 }}>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: 11, textTransform: "uppercase", letterSpacing: ".08em", color: "#605d5d" }}>{t("amountWords")}</div>
                <div style={{ fontStyle: "italic", maxWidth: "30ch" }}>{words}</div>
              </div>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 24, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                {money(amountNumber, form.currency)}
              </div>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20, paddingTop: 18 }}>
              <div><div style={{ borderBottom: "1px solid #9b9797", height: 34 }} /><div style={{ fontSize: 11, color: "#605d5d", marginTop: 4 }}>Signature &amp; date</div></div>
              <div><div style={{ borderBottom: "1px solid #9b9797", height: 34 }} /><div style={{ fontSize: 11, color: "#605d5d", marginTop: 4 }}>Approval &amp; date</div></div>
            </div>
          </div>
          <div style={{ fontSize: 13, color: "var(--color-neutral-600)", marginTop: 10 }}>
            This is what prints. The signature blocks follow your company&rsquo;s configured workflow.
          </div>
        </div>
      </div>
    </div>
  );
}

function PreviewCell({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div style={{ fontSize: 11, textTransform: "uppercase", letterSpacing: ".08em", color: "#605d5d" }}>{label}</div>
      <div>{value}</div>
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
