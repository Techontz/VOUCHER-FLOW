"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { ACCEPT_ATTRIBUTE, acceptFiles, attachmentForm, MAX_UPLOAD_MB, type Rejected } from "@/lib/attachments";
import { dateInputValue, money } from "@/lib/format";
import { Field, Icon, Note, PageHeader, Spinner } from "@/components/ui";
import { resolveWorkflow, routeFor } from "@/lib/progress";
import { useWorkflows } from "@/lib/use-workflows";
import { VoucherSheet } from "@/components/voucher-sheet";
import type { Voucher as VoucherModel } from "@/lib/types";
import type { Department, Voucher, VoucherType } from "@/lib/types";

const METHODS = ["Bank Transfer", "Mobile Money", "Cash", "Cheque"];

/** The first field, in page order, that the server or the form refused — so the page can take the reader to it. */
const FIELD_ORDER = [
  "voucher_type_id", "kind", "amount", "currency", "voucher_date", "purpose", "description",
  "payee", "payment_method", "account_ref", "payee_bank", "payee_account_name", "payee_account_number", "payee_bank_branch", "cash_float",
  "department_id", "category", "files", "notes_to_approver",
];

/** A short line under each voucher type, by its number prefix. Unknown prefixes simply show none. */
const TYPE_HINT: Record<string, { icon: string; en: string; sw: string }> = {
  PV: { icon: "ph-receipt", en: "Supplier or service", sw: "Msambazaji au huduma" },
  PC: { icon: "ph-coins", en: "Small cash spend", sw: "Matumizi madogo ya taslimu" },
  EX: { icon: "ph-shopping-bag", en: "Bills and utilities", sw: "Bili na huduma" },
  AD: { icon: "ph-airplane-tilt", en: "Before a trip or job", sw: "Kabla ya safari au kazi" },
  RB: { icon: "ph-arrow-counter-clockwise", en: "You already paid", sw: "Umeshalipa" },
  OV: { icon: "ph-dots-three-circle", en: "Anything else", sw: "Nyingine yoyote" },
};

const CATEGORIES = ["Logistics", "Premises", "Transport", "Capital equipment", "Professional fees", "Staff welfare", "Utilities", "Other"];

