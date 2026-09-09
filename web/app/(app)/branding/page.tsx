"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Field, Icon, Note, PageHeader, Panel, SectionTitle, Spinner } from "@/components/ui";
import { VoucherSheet } from "@/components/voucher-sheet";
import type { Voucher } from "@/lib/types";

/**
 * A company's own identity.
 *
 * Everything on this page is per-tenant: the logo, the letterhead details, the
 * banking particulars a bank voucher is drawn on, and the colour that carries
 * onto the printed document. Nothing about any one company is baked into the
 * platform — the demo tenant simply filled this in.
 */
export default function BrandingPage() {
  const { t, company, refresh, toast, reportError } = useApp();
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({
    name: "", legal_name: "", email: "", phone: "", address: "", website: "", tin: "",
    primary_color: "#2E3192", voucher_footer_text: "",
    bank_name: "", bank_account_name: "", bank_account_number: "", bank_branch: "",
    logo_url: "", logo_mark_url: "",
  });

  useEffect(() => {
    if (!company) return;
    setForm({
      name: company.name ?? "",
      legal_name: company.legal_name ?? "",
      email: company.email ?? "",
      phone: company.phone ?? "",
      address: company.address ?? "",
      website: company.website ?? "",
      tin: company.tin ?? "",
      primary_color: company.primary_color ?? "#2E3192",
      voucher_footer_text: company.voucher_footer_text ?? "",
      bank_name: company.bank_name ?? "",
      bank_account_name: company.bank_account_name ?? "",
      bank_account_number: company.bank_account_number ?? "",
      bank_branch: company.bank_branch ?? "",
      logo_url: company.logo_url ?? "",
      logo_mark_url: company.logo_mark_url ?? "",
    });
  }, [company]);

  const set = (key: keyof typeof form) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setForm((f) => ({ ...f, [key]: e.target.value }));

  /** Reads an uploaded image straight into the record, as an upload would. */
  function pickImage(key: "logo_url" | "logo_mark_url") {
    return (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      if (file.size > 2_000_000) {
        toast(t("logo"), "That image is over 2 MB — use a smaller one.", "warn");
        return;
      }
      const reader = new FileReader();
      reader.onload = () => setForm((f) => ({ ...f, [key]: String(reader.result) }));
      reader.readAsDataURL(file);
    };
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api.put("/company/branding", form);
      await refresh();
      toast("Branding saved", "Your identity now appears on the interface and on every voucher.", "ok");
    } catch (err) {
      reportError(err, "Could not save your branding");
    } finally {
      setBusy(false);
    }
  }

  /* A live specimen of the company's own letterhead, so the effect of every
     field on this page is visible before it reaches a real voucher. */
  const specimen = {
    id: 0, number: "PV-2026-000000", status: "draft", kind: "bank",
    status_key: "draft", status_label: t("drafts"), status_label_en: "Draft",
    status_label_sw: "Rasimu", status_tag: "tag-neutral",
    payee: "Specimen Supplier Limited",
    purpose: "Specimen voucher — this is how your document will print",
    description: "Every field on this page appears on the printed voucher exactly as shown here.",
    amount: 1250000, currency: company?.currency ?? "TZS",
    amount_text: `${company?.currency ?? "TZS"} 1,250,000`,
    amount_in_words: "One million two hundred fifty thousand shillings only",
    payment_method: "Bank Transfer", account_ref: "INV-000000",
    category: "Specimen", cost_centre: "CC-000",
    voucher_date: new Date().toISOString().slice(0, 10),
    notes_to_approver: null, verification_code: "VF-SPEC-IMEN",
    voucher_type_id: 0, voucher_type: { id: 0, name: "Payment Voucher", label: "Payment Voucher" },
    department_id: null, department: { id: 0, name: "Finance" },
    requester_id: 0,
    requester: { id: 0, name: "Specimen Requester", initials: "SR", job_title: "Officer" },
    workflow_id: null, current_step_position: null, current_step: null,
    is_signed_at_current_step: false, is_editable: false, is_terminal: false,
    submitted_at: null, approved_at: null, rejected_at: null,
    paid_at: null, payment_reference: null, paid_by: null,
    payee_bank: "Specimen Bank", payee_account_name: "Specimen Supplier Limited",
    payee_account_number: "0000000000000", payee_bank_branch: "Main Branch",
    cheque_number: null, cash_float: null, received_by: null,
    created_at: null, updated_at: null, timeline: [], attachments: [],
  } as unknown as Voucher;

  const previewCompany = company ? { ...company, ...form } : null;

  return (
    <div style={{ maxWidth: 1300 }}>
      <PageHeader
        kicker={t("branding")}
        title={t("branding")}
        sub="Your logo, letterhead and banking details are applied to the interface and printed on every voucher this company issues."
        actions={
          <button className="btn btn-primary" onClick={save} disabled={busy}>
            {busy ? <Spinner /> : t("saveChanges")}
          </button>
        }
      />

      <div className="vf-split">
        <form onSubmit={save} style={{ display: "grid", gap: "var(--space-4)" }}>
          {/* ── identity ── */}
          <Panel title={t("companyDetails")}>
            <div style={{ display: "grid", gap: "var(--space-3)" }}>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("companyName")} htmlFor="b-name" required>
                  <input id="b-name" className="input" value={form.name} onChange={set("name")} required />
                </Field>
                <Field label={t("legalName")} htmlFor="b-legal" hint="As it appears on the document">
                  <input id="b-legal" className="input" value={form.legal_name} onChange={set("legal_name")} />
                </Field>
              </div>

              <Field label={t("address")} htmlFor="b-address">
                <textarea id="b-address" className="input" value={form.address}
                  onChange={set("address")} style={{ minHeight: 58 }} />
              </Field>

              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("phone")} htmlFor="b-phone">
                  <input id="b-phone" className="input" value={form.phone} onChange={set("phone")} />
                </Field>
                <Field label={t("email")} htmlFor="b-email">
                  <input id="b-email" className="input" type="email" value={form.email} onChange={set("email")} />
                </Field>
              </div>

              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("website")} htmlFor="b-web">
                  <input id="b-web" className="input" value={form.website} onChange={set("website")} />
                </Field>
                <Field label={t("tinNumber")} htmlFor="b-tin">
                  <input id="b-tin" className="input" value={form.tin} onChange={set("tin")}
                    style={{ fontVariantNumeric: "tabular-nums" }} />
                </Field>
              </div>
            </div>
          </Panel>

          {/* ── marks and colour ── */}
          <Panel title={t("documentLetterhead")}>
            <div style={{ display: "grid", gap: "var(--space-4)" }}>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "var(--space-4)" }}>
                <LogoField
                  label={t("logoLockup")}
                  hint="Printed on the voucher letterhead"
                  value={form.logo_url}
                  onPick={pickImage("logo_url")}
                  onClear={() => setForm((f) => ({ ...f, logo_url: "" }))}
                  boxStyle={{ height: 66 }}
                />
                <LogoField
                  label={t("logoMark")}
                  hint="Used wherever the interface has room for an icon only"
                  value={form.logo_mark_url}
                  onPick={pickImage("logo_mark_url")}
                  onClear={() => setForm((f) => ({ ...f, logo_mark_url: "" }))}
                  boxStyle={{ height: 66, width: 66 }}
                />
              </div>

              <Field label={t("colour")} htmlFor="b-colour"
                hint="Carried onto the document's header rule and the interface accents">
                <div style={{ display: "flex", gap: "var(--space-2)", alignItems: "center" }}>
                  <input id="b-colour" type="color" value={form.primary_color}
                    onChange={set("primary_color")}
                    style={{ width: 54, height: 42, padding: 3, borderRadius: 10, border: "1px solid var(--vf-line)", background: "var(--vf-elev-2)" }} />
                  <input className="input" value={form.primary_color} onChange={set("primary_color")}
                    style={{ maxWidth: 140, fontVariantNumeric: "tabular-nums" }} />
                </div>
              </Field>

              <Field label={t("voucherFooterText")} htmlFor="b-footer"
                hint="The small print at the foot of every printed voucher">
                <textarea id="b-footer" className="input" value={form.voucher_footer_text}
                  onChange={set("voucher_footer_text")} style={{ minHeight: 62 }} />
              </Field>
            </div>
          </Panel>

          {/* ── the account bank vouchers are drawn on ── */}
          <Panel title={t("bankDetails")}
            sub="Printed on every bank voucher as the account the payment is drawn on">
            <div style={{ display: "grid", gap: "var(--space-3)" }}>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("bank")} htmlFor="b-bank">
                  <input id="b-bank" className="input" value={form.bank_name} onChange={set("bank_name")} />
                </Field>
                <Field label={t("branch")} htmlFor="b-branch">
                  <input id="b-branch" className="input" value={form.bank_branch} onChange={set("bank_branch")} />
                </Field>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: "var(--space-3)" }}>
                <Field label={t("accountName")} htmlFor="b-acc-name">
                  <input id="b-acc-name" className="input" value={form.bank_account_name} onChange={set("bank_account_name")} />
                </Field>
                <Field label={t("accountNo")} htmlFor="b-acc-no">
                  <input id="b-acc-no" className="input" value={form.bank_account_number}
                    onChange={set("bank_account_number")} style={{ fontVariantNumeric: "tabular-nums" }} />
                </Field>
              </div>
              <Note>Cash vouchers name the petty cash float instead, chosen when the voucher is raised.</Note>
            </div>
          </Panel>

          <button className="btn btn-primary" type="submit" disabled={busy} style={{ justifySelf: "start" }}>
            {busy ? <Spinner /> : t("saveChanges")}
          </button>
        </form>

        {/* ── live specimen ── */}
        <div className="vf-sticky">
          <SectionTitle>{t("livePreview")}</SectionTitle>
          <div className="vf-document-frame">
            <VoucherSheet voucher={specimen} company={previewCompany} />
          </div>
          <div style={{ marginTop: "var(--space-3)" }}>
            <Note>{t("previewNote")}</Note>
          </div>
        </div>
      </div>
    </div>
  );
}

