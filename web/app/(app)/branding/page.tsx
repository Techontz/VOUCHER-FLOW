"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Field, Icon, Note, Panel, Spinner } from "@/components/ui";
import { SettingsLayout } from "@/components/app-ui";
import { VoucherSheet } from "@/components/voucher-sheet";
import type { ColorTheme, Voucher } from "@/lib/types";

type LogoSlot = "logo" | "logo_mark";

/** The interface palettes; the CSS for each lives in styles/app.css. */
const COLOR_THEMES: { key: ColorTheme; label: [string, string]; swatch: string }[] = [
  { key: "blue", label: ["Blue", "Bluu"], swatch: "#2563eb" },
  { key: "emerald", label: ["Emerald", "Zumaridi"], swatch: "#047857" },
  { key: "violet", label: ["Violet", "Zambarau"], swatch: "#6d28d9" },
  { key: "rose", label: ["Rose", "Waridi"], swatch: "#be123c" },
];

/** What the API accepts for a logo; SVG is refused there because it can carry script. */
const LOGO_TYPES = "image/png,image/jpeg,image/webp";
const LOGO_MAX_BYTES = 2 * 1024 * 1024;

/**
 * A company's own identity.
 *
 * Everything on this page is per-tenant: the logo, the letterhead details, the
 * banking particulars a bank voucher is drawn on, and the colour that carries
 * onto the printed document. Nothing about any one company is baked into the
 * platform — the demo tenant simply filled this in.
 */