export default function CreateVoucherPage() {
  const router = useRouter();
  const { t, user, company, toast, reportError, locale } = useApp();

  const [types, setTypes] = useState<VoucherType[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [rejected, setRejected] = useState<Rejected[]>([]);
  const [busy, setBusy] = useState<"draft" | "submit" | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [reviewing, setReviewing] = useState(false);
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

  /**
   * Adds files from the picker or a drop. Callers pass an array they have
   * already copied out of the event: reading the FileList later — inside a
   * state updater, say — finds it emptied, which is how picked documents used
   * to vanish without a trace.
   */
  function addFiles(picked: File[]) {
    if (!picked.length) return;
    const result = acceptFiles(files, picked);
    setFiles(result.files);
    setRejected(result.rejected);
  }

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
        try {
          await request(`/vouchers/${voucher.id}/attachments`, { method: "POST", form: attachmentForm(files) });
        } catch (err) {
          // The voucher exists now. Staying here would invite a second save and a
          // duplicate voucher, so go to the draft — where documents can be added
          // again — and say exactly what did not attach. It is not submitted:
          // whoever reviews it would expect those documents to be there.
          const detail = err instanceof ApiError ? (Object.values(err.errors)[0]?.[0] ?? err.message) : undefined;
          toast(t("docsNotAttached"), `${voucher.number} — ${detail ?? t("docsNotAttachedBody")}`, "bad");
          router.push(`/vouchers/${voucher.id}`);
          return;
        }
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
        const first = FIELD_ORDER.find((f) => Object.keys(err.errors ?? {}).some((e) => e === f || e.startsWith(`${f}.`)));
        if (first) { setReviewing(false); scrollToField(first); }
      }
      reportError(err, "Could not save the voucher");
      setBusy(null);
    }
  }

  const fe = (name: string) => error?.field(name) ?? localErrors[name];

  /* ── review ───────────────────────────────────────────────────────────── */

  /** What must be true before review — the same things the server will insist on. */
  function problems(): Record<string, string> {
    const out: Record<string, string> = {};
    if (!form.voucher_type_id) out.voucher_type_id = t("required");
    if (amountNumber <= 0) out.amount = t("amountRequired");
    if (!form.purpose.trim()) out.purpose = t("required");
    if (!form.payee.trim()) out.payee = t("required");
    return out;
  }

  function scrollToField(name: string) {
    window.setTimeout(() => {
      const el = document.getElementById(name);
      if (!el) return;
      window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 120, behavior: "smooth" });
      el.focus({ preventScroll: true });
    }, 60);
  }

  function toReview() {
    const found = problems();
    setLocalErrors(found);
    const first = FIELD_ORDER.find((f) => found[f]);
    if (first) { scrollToField(first); return; }
    setReviewing(true);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  const workflow = resolveWorkflow(workflows, form.voucher_type_id);
  const route = routeFor(workflow, amountNumber, locale);
  const sw = locale === "sw";
  const departmentName = departments.find((d) => String(d.id) === form.department_id)?.name;
  const checks = [
    { ok: !!form.voucher_type_id && amountNumber > 0 && !!form.purpose.trim(), label: sw ? "Aina, kiasi na madhumuni" : "Type, amount and purpose" },
    { ok: !!form.payee.trim(), label: sw ? "Mlipwaji" : "Payee" },
    { ok: files.length > 0, label: files.length ? `${files.length} ${sw ? "nyaraka" : files.length === 1 ? "document" : "documents"}` : (sw ? "Hakuna nyaraka bado" : "No documents yet"), soft: true },
  ];

  const typeLabel = selectedType?.label ?? t("voucher");
  const kindLabel = form.kind === "bank" ? t("bank") : t("cash");

  if (reviewing) {
    return (
      <div className="vf-create app-create">
        <PageHeader
          back={<button type="button" className="vf-back app-linkish" onClick={() => setReviewing(false)}><Icon name="ph-arrow-left" size={15} /> {sw ? "Rudi kuhariri" : "Back to editing"}</button>}
          title={sw ? "Kagua kabla ya kuwasilisha" : "Review before submitting"}
          sub={sw ? "Hivi ndivyo waidhinishaji wataiona vocha." : "This is the voucher exactly as approvers will see and print it."}
        />
        <div className="app-review-grid">
          <div className="vf-document-frame app-review-sheet">
            <VoucherSheet voucher={preview} company={company} />
          </div>
          <aside className="app-review-side">
            <div className="vf-panel vf-panel-pad app-stack">
              <div>
                <h2 className="app-review-q">{sw ? "Tayari kuwasilisha?" : "Ready to submit?"}</h2>
                <p className="app-review-note">{sw
                  ? "Ukishawasilisha, huwezi kuihariri. Unaweza kuifuta hadi mtu atakapoishughulikia."
                  : "After you submit, you can't edit it. You can cancel it until someone acts on it."}</p>
              </div>
              <dl className="app-confirm">
                <div><dt>{t("amount")}</dt><dd className="tnum"><strong>{money(amountNumber, form.currency)}</strong></dd></div>
                <div><dt>{t("payee")}</dt><dd>{form.payee}</dd></div>
                <div><dt>{typeLabel}</dt><dd>{kindLabel}</dd></div>
                {route[0] && <div><dt>{sw ? "Anayesaini kwanza" : "First step"}</dt><dd>{route[0]}</dd></div>}
                <div><dt>{t("attachments")}</dt><dd>{files.length ? files.length : t("noneAttached")}</dd></div>
              </dl>
              <button type="button" className="btn btn-primary btn-lg btn-block" onClick={() => save("submit")} disabled={busy !== null}>
                {busy === "submit" ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={17} /> {t("submitVoucher")}</>}
              </button>
              <div className="app-review-alt">
                <button type="button" className="btn btn-ghost" onClick={() => setReviewing(false)} disabled={busy !== null}>{sw ? "Rudi kuhariri" : "Back to editing"}</button>
                <button type="button" className="btn btn-secondary" onClick={() => save("draft")} disabled={busy !== null}>
                  {busy === "draft" ? <Spinner /> : t("saveDraft")}
                </button>
              </div>
            </div>
          </aside>
        </div>
      </div>
    );
  }

  return (
    <div className="vf-create app-create">
      <PageHeader
        back={<Link className="vf-back" href="/vouchers"><Icon name="ph-arrow-left" size={15} /> {t("register")}</Link>}
        title={t("newVoucher")}
        sub={[selectedType?.next_number_preview, departmentName].filter(Boolean).join(" · ") || undefined}
      />

      <div className="app-create-grid">
        <form className="vf-panel app-create-form" noValidate onSubmit={(e) => { e.preventDefault(); toReview(); }}>

          {/* 01 · what it is for */}
          <CreateSection n="01" title={sw ? "Ni kwa ajili ya nini?" : "What is it for?"}
            sub={sw ? "Aina huamua kiambishi cha namba, mfano PV kwa vocha za malipo." : "The type sets the number prefix, e.g. PV for payment vouchers."}>
            <div className="app-type-grid" role="radiogroup" aria-label={t("voucherType")} id="voucher_type_id" tabIndex={-1}>
              {types.map((type) => {
                const hint = TYPE_HINT[type.prefix];
                return (
                  <button key={type.id} type="button" role="radio" aria-checked={form.voucher_type_id === type.id}
                    className="app-type" onClick={() => setForm((f) => ({ ...f, voucher_type_id: type.id }))}>
                    <Icon name={hint?.icon ?? "ph-file-text"} size={19} />
                    <span className="app-type-text">
                      <span className="app-type-name">{type.label}</span>
                      {hint && <span className="app-type-sub">{sw ? hint.sw : hint.en}</span>}
                    </span>
                  </button>
                );
              })}
            </div>
            {fe("voucher_type_id") && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {fe("voucher_type_id")}</div>}

            <div className="vf-form-row">
              <div className="vf-amount-field">
                <Field label={t("amount")} htmlFor="amount" error={fe("amount")} required>
                  <div className="vf-input-group">
                    <select className="input vf-input-group-addon" value={form.currency} onChange={set("currency")} aria-label={t("currency")}>
                      <option>TZS</option><option>USD</option><option>KES</option><option>EUR</option>
                    </select>
                    <input id="amount" className="input vf-amount-input" inputMode="decimal" value={form.amount} onChange={set("amount")}
                      placeholder="0" aria-invalid={!!fe("amount")} />
                  </div>
                </Field>
                {amountNumber > 0 && <div className="vf-amount-words">{words}</div>}
              </div>
              <Field label={t("date")} htmlFor="voucher_date" error={fe("voucher_date")} required>
                <input id="voucher_date" className="input" type="date" value={form.voucher_date} onChange={set("voucher_date")} />
              </Field>
            </div>
            <Field label={t("paymentPurpose")} htmlFor="purpose" error={fe("purpose")} required hint={sw ? "Mstari mmoja, kama utakavyoonekana kwenye vocha" : "One line, as it will appear on the voucher"}>
              <input id="purpose" className="input" value={form.purpose} onChange={set("purpose")} aria-invalid={!!fe("purpose")} />
            </Field>
            <Field label={t("description")} htmlFor="description" error={fe("description")} hint={t("optional")}>
              <textarea id="description" className="input" value={form.description} onChange={set("description")} />
            </Field>
          </CreateSection>

          {/* 02 · who gets paid, and how */}
          <CreateSection n="02" title={sw ? "Nani analipwa, na vipi" : "Who gets paid, and how"}
            sub={form.kind === "bank" ? t("paymentSubBank") : t("paymentSubCash")}>
            <div className="app-kind-row" id="kind">
              <div className="seg" role="radiogroup" aria-label={t("voucherFormat")}>
                <button type="button" role="radio" aria-checked={form.kind === "bank"}
                  onClick={() => setForm((f) => ({ ...f, kind: "bank", payment_method: f.payment_method === "Cash" ? "Bank Transfer" : f.payment_method }))}>
                  <Icon name="ph-bank" size={15} /> {t("bank")}
                </button>
                <button type="button" role="radio" aria-checked={form.kind === "cash"}
                  onClick={() => setForm((f) => ({ ...f, kind: "cash", payment_method: "Cash" }))}>
                  <Icon name="ph-money" size={15} /> {t("cash")}
                </button>
              </div>
              <span className="field-hint">{form.kind === "bank"
                ? (sw ? "Benki inajumuisha uhamisho, hundi na pesa kwa simu." : "Bank covers transfers, cheques and mobile money.")
                : (sw ? "Fedha taslimu hutoka kwenye akiba." : "Notes released from a petty cash float.")}</span>
            </div>
            <div className="vf-form-row">
              <Field label={t("payee")} htmlFor="payee" error={fe("payee")} required>
                <input id="payee" className="input" value={form.payee} onChange={set("payee")} placeholder={sw ? "Msambazaji au jina la mfanyakazi" : "Supplier or staff name"}
                  aria-invalid={!!fe("payee")} />
              </Field>
              <Field label={t("paymentMethod")} htmlFor="payment_method">
                <select id="payment_method" className="input" value={form.payment_method} onChange={set("payment_method")}>
                  {METHODS.map((m) => <option key={m}>{m}</option>)}
                </select>
              </Field>
            </div>
            {form.kind === "bank" ? (
              <>
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
                    <input id="payee_account_name" className="input" value={form.payee_account_name} onChange={set("payee_account_name")} placeholder={form.payee || (sw ? "Mmiliki wa akaunti" : "Account holder")} />
                  </Field>
                  <Field label={t("accountNo")} htmlFor="payee_account_number" error={fe("payee_account_number")}>
                    <input id="payee_account_number" className="input app-mono-input" value={form.payee_account_number} onChange={set("payee_account_number")} placeholder="0150000000000" />
                  </Field>
                </div>
                {company?.bank_account_number && (
                  <Note>{t("drawnOn")}: {company.bank_name} · {company.bank_account_number}{company.bank_branch ? ` · ${company.bank_branch}` : ""}</Note>
                )}
              </>
            ) : (
              <>
                <Field label={t("payFrom")} htmlFor="cash_float" hint={sw ? "Akiba ambayo fedha zitatoka" : "The float the notes come out of"}>
                  <input id="cash_float" className="input" value={form.cash_float} onChange={set("cash_float")} placeholder="Head office petty cash" />
                </Field>
                <Note>{t("cashReceiptNote")}</Note>
              </>
            )}
            <Field label={t("accountRef")} htmlFor="account_ref" error={fe("account_ref")} hint={sw ? "Namba ya ankara, nukuu au risiti" : "Invoice, quotation or receipt number"}>
              <input id="account_ref" className="input app-mono-input" value={form.account_ref} onChange={set("account_ref")} placeholder="INV-88213" />
            </Field>
          </CreateSection>

          {/* 03 · where it is charged */}
          <CreateSection n="03" title={sw ? "Inatozwa wapi" : "Where it is charged"}
            sub={sw ? "Idara huamua nani anasaini kwanza." : "The department decides who signs first."}>
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
            <Field label={t("requester")} htmlFor="requester">
              <input id="requester" className="input" value={user?.name ?? ""} readOnly />
            </Field>
          </CreateSection>

          {/* 04 · documents */}
          <CreateSection n="04" title={t("supportingDocs")}
            sub={sw ? `PDF, JPG au PNG. Hadi MB ${MAX_UPLOAD_MB} kila moja.` : `PDF, JPG or PNG. Up to ${MAX_UPLOAD_MB} MB each.`}>
            <label className="vf-dropzone app-dropzone" id="files"
              onDragOver={(e) => { e.preventDefault(); e.currentTarget.dataset.over = "true"; }}
              onDragLeave={(e) => { delete e.currentTarget.dataset.over; }}
              onDrop={(e) => {
                e.preventDefault(); delete e.currentTarget.dataset.over;
                // Copy now: the DataTransfer is emptied once this event returns.
                addFiles(Array.from(e.dataTransfer.files ?? []));
              }}>
              <input type="file" multiple accept={ACCEPT_ATTRIBUTE} hidden
                onChange={(e) => {
                  // Copy before resetting: clearing the value empties this same FileList.
                  const picked = Array.from(e.target.files ?? []);
                  e.target.value = "";
                  addFiles(picked);
                }} />
              <span className="vf-dropzone-icon"><Icon name="ph-upload-simple" size={20} /></span>
              <span className="app-dropzone-text">
                <span className="vf-dropzone-title">{t("dropFiles")} · <span className="app-linkish">{t("browseFiles")}</span></span>
                <span className="vf-dropzone-sub">{sw ? "Ankara, hati za kupokea, nukuu, risiti" : "Invoices, delivery notes, quotations, receipts"}</span>
              </span>
            </label>

            {rejected.length > 0 && (
              <div className="vf-alert tone-bad" role="alert">
                <Icon name="ph-warning-circle" size={20} style={{ flex: "none" }} />
                <div className="vf-alert-text">
                  <div className="vf-alert-title">{t("filesNotAdded")}</div>
                  {rejected.map((r) => (
                    <div key={`${r.name}-${r.reason}`}>
                      {r.name} — {r.reason === "type" ? t("fileWrongType") : r.reason === "size" ? `${t("fileTooLarge")} ${MAX_UPLOAD_MB} MB` : t("fileTooMany")}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {files.length > 0 && (
              <ul className="vf-files app-file-list">
                {files.map((file, i) => (
                  <li key={`${file.name}-${i}`}>
                    <div className="vf-file" style={{ cursor: "default" }}>
                      <span className="vf-file-icon" data-kind={file.type.startsWith("image/") ? "image" : "pdf"}><Icon name={file.type.startsWith("image/") ? "ph-image" : "ph-file-pdf"} size={18} /></span>
                      <span className="vf-file-text">
                        <span className="vf-file-name">{file.name}</span>
                        <span className="vf-file-size">{formatBytes(file.size)}</span>
                      </span>
                      <button type="button" className="btn btn-icon btn-sm" onClick={() => { setFiles((f) => f.filter((_, j) => j !== i)); setRejected([]); }} aria-label={`Remove ${file.name}`}>
                        <Icon name="ph-trash" size={15} />
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CreateSection>

          {/* 05 · note */}
          <CreateSection n="05" title={t("notesApprover")}
            sub={sw ? "Si lazima. Huonyeshwa kwa kila mwidhinishaji juu ya taarifa." : "Optional. Shown to each approver above the details."}>
            <Field label={t("notesApprover")} htmlFor="notes_to_approver">
              <textarea id="notes_to_approver" className="input" value={form.notes_to_approver} onChange={set("notes_to_approver")} style={{ minHeight: 80 }} />
            </Field>
          </CreateSection>

          {/* A form submits with Enter; the rail holds the visible actions. */}
          <button type="submit" hidden aria-hidden="true" tabIndex={-1} />
        </form>

        {/* On a phone the rail sits below the form, so the next step stays in reach here. */}
        <div className="app-create-mobilebar no-print">
          <span className="app-create-mobilebar-amount tnum">{money(amountNumber, form.currency)}</span>
          <button type="button" className="btn btn-primary" onClick={toReview} disabled={busy !== null}>
            {sw ? "Kagua na uwasilishe" : "Review & submit"} <Icon name="ph-arrow-right" size={15} />
          </button>
        </div>

        {/* ── the summary rail: amount, route, readiness ── */}
        <aside className="app-create-rail">
          <div className="vf-panel vf-panel-pad app-stack">
            <div className="app-rail-amount">
              <span className="app-rail-kicker">{typeLabel} · {kindLabel}</span>
              <span className="app-rail-value tnum">{money(amountNumber, form.currency)}</span>
              {form.payee.trim() && <span className="app-rail-kicker">{sw ? "kwa" : "to"} {form.payee}</span>}
            </div>
            {route.length > 0 && (
              <div className="app-rail-route">
                <span className="vf-label">{sw ? "Vocha hii itaenda kwa" : "This voucher will go to"}</span>
                <ol>
                  {route.map((step, i) => (
                    <li key={`${step}-${i}`}>
                      <span className="app-rail-dot"><Icon name={i === route.length - 1 && route.length > 1 ? "ph-wallet" : i === 0 ? "ph-signature" : "ph-seal-check"} size={13} /></span>
                      <span>{step}</span>
                    </li>
                  ))}
                </ol>
              </div>
            )}
            <ul className="app-rail-checks">
              {checks.map((c) => (
                <li key={c.label} data-ok={c.ok || undefined} data-soft={c.soft || undefined}>
                  <Icon name={c.ok ? "ph-check-circle" : c.soft ? "ph-circle-dashed" : "ph-warning-circle"} size={16} weight={c.ok ? "fill" : "regular"} />
                  {c.label}
                </li>
              ))}
            </ul>
            <button type="button" className="btn btn-primary btn-lg btn-block" onClick={toReview} disabled={busy !== null}>
              {sw ? "Kagua na uwasilishe" : "Review & submit"} <Icon name="ph-arrow-right" size={16} />
            </button>
            <button type="button" className="btn btn-ghost btn-block" onClick={() => save("draft")} disabled={busy !== null}>
              {busy === "draft" ? <Spinner /> : t("saveDraft")}
            </button>
          </div>
        </aside>
      </div>
    </div>
  );
}

function CreateSection({ n, title, sub, children }: { n: string; title: string; sub?: string; children: React.ReactNode }) {
  return (
    <section className="app-create-section">
      <div className="app-create-section-head">
        <span className="app-create-n">{n}</span>
        <h2>{title}</h2>
        {sub && <p>{sub}</p>}
      </div>
      <div className="app-create-section-body">{children}</div>
    </section>
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
