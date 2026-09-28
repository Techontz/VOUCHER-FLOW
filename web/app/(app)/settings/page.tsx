"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Dialog, Field, Icon, LoadingBlock, Spinner } from "@/components/ui";
import { FormSection, SettingsLayout } from "@/components/app-ui";
import type { Company, VoucherType } from "@/lib/types";
import { WorkflowBuilder } from "./workflow-builder";

type Tab = "workflow" | "types" | "company";

export default function SettingsPage() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("workflow");

  // The section lives in the address (#workflow, #types, #company), so the
  // settings menu can link straight to it and a refresh keeps your place.
  useEffect(() => {
    const read = () => {
      const hash = window.location.hash.replace("#", "");
      setTab(hash === "types" || hash === "company" ? hash : "workflow");
    };
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, []);

  const heading = tab === "workflow" ? t("approvalWorkflow") : tab === "types" ? t("voucherSettings") : t("companyProfile");

  return (
    <SettingsLayout title={heading} sub={tab === "workflow" ? t("wfIntro") : undefined}>
      {tab === "workflow" && <WorkflowBuilder />}
      {tab === "types" && <VoucherTypes />}
      {tab === "company" && <CompanyProfile />}
    </SettingsLayout>
  );
}

/* ──────────────────────────────────────────────── voucher types ─────────── */

function VoucherTypes() {
  const { t, toast, reportError } = useApp();
  const [types, setTypes] = useState<VoucherType[] | null>(null);
  const [dialog, setDialog] = useState(false);
  const [editing, setEditing] = useState<VoucherType | null>(null);
  const [form, setForm] = useState({ name: "", name_sw: "", code: "", prefix: "", seq_padding: 6, next_number: 1, reset_yearly: true });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: VoucherType[] }>("/voucher-types", { include_inactive: true })
      .then((r) => setTypes(r.data)).catch(() => setTypes([]));
  }, []);

  useEffect(load, [load]);

  function openCreate() {
    setEditing(null);
    setForm({ name: "", name_sw: "", code: "", prefix: "", seq_padding: 6, next_number: 1, reset_yearly: true });
    setFormError(null); setDialog(true);
  }

  function openEdit(type: VoucherType) {
    setEditing(type);
    setForm({
      name: type.name, name_sw: type.name_sw ?? "", code: type.code, prefix: type.prefix,
      seq_padding: type.seq_padding, next_number: type.next_number, reset_yearly: type.reset_yearly,
    });
    setFormError(null); setDialog(true);
  }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      if (editing) await api.put(`/voucher-types/${editing.id}`, form);
      else await api.post("/voucher-types", form);
      toast(editing ? "Voucher type updated" : "Voucher type created", form.name, "ok");
      setDialog(false); load();
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the voucher type");
    } finally { setBusy(false); }
  }

  if (!types) return <LoadingBlock rows={4} />;

  return (
    <section className="vf-panel">
      <div className="vf-panel-head">
        <div className="vf-panel-head-main app-panel-title"><h2>{t("voucherSettings")}</h2><span className="vf-count">{types.length}</span></div>
        <button className="btn btn-primary btn-sm" onClick={openCreate}><Icon name="ph-plus" size={14} /> {t("add")}</button>
      </div>

      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr><th>Type</th><th>Code</th><th>Prefix</th><th>Next number</th><th className="num">{t("vouchers")}</th><th>{t("status")}</th><th /></tr>
          </thead>
          <tbody>
            {types.map((type) => (
              <tr key={type.id}>
                <td style={{ fontWeight: 500 }}>{type.name}</td>
                <td style={{ color: "var(--color-neutral-700)" }}>{type.code}</td>
                <td>{type.prefix}</td>
                <td style={{ fontVariantNumeric: "tabular-nums" }}>{type.next_number_preview}</td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{type.vouchers_count ?? 0}</td>
                <td><span className={`badge ${type.is_active ? "tone-ok" : "tone-neutral"}`}>{type.is_active ? t("active") : "Inactive"}</span></td>
                <td style={{ textAlign: "right" }}>
                  <button className="btn btn-ghost btn-sm" onClick={() => openEdit(type)} aria-label={`Edit ${type.name}`}>
                    <Icon name="ph-pencil-simple" size={14} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Dialog open={dialog} title={editing ? t("edit") : t("add")} onClose={() => setDialog(false)}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setDialog(false)} disabled={busy}>{t("cancel")}</button>
          <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || !form.code || !form.prefix}>
            {busy ? <Spinner /> : t("save")}
          </button>
        </>}>
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <Field label="Name (English)" htmlFor="vt-name" error={formError?.field("name")} required>
            <input id="vt-name" className="input" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} required />
          </Field>
          <Field label="Name (Swahili)" htmlFor="vt-name-sw">
            <input id="vt-name-sw" className="input" value={form.name_sw} onChange={(e) => setForm((f) => ({ ...f, name_sw: e.target.value }))} />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Code" htmlFor="vt-code" error={formError?.field("code")} required>
              <input id="vt-code" className="input" value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value }))} required />
            </Field>
            <Field label="Prefix" htmlFor="vt-prefix" error={formError?.field("prefix")} hint="e.g. PV → PV-2026-000001" required>
              <input id="vt-prefix" className="input" value={form.prefix} onChange={(e) => setForm((f) => ({ ...f, prefix: e.target.value.toUpperCase() }))} required />
            </Field>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Digits" htmlFor="vt-pad">
              <input id="vt-pad" className="input" type="number" min={1} max={10} value={form.seq_padding}
                onChange={(e) => setForm((f) => ({ ...f, seq_padding: Number(e.target.value) }))} />
            </Field>
            <Field label="Next number" htmlFor="vt-next">
              <input id="vt-next" className="input" type="number" min={1} value={form.next_number}
                onChange={(e) => setForm((f) => ({ ...f, next_number: Number(e.target.value) }))} />
            </Field>
          </div>
          <label className="radio">
            <input type="checkbox" checked={form.reset_yearly} onChange={(e) => setForm((f) => ({ ...f, reset_yearly: e.target.checked }))} />
            <span className="dot" />
            Reset the sequence each year
          </label>
        </div>
      </Dialog>
    </section>
  );
}