export default function BrandingPage() {
  const { t, locale, company, refresh, toast, reportError } = useApp();
  const sw = locale === "sw";
  const [busy, setBusy] = useState(false);
  // New artwork waiting to be uploaded, and artwork marked for removal. The
  // *_url fields in the form are only the on-screen preview of either.
  const [files, setFiles] = useState<Partial<Record<LogoSlot, File>>>({});
  const [removed, setRemoved] = useState<Partial<Record<LogoSlot, boolean>>>({});
  const [form, setForm] = useState({
    name: "", legal_name: "", email: "", phone: "", address: "", website: "", tin: "",
    primary_color: "#2E3192", color_theme: "blue" as ColorTheme, voucher_footer_text: "",
    bank_name: "", bank_account_name: "", bank_account_number: "", bank_branch: "",
    logo_url: "", logo_mark_url: "",
  });

  useEffect(() => {
    if (!company) return;
    // Re-seeding the form whenever the saved company changes is the point.
    /* eslint-disable react-hooks/set-state-in-effect */
    setForm({
      name: company.name ?? "",
      legal_name: company.legal_name ?? "",
      email: company.email ?? "",
      phone: company.phone ?? "",
      address: company.address ?? "",
      website: company.website ?? "",
      tin: company.tin ?? "",
      primary_color: company.primary_color ?? "#2E3192",
      color_theme: company.color_theme ?? "blue",
      voucher_footer_text: company.voucher_footer_text ?? "",
      bank_name: company.bank_name ?? "",
      bank_account_name: company.bank_account_name ?? "",
      bank_account_number: company.bank_account_number ?? "",
      bank_branch: company.bank_branch ?? "",
      logo_url: company.logo_url ?? "",
      logo_mark_url: company.logo_mark_url ?? "",
    });
    setFiles({});
    setRemoved({});
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [company]);

  // Preview the chosen palette on the whole interface while this page is
  // open; leaving without saving puts the company's own palette back.
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.accent = form.color_theme;
    return () => { root.dataset.accent = company?.color_theme ?? "blue"; };
  }, [form.color_theme, company?.color_theme]);

  const set = (key: keyof typeof form) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setForm((f) => ({ ...f, [key]: e.target.value }));

  /** Holds a chosen image for upload on save, and previews it now. */
  function pickImage(slot: LogoSlot) {
    return (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      e.target.value = "";
      if (!file) return;
      if (!LOGO_TYPES.split(",").includes(file.type)) {
        toast(t("logo"), "Use a PNG, JPG or WebP image.", "warn");
        return;
      }
      if (file.size > LOGO_MAX_BYTES) {
        toast(t("logo"), "That image is over 2 MB — use a smaller one.", "warn");
        return;
      }
      setFiles((f) => ({ ...f, [slot]: file }));
      setRemoved((r) => ({ ...r, [slot]: false }));
      const reader = new FileReader();
      reader.onload = () => setForm((f) => ({ ...f, [`${slot}_url`]: String(reader.result) }));
      reader.readAsDataURL(file);
    };
  }

  function clearImage(slot: LogoSlot) {
    setFiles((f) => ({ ...f, [slot]: undefined }));
    setRemoved((r) => ({ ...r, [slot]: true }));
    setForm((f) => ({ ...f, [`${slot}_url`]: "" }));
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      // Details, colours and bank account in one request; artwork after it,
      // one file per request, through the validated upload route.
      const { logo_url: _logo, logo_mark_url: _mark, ...details } = form;
      await api.put("/company", details);

      for (const slot of ["logo", "logo_mark"] as const) {
        const file = files[slot];
        if (file) {
          const upload = new FormData();
          upload.append("logo", file);
          upload.append("slot", slot);
          await api.upload("/company/logo", upload);
        } else if (removed[slot]) {
          await api.delete(`/company/logo?slot=${slot}`);
        }
      }

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
    <SettingsLayout
      title={t("branding")}
      sub="Your logo, letterhead and banking details are applied to the interface and printed on every voucher this company issues."
      actions={
        <button className="btn btn-primary" onClick={save} disabled={busy}>
          {busy ? <Spinner /> : t("saveChanges")}
        </button>
      }
    >
      <div className="app-branding-grid">
        <form onSubmit={save} className="app-stack">
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
                <Field label={t("email")} htmlFor="b-email" required>
                  <input id="b-email" className="input" type="email" value={form.email} onChange={set("email")} required />
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
                  onPick={pickImage("logo")}
                  onClear={() => clearImage("logo")}
                  boxStyle={{ height: 66 }}
                />
                <LogoField
                  label={t("logoMark")}
                  hint="Used wherever the interface has room for an icon only"
                  value={form.logo_mark_url}
                  onPick={pickImage("logo_mark")}
                  onClear={() => clearImage("logo_mark")}
                  boxStyle={{ height: 66, width: 66 }}
                />
              </div>

              <Field label={t("colour")} htmlFor="b-colour"
                hint="Carried onto the printed document's header rule and voucher tag">
                <div style={{ display: "flex", gap: "var(--space-2)", alignItems: "center" }}>
                  <input id="b-colour" type="color" value={form.primary_color}
                    onChange={set("primary_color")}
                    className="app-color-swatch" />
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

          {/* ── the interface palette ── */}
          <Panel title={sw ? "Rangi ya mfumo" : "Interface colour"}
            sub={sw
              ? "Rangi ambayo kila mtu katika kampuni hii anaiona kwenye vitufe, viungo na vichupo. Inafanya kazi kwenye hali ya giza na mwanga."
              : "The colour everyone in this company sees on buttons, links and tabs. Each works in dark and light mode."}>
            <div className="app-theme-picker" role="radiogroup" aria-label={sw ? "Rangi ya mfumo" : "Interface colour"}>
              {COLOR_THEMES.map((option) => (
                <button key={option.key} type="button" role="radio"
                  aria-checked={form.color_theme === option.key}
                  className="app-theme-option"
                  onClick={() => setForm((f) => ({ ...f, color_theme: option.key }))}>
                  <span className="app-theme-swatch" style={{ background: option.swatch }} aria-hidden="true">
                    {form.color_theme === option.key && <Icon name="ph-check" size={14} color="#fff" />}
                  </span>
                  {option.label[sw ? 1 : 0]}
                </button>
              ))}
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
        <div className="app-branding-preview">
          <div className="app-preview-label"><Icon name="ph-eye" size={14} /> {t("livePreview")}</div>
          <div className="vf-document-frame">
            <VoucherSheet voucher={specimen} company={previewCompany} />
          </div>
          <div style={{ marginTop: "var(--space-3)" }}>
            <Note>{t("previewNote")}</Note>
          </div>
        </div>
      </div>
    </SettingsLayout>
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
      {/* Paper-white in both themes: a logo is artwork for the printed page,
          and a dark logo on a dark well would be invisible. */}
      <div className="app-logo-well" data-paper="true" style={boxStyle}>
        {value
          ? <img src={value} alt="" style={{ maxHeight: 56, maxWidth: "100%", objectFit: "contain" }} />
          : <Icon name="ph-image" size={24} color="#b8c0d0" />}
      </div>
      <div style={{ display: "flex", gap: 6, marginTop: 8, flexWrap: "wrap" }}>
        <label className="btn btn-secondary btn-sm">
          <Icon name="ph-upload-simple" size={14} /> {value ? t("replace") : t("uploadImage")}
          <input type="file" accept={LOGO_TYPES} style={{ display: "none" }} onChange={onPick} />
        </label>
        {value && (
          <button type="button" className="btn btn-ghost btn-sm" onClick={onClear}>{t("remove")}</button>
        )}
      </div>
      <div style={{ fontSize: 12, color: "var(--color-neutral-600)", marginTop: 5 }}>{hint} · PNG, JPG or WebP, up to 2 MB</div>
    </div>
  );
}
