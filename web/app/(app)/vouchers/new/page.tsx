"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { dateInputValue, money } from "@/lib/format";
import { Choice, Field, Icon, Note, PageHeader, Spinner } from "@/components/ui";
import { resolveWorkflow, routeFor } from "@/lib/progress";
import { useWorkflows } from "@/lib/use-workflows";
import { VoucherSheet } from "@/components/voucher-sheet";
import type { Voucher as VoucherModel } from "@/lib/types";
import type { Department, Voucher, VoucherType } from "@/lib/types";

const METHODS = ["Bank Transfer", "Mobile Money", "Cash", "Cheque"];
/** Which fields each step of the guided flow owns, in order. */
const STEP_FIELDS: string[][] = [
  ["voucher_type_id", "kind"],
  ["voucher_date", "department_id", "category", "payee", "purpose", "description"],
  ["amount", "currency", "payment_method", "account_ref", "payee_bank", "payee_account_name", "payee_account_number", "payee_bank_branch", "cash_float"],
  ["files", "notes_to_approver"],
  [],
];

/** The step that owns the first field the server refused, or -1. */
function stepForErrors(errors: Record<string, string[]> | undefined): number {
  const fields = Object.keys(errors ?? {});
  return STEP_FIELDS.findIndex((owned) => owned.some((f) => fields.some((e) => e === f || e.startsWith(`${f}.`))));
}

const CATEGORIES = ["Logistics", "Premises", "Transport", "Capital equipment", "Professional fees", "Staff welfare", "Utilities", "Other"];