/* ─────────────────────────────────────────────── company profile ────────── */

function CompanyProfile() {
  const { t, company, refresh, toast, reportError } = useApp();
  const [form, setForm] = useState({ name: "", legal_name: "", email: "", phone: "", address: "", website: "", currency: "TZS", locale: "en", timezone: "" });
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!company) return;
    setForm({
      name: company.name, legal_name: company.legal_name ?? "", email: company.email,
      phone: company.phone ?? "", address: company.address ?? "", website: company.website ?? "",
      currency: company.currency, locale: company.locale, timezone: company.timezone,
    });
  }, [company]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api.put<{ data: Company }>("/company", form);
      await refresh();
      toast("Company updated", form.name, "ok");
    } catch (err) { reportError(err, "Could not save the company profile"); }
    finally { setBusy(false); }
  }

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  if (!company) return <LoadingBlock rows={4} />;

  return (
    <form onSubmit={save} className="vf-panel">
      <div className="vf-panel-pad">
        <FormSection title={t("companyProfile")} description="The name and legal identity printed on every voucher.">
          <Field label={t("companyName")} htmlFor="c-name" required>
            <input id="c-name" className="input" value={form.name} onChange={set("name")} required />
          </Field>
          <Field label="Legal name" htmlFor="c-legal"><input id="c-legal" className="input" value={form.legal_name} onChange={set("legal_name")} /></Field>
        </FormSection>
        <FormSection title={t("phone")} description="How people reach the company.">
          <Field label={t("businessEmail")} htmlFor="c-email" required>
            <input id="c-email" className="input" type="email" value={form.email} onChange={set("email")} required />
          </Field>
          <div className="vf-form-row">
            <Field label={t("phone")} htmlFor="c-phone"><input id="c-phone" className="input" value={form.phone} onChange={set("phone")} /></Field>
            <Field label={t("website")} htmlFor="c-web"><input id="c-web" className="input" value={form.website} onChange={set("website")} /></Field>
          </div>
          <Field label={t("address")} htmlFor="c-address"><input id="c-address" className="input" value={form.address} onChange={set("address")} /></Field>
        </FormSection>
        <FormSection title={t("currency")} description="Defaults for new vouchers.">
          <div className="vf-form-row">
            <Field label={t("currency")} htmlFor="c-currency">
              <select id="c-currency" className="input" value={form.currency} onChange={set("currency")}>
                <option>TZS</option><option>KES</option><option>USD</option><option>EUR</option>
              </select>
            </Field>
            <Field label={t("language")} htmlFor="c-locale">
              <select id="c-locale" className="input" value={form.locale} onChange={set("locale")}>
                <option value="en">English</option><option value="sw">Kiswahili</option>
              </select>
            </Field>
          </div>
        </FormSection>
      </div>
      <div className="app-form-foot">
        <span className="field-hint">{company.name}</span>
        <div className="app-form-foot-end"><button className="btn btn-primary" disabled={busy}>{busy ? <Spinner /> : t("saveChanges")}</button></div>
      </div>
    </form>
  );
}
