"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Lead, LEAD_STATUS_LABEL, LEAD_STATUSES, type LeadStatus, SOURCE_LABEL, SOURCES } from "@/lib/crm-types";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { CrmTabs, LeadBadge, useMoney, usePeople } from "@/components/crm-ui";

export default function LeadsPage() {
  return <ErpGate module="crm" permission="crm.view"><Leads /></ErpGate>;
}

const blank = { contact_name: "", company_name: "", phone: "", email: "", region: "", source: "referral", estimated_value: "", notes: "", owner_id: "" };

function Leads() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const money = useMoney();
  const people = usePeople();
  const initial = useQueryValue("status");
  const [chosen, setStatus] = useState<LeadStatus | "" | null>(null);
  const status = chosen ?? ((initial as LeadStatus | null | undefined) || "");
  const [source, setSource] = useState("");
  const [region, setRegion] = useState("");
  const [regions, setRegions] = useState<string[]>([]);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Lead> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<typeof blank | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  useEffect(() => { api.get<{ data: string[] }>("/erp/crm/leads/regions").then((r) => setRegions(r.data)).catch(() => undefined); }, []);

  const load = useCallback(() => {
    api.get<Paginated<Lead>>("/erp/crm/leads", { status: status || undefined, source: source || undefined, region: region || undefined, q: q || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [status, source, region, q, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: Lead }>("/erp/crm/leads", {
        contact_name: form.contact_name, company_name: form.company_name || null, phone: form.phone || null, email: form.email || null,
        region: form.region || null, source: form.source, estimated_value: Number(form.estimated_value || 0), notes: form.notes || null,
        owner_id: form.owner_id ? Number(form.owner_id) : undefined,
      });
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/crm/leads/${r.data.id}`);
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  const set = (k: keyof typeof blank, v: string) => setForm((f) => (f ? { ...f, [k]: v } : f));
  const text = (k: keyof typeof blank, label: string, type = "text", required = false) => (
    <Field label={label} htmlFor={`ld-${k}`} required={required} error={formError?.field(k)}>
      <input id={`ld-${k}`} className="input" type={type} value={form?.[k] ?? ""} onChange={(e) => set(k, e.target.value)} />
    </Field>
  );

  return (
    <div className="erp-page">
      <PageHeader title={t("crmNavLeads")} subtitle={t("crmLeadsSub")}
        actions={can("crm.manage") && <button className="btn btn-primary" onClick={() => { setForm(blank); setFormError(null); }}><Icon name="ph-plus" size={18} /> {t("crmNewLead")}</button>} />
      <CrmTabs />

      <Toolbar end={<>
        <select className="input" aria-label={t("crmSource")} value={source} onChange={(e) => { setSource(e.target.value); setPage(1); }} style={{ maxWidth: 200 }}>
          <option value="">{t("crmAllSources")}</option>
          {SOURCES.map((s) => <option key={s} value={s}>{t(SOURCE_LABEL[s])}</option>)}
        </select>
        <select className="input" aria-label={t("crmRegion")} value={region} onChange={(e) => { setRegion(e.target.value); setPage(1); }} style={{ maxWidth: 200 }}>
          <option value="">{t("crmAllRegions")}</option>
          {regions.map((r) => <option key={r} value={r}>{r}</option>)}
        </select>
      </>}>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("crmContact")}, ${t("crmBusiness")}`} />
        <FilterChips<LeadStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") },
          ...[...LEAD_STATUSES, "converted" as const].map((s) => ({ value: s, label: t(LEAD_STATUS_LABEL[s]) })),
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-user-plus" title={t("crmNoLeads")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("crmContact")}</th><th>{t("crmRegion")}</th><th>{t("crmSource")}</th><th className="num">{t("crmEstValue")}</th><th>{t("crmOwner")}</th><th>{t("crmCreated")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((l) => (
                  <tr key={l.id} className="is-clickable" onClick={() => router.push(`/erp/crm/leads/${l.id}`)}>
                    <td><Link href={`/erp/crm/leads/${l.id}`} className="erp-cell-link" onClick={(e) => e.stopPropagation()}>
                      <span className="erp-cell-title">{l.contact_name}</span>
                      <span className="erp-cell-sub">{l.company_name ?? ""}{l.company_name ? " · " : ""}<span className="tnum">{l.number}</span></span>
                    </Link></td>
                    <td>{l.region ?? "-"}</td>
                    <td>{t(SOURCE_LABEL[l.source] ?? "crmSrcOther")}</td>
                    <td className="num">{money(l.estimated_value)}</td>
                    <td>{l.owner?.name ?? "-"}</td>
                    <td className="tnum">{formatDate(l.created_at, locale)}</td>
                    <td><LeadBadge status={l.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {form && (
        <Dialog open wide title={t("crmNewLead")} onClose={() => setForm(null)} busy={busy}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.contact_name.trim()}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            {text("contact_name", t("crmContact"), "text", true)}
            {text("company_name", t("crmBusiness"))}
            {text("phone", t("erpPhone"), "tel")}
            {text("email", t("erpEmail"), "email")}
            {text("region", t("crmRegion"))}
            <Field label={t("crmSource")} htmlFor="ld-source" required error={formError?.field("source")}>
              <select id="ld-source" className="input" value={form.source} onChange={(e) => set("source", e.target.value)}>
                {SOURCES.map((s) => <option key={s} value={s}>{t(SOURCE_LABEL[s])}</option>)}
              </select>
            </Field>
            {text("estimated_value", t("crmEstValue"), "number")}
            {can("crm.assign") && (
              <Field label={t("crmOwner")} htmlFor="ld-owner" error={formError?.field("owner_id")}>
                <select id="ld-owner" className="input" value={form.owner_id} onChange={(e) => set("owner_id", e.target.value)}>
                  <option value="">{t("crmMe")}</option>
                  {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </Field>
            )}
          </div>
          <Field label={t("crmNotes")} htmlFor="ld-notes" error={formError?.field("notes")}>
            <textarea id="ld-notes" className="input" rows={3} value={form.notes} onChange={(e) => set("notes", e.target.value)} />
          </Field>
        </Dialog>
      )}
    </div>
  );
}