/** An image field that shows what is currently set and lets it be replaced. */
function LogoField({
  label, hint, value, onPick, onClear, boxStyle,
}: {
  label: string; hint: string; value: string;
  onPick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onClear: () => void;
  boxStyle?: React.CSSProperties;
}) {
  const { t } = useApp();
  return (
    <div>
      <div style={{ fontSize: 12.5, fontWeight: 500, color: "var(--color-neutral-700)", marginBottom: 6 }}>
        {label}
      </div>
      <div style={{
        display: "grid", placeItems: "center", padding: "var(--space-3)",
        border: "1px dashed var(--vf-line-strong)", borderRadius: 12,
        background: "#fff", minHeight: 82, ...boxStyle,
      }}>
        {value
          ? <img src={value} alt="" style={{ maxHeight: 56, maxWidth: "100%", objectFit: "contain" }} />
          : <Icon name="ph-image" size={24} color="#b8c0d0" />}
      </div>
      <div style={{ display: "flex", gap: 6, marginTop: 8, flexWrap: "wrap" }}>
        <label className="btn btn-secondary btn-sm">
          <Icon name="ph-upload-simple" size={14} /> {value ? t("replace") : t("uploadImage")}
          <input type="file" accept="image/png,image/jpeg,image/svg+xml" style={{ display: "none" }} onChange={onPick} />
        </label>
        {value && (
          <button type="button" className="btn btn-ghost btn-sm" onClick={onClear}>{t("remove")}</button>
        )}
      </div>
      <div style={{ fontSize: 12, color: "var(--color-neutral-600)", marginTop: 5 }}>{hint}</div>
    </div>
  );
}