export default function CreateVoucherPage() {
  const router = useRouter();
  const { t, user, company, toast, reportError, locale } = useApp();

  const [types, setTypes] = useState<VoucherType[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState<"draft" | "submit" | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [stepIndex, setStepIndex] = useState(0);
  const [localErrors, setLocalErrors] = useState<Record<string, string>>({});
  const workflows = useWorkflows();

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
      if (err instanceof ApiError) {
        setError(err);
        // The server is the final word. If it refuses a field, take the reader to it.
        const at = stepForErrors(err.errors);
        if (at >= 0) setStepIndex(at);
      }
      reportError(err, "Could not save the voucher");
      setBusy(null);
    }
  }

  const fe = (name: string) => error?.field(name) ?? localErrors[name];

  /* ── guided steps ─────────────────────────────────────────────────────── */

  const STEPS = [
    { key: "type", label: t("voucherType") },
    { key: "details", label: t("details") },
    { key: "payment", label: t("payment") },
    { key: "documents", label: t("supportingDocs") },
    { key: "review", label: t("review") },
  ];

  /** What must be true before leaving a step — the same things the server will insist on. */
  function problemsAt(index: number): Record<string, string> {
    const out: Record<string, string> = {};
    if (index === 1) {
      if (!form.payee.trim()) out.payee = t("required");
      if (!form.purpose.trim()) out.purpose = t("required");
    }
    if (index === 2 && amountNumber <= 0) out.amount = t("amountRequired");
    return out;
  }

  function go(next: number) {
    // Moving forward checks every step being passed; moving back never does.
    if (next > stepIndex) {
      for (let i = stepIndex; i < next; i++) {
        const problems = problemsAt(i);
        if (Object.keys(problems).length) {
          setLocalErrors(problems);
          setStepIndex(i);
          return;
        }
      }
    }
    setLocalErrors({});
    setStepIndex(next);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }


  const workflow = resolveWorkflow(workflows, form.voucher_type_id);
  const route = routeFor(workflow, amountNumber, locale);
  const onReview = stepIndex === STEPS.length - 1;

  return (
    <div className="vf-create">
      <PageHeader
        back={<Link className="vf-back" href="/vouchers"><Icon name="ph-arrow-left" size={15} /> {t("register")}</Link>}
        kicker={selectedType ? `${t("newVoucher")} · ${selectedType.next_number_preview}` : t("newVoucher")}
        title={t("createVoucher")}
      />

      <ol className="vf-stepper" aria-label={t("createVoucher")}>
        {STEPS.map((step, index) => (
          <li key={step.key} style={{ display: "contents" }}>
            <button type="button" className="vf-stepper-item" onClick={() => go(index)}
              data-state={index === stepIndex ? "current" : index < stepIndex ? "done" : "pending"}
              aria-current={index === stepIndex ? "step" : undefined}>
              <span className="vf-stepper-num">{index < stepIndex ? <Icon name="ph-check" size={12} /> : index + 1}</span>
              {step.label}
            </button>
          </li>
        ))}
      </ol>

      <div className="vf-create-grid">
        <form className="vf-panel vf-create-form" noValidate
          onSubmit={(e) => { e.preventDefault(); if (onReview) void save("submit"); else go(stepIndex + 1); }}>

          {/* 1 · type ────────────────────────────────────────────────────── */}
          {stepIndex === 0 && (
            <div className="vf-create-step vf-rise">
              <StepHead n={1} title={t("chooseFormat")} sub={t("chooseFormatSub")} />
              <div className="vf-choice-grid">
                <Choice selected={form.kind === "bank"} icon="ph-bank" label={t("bankVoucher")}
                  sub="Transfer or cheque to a bank account"
                  onSelect={() => setForm((f) => ({ ...f, kind: "bank", payment_method: "Bank Transfer" }))} />
                <Choice selected={form.kind === "cash"} icon="ph-money" label={t("cashVoucher")}
                  sub="Notes released from a petty cash float"
                  onSelect={() => setForm((f) => ({ ...f, kind: "cash", payment_method: "Cash" }))} />
              </div>

              <div className="field" style={{ marginTop: 22 }}>
                <span className="vf-label">{t("voucherType")}</span>
                <div className="vf-pills" role="radiogroup" aria-label={t("voucherType")}>
                  {types.map((type) => (
                    <button key={type.id} type="button" role="radio" aria-checked={form.voucher_type_id === type.id}
                      className="vf-pill" onClick={() => setForm((f) => ({ ...f, voucher_type_id: type.id }))}>
                      {type.label}
                    </button>
                  ))}
                </div>
                {fe("voucher_type_id") && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {fe("voucher_type_id")}</div>}
              </div>
            </div>
          )}

          {/* 2 · details ─────────────────────────────────────────────────── */}
          {stepIndex === 1 && (
            <div className="vf-create-step vf-rise">
              <StepHead n={2} title={t("details")} sub={t("detailsSub")} />
              <div className="vf-form-grid">
                <Field label={t("payee")} htmlFor="payee" error={fe("payee")} required>
                  <input id="payee" className="input" value={form.payee} onChange={set("payee")} placeholder="Supplier or staff name"
                    aria-invalid={!!fe("payee")} autoFocus />
                </Field>
                <Field label={t("paymentPurpose")} htmlFor="purpose" error={fe("purpose")} required hint="One line, as it will appear on the voucher">
                  <input id="purpose" className="input" value={form.purpose} onChange={set("purpose")} aria-invalid={!!fe("purpose")} />
                </Field>
                <div className="vf-form-row">
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
                <div className="vf-form-row">
                  <Field label={t("date")} htmlFor="voucher_date" error={fe("voucher_date")}>
                    <input id="voucher_date" className="input" type="date" value={form.voucher_date} onChange={set("voucher_date")} />
                  </Field>
                  <Field label={t("requester")} htmlFor="requester">
                    <input id="requester" className="input" value={user?.name ?? ""} readOnly />
                  </Field>
                </div>
                <Field label={t("description")} htmlFor="description" error={fe("description")} hint={t("optional")}>
                  <textarea id="description" className="input" value={form.description} onChange={set("description")} />
                </Field>
              </div>
            </div>
          )}

          {/* 3 · payment ─────────────────────────────────────────────────── */}
          {stepIndex === 2 && (
            <div className="vf-create-step vf-rise">
              <StepHead n={3} title={t("payment")} sub={form.kind === "bank" ? t("paymentSubBank") : t("paymentSubCash")} />
              <div className="vf-form-grid">
                <div className="vf-amount-field">
                  <Field label={t("amount")} htmlFor="amount" error={fe("amount")} required>
                    <div className="vf-input-group">
                      <select className="input vf-input-group-addon" value={form.currency} onChange={set("currency")} aria-label={t("currency")}>
                        <option>TZS</option><option>USD</option><option>KES</option><option>EUR</option>
                      </select>
                      <input id="amount" className="input vf-amount-input" inputMode="decimal" value={form.amount} onChange={set("amount")}
                        placeholder="0" aria-invalid={!!fe("amount")} autoFocus />
                    </div>
                  </Field>
                  {amountNumber > 0 && <div className="vf-amount-words">{words}</div>}
                </div>

                <div className="vf-form-row">
                  <Field label={t("paymentMethod")} htmlFor="payment_method">
                    <select id="payment_method" className="input" value={form.payment_method} onChange={set("payment_method")}>
                      {METHODS.map((m) => <option key={m}>{m}</option>)}
                    </select>
                  </Field>
                  <Field label={t("accountRef")} htmlFor="account_ref" error={fe("account_ref")} hint="Invoice, quotation or receipt number">
                    <input id="account_ref" className="input" value={form.account_ref} onChange={set("account_ref")} placeholder="INV-88213" />
                  </Field>
                </div>

                {/* The two formats settle differently, so they ask for different
                    things. A bank voucher needs an account to pay into; a cash
                    voucher needs the float it comes out of. */}
                {form.kind === "bank" ? (
                  <fieldset className="vf-fieldset">
                    <legend>{t("payeeBankDetails")}</legend>
                    <div className="vf-form-row">
                      <Field label={t("bank")} htmlFor="payee_bank" error={fe("payee_bank")}>
                        <input id="payee_bank" className="input" value={form.payee_bank} onChange={set("payee_bank")} placeholder="CRDB Bank" />
                      </Field>
                      <Field label={t("branch")} htmlFor="payee_bank_branch">
                        <input id="payee_bank_branch" className="input" value={form.payee_bank_branch} onChange={set("payee_bank_branch")} placeholder="Tower Branch" />
                      </Field>
                    </div>
                    <div className="vf-form-row">
                      <Field label={t("accountName")} htmlFor="payee_account_name">
                        <input id="payee_account_name" className="input" value={form.payee_account_name} onChange={set("payee_account_name")} placeholder={form.payee || "Account holder"} />
                      </Field>
                      <Field label={t("accountNo")} htmlFor="payee_account_number" error={fe("payee_account_number")}>
                        <input id="payee_account_number" className="input tnum" value={form.payee_account_number} onChange={set("payee_account_number")} placeholder="0150000000000" />
                      </Field>
                    </div>
                    {company?.bank_account_number && (
                      <Note>{t("drawnOn")}: {company.bank_name} · {company.bank_account_number}{company.bank_branch ? ` · ${company.bank_branch}` : ""}</Note>
                    )}
                  </fieldset>
                ) : (
                  <fieldset className="vf-fieldset">
                    <legend>{t("cashDetails")}</legend>
                    <Field label={t("payFrom")} htmlFor="cash_float" hint="The float the notes come out of">
                      <input id="cash_float" className="input" value={form.cash_float} onChange={set("cash_float")} placeholder="Kibada plant petty cash float" />
                    </Field>
                    <Note>{t("cashReceiptNote")}</Note>
                  </fieldset>
                )}
              </div>
            </div>
          )}

          {/* 4 · documents ───────────────────────────────────────────────── */}
          {stepIndex === 3 && (
            <div className="vf-create-step vf-rise">
              <StepHead n={4} title={t("supportingDocs")} sub={t("documentsSub")} />
              <label className="vf-dropzone"
                onDragOver={(e) => { e.preventDefault(); e.currentTarget.dataset.over = "true"; }}
                onDragLeave={(e) => { delete e.currentTarget.dataset.over; }}
                onDrop={(e) => {
                  e.preventDefault(); delete e.currentTarget.dataset.over;
                  setFiles((f) => [...f, ...Array.from(e.dataTransfer.files ?? [])]);
                }}>
                <input type="file" multiple accept="application/pdf,image/*" hidden
                  onChange={(e) => { setFiles((f) => [...f, ...Array.from(e.target.files ?? [])]); e.target.value = ""; }} />
                <span className="vf-dropzone-icon"><Icon name="ph-upload-simple" size={22} /></span>
                <span className="vf-dropzone-title">{t("dropFiles")}</span>
                <span className="vf-dropzone-sub">PDF, JPG, PNG · up to 10 MB each</span>
                <span className="btn btn-secondary btn-sm" style={{ marginTop: 8 }}>{t("browseFiles")}</span>
              </label>

              {files.length > 0 && (
                <ul className="vf-files" style={{ marginTop: 12 }}>
                  {files.map((file, i) => (
                    <li key={`${file.name}-${i}`}>
                      <div className="vf-file" style={{ cursor: "default" }}>
                        <span className="vf-file-icon"><Icon name={file.type.startsWith("image/") ? "ph-image" : "ph-file-pdf"} size={20} /></span>
                        <span className="vf-file-text">
                          <span className="vf-file-name">{file.name}</span>
                          <span className="vf-file-size">{formatBytes(file.size)}</span>
                        </span>
                        <button type="button" className="btn btn-icon btn-sm" onClick={() => setFiles((f) => f.filter((_, j) => j !== i))} aria-label={`Remove ${file.name}`}>
                          <Icon name="ph-x" size={15} />
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              )}

              <div style={{ marginTop: 20 }}>
                <Field label={t("notesApprover")} htmlFor="notes_to_approver" hint={t("optional")}>
                  <textarea id="notes_to_approver" className="input" value={form.notes_to_approver} onChange={set("notes_to_approver")} style={{ minHeight: 80 }} />
                </Field>
              </div>
            </div>
          )}

          {/* 5 · review ──────────────────────────────────────────────────── */}
          {onReview && (
            <div className="vf-create-step vf-rise">
              <StepHead n={5} title={t("reviewVoucher")} sub={t("reviewSub")} />

              <div className="vf-review-amount">
                <span className="vf-eyebrow">{t("amount")}</span>
                <span className="vf-review-amount-value tnum">{money(amountNumber, form.currency)}</span>
                {amountNumber > 0 && <span className="vf-amount-words">{words}</span>}
              </div>

              <dl className="vf-dl">
                <ReviewRow label={t("voucherType")} value={selectedType?.label} onEdit={() => go(0)} />
                <ReviewRow label={t("voucherFormat")} value={form.kind === "bank" ? t("bankVoucher") : t("cashVoucher")} onEdit={() => go(0)} />
                <ReviewRow label={t("payee")} value={form.payee} onEdit={() => go(1)} />
                <ReviewRow label={t("paymentPurpose")} value={form.purpose} onEdit={() => go(1)} />
                <ReviewRow label={t("department")} value={departments.find((d) => String(d.id) === form.department_id)?.name} onEdit={() => go(1)} />
                <ReviewRow label={t("paymentMethod")} value={form.payment_method} onEdit={() => go(2)} />
                {form.kind === "bank" && (form.payee_bank || form.payee_account_number) && (
                  <ReviewRow label={t("bank")} value={[form.payee_bank, form.payee_account_number].filter(Boolean).join(" · ")} onEdit={() => go(2)} />
                )}
                <ReviewRow label={t("attachments")} value={files.length ? `${files.length} ${files.length === 1 ? "file" : "files"}` : t("noneAttached")} onEdit={() => go(3)} />
              </dl>

              {/* The route comes from the company's configured workflow, not a guess. */}
              {route.length > 0 && (
                <div className="vf-route">
                  <span className="vf-eyebrow">{t("approvalRoute")}</span>
                  <ol className="vf-route-list">
                    {route.map((step, i) => (
                      <li key={`${step}-${i}`}>
                        {i > 0 && <Icon name="ph-arrow-right" size={14} />}
                        <span className="vf-route-step">{step}</span>
                      </li>
                    ))}
                  </ol>
                </div>
              )}
            </div>
          )}

          {/* ── step navigation ── */}
          <div className="vf-create-nav">
            {stepIndex > 0
              ? <button type="button" className="btn btn-ghost" onClick={() => go(stepIndex - 1)} disabled={busy !== null}><Icon name="ph-arrow-left" size={16} /> {t("back")}</button>
              : <span />}
            <div className="vf-create-nav-end">
              <button type="button" className="btn btn-secondary" onClick={() => save("draft")} disabled={busy !== null}>
                {busy === "draft" ? <Spinner /> : t("saveDraft")}
              </button>
              {onReview ? (
                <button type="submit" className="btn btn-primary" disabled={busy !== null}>
                  {busy === "submit" ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={17} /> {t("submitVoucher")}</>}
                </button>
              ) : (
                <button type="submit" className="btn btn-primary">
                  {t("next")} <Icon name="ph-arrow-right" size={16} />
                </button>
              )}
            </div>
          </div>
        </form>

        {/* The sheet that will print, updating as the form is filled in. */}
        <aside className="vf-create-preview">
          <div className="vf-create-preview-head">
            <span className="vf-eyebrow">{t("livePreview")}</span>
          </div>
          <div className="vf-document-frame">
            <VoucherSheet voucher={preview} company={company} />
          </div>
        </aside>
      </div>
    </div>
  );
}

function StepHead({ n, title, sub }: { n: number; title: string; sub?: string }) {
  return (
    <div className="vf-step-head">
      <span className="vf-eyebrow">Step {n} of 5</span>
      <h2>{title}</h2>
      {sub && <p>{sub}</p>}
    </div>
  );
}

function ReviewRow({ label, value, onEdit }: { label: string; value: string | null | undefined; onEdit: () => void }) {
  const { t } = useApp();
  return (
    <div className="vf-dl-row vf-review-row">
      <dt>{label}</dt>
      <dd>{value || "—"}</dd>
      <button type="button" className="btn btn-ghost btn-sm" onClick={onEdit}>{t("edit")}</button>
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1_048_576) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1_048_576).toFixed(1)} MB`;
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
