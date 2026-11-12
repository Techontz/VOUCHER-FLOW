"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Party, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { type Lead, LEAD_STATUS_LABEL, LEAD_STATUSES, OPEN_STAGES, SOURCE_LABEL, SOURCES, STAGE_LABEL, type Stage } from "@/lib/crm-types";
import { Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { ActivityDialog, ActivityList, LeadBadge, StageBadge, useMoney, usePeople } from "@/components/crm-ui";
import { RecordFiles } from "@/components/crm-attachments";

export default function LeadPage() {
  return <ErpGate module="crm" permission="crm.view"><LeadDetail /></ErpGate>;
}

function LeadDetail() {
  const { t, locale, toast } = useApp();
  const { can, has } = useErp();
  const router = useRouter();
  const money = useMoney();
  const people = usePeople();
  const { id } = useParams<{ id: string }>();
  const [lead, setLead] = useState<Lead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Record<string, string> | null>(null);
  const [converting, setConverting] = useState(false);
  const [convert, setConvert] = useState({ customer_id: "", title: "", value: "", expected_close_date: "", stage: "prospecting" as Stage });
  const [customers, setCustomers] = useState<Party[]>([]);
  const [assigning, setAssigning] = useState<string | null>(null);
  const [scheduling, setScheduling] = useState(false);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Lead }>(`/erp/crm/leads/${id}`).then((r) => setLead(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  useEffect(() => {
    if (converting && can("customers.view") && customers.length === 0) {
      api.get<{ data: Party[] }>("/erp/customers", { per_page: 200, active_only: 1 }).then((r) => setCustomers(r.data)).catch(() => undefined);
    }
  }, [converting, can, customers.length]);

  async function run(fn: () => Promise<unknown>, done: () => void) {
    setBusy(true); setFormError(null);
    try { await fn(); done(); load(); } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} />;
  if (!lead) return <LoadingBlock rows={6} />;

  const manage = can("crm.manage") && lead.status !== "converted";
  const set = (k: string, v: string) => setEditing((f) => (f ? { ...f, [k]: v } : f));

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/crm/leads" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("crmNavLeads")}</Link>}
        kicker={lead.number}
        title={lead.contact_name}
        subtitle={[lead.company_name, lead.region, t(SOURCE_LABEL[lead.source] ?? "crmSrcOther")].filter(Boolean).join(" · ")}
        actions={<>
          <LeadBadge status={lead.status} />
          {manage && <button className="btn btn-secondary" onClick={() => { setFormError(null); setEditing({
            contact_name: lead.contact_name, company_name: lead.company_name ?? "", phone: lead.phone ?? "", email: lead.email ?? "",
            region: lead.region ?? "", source: lead.source, status: lead.status, estimated_value: String(Number(lead.estimated_value)),
            notes: lead.notes ?? "", lost_reason: lead.lost_reason ?? "",
          }); }}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {can("crm.assign") && lead.status !== "converted" && <button className="btn btn-secondary" onClick={() => { setFormError(null); setAssigning(String(lead.owner_id ?? "")); }}><Icon name="ph-user-switch" size={17} /> {t("crmAssign")}</button>}
          {manage && lead.status === "qualified" && <button className="btn btn-primary" onClick={() => {
            setFormError(null); setConverting(true);
            setConvert({ customer_id: "", title: `${lead.company_name || lead.contact_name}`, value: String(Number(lead.estimated_value)), expected_close_date: "", stage: "prospecting" });
          }}><Icon name="ph-user-circle-plus" size={18} /> {t("crmConvert")}</button>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard title={t("crmDetails")}>
          <dl className="erp-review">
            <dt>{t("erpPhone")}</dt><dd>{lead.phone ? <a href={`tel:${lead.phone}`}>{lead.phone}</a> : "-"}</dd>
            <dt>{t("erpEmail")}</dt><dd>{lead.email ? <a href={`mailto:${lead.email}`}>{lead.email}</a> : "-"}</dd>
            <dt>{t("crmEstValue")}</dt><dd className="tnum">{money(lead.estimated_value)}</dd>
            <dt>{t("crmOwner")}</dt><dd>{lead.owner?.name ?? "-"}</dd>
            <dt>{t("crmCreated")}</dt><dd>{formatDate(lead.created_at, locale)}</dd>
            {lead.lost_reason && <><dt>{t("crmLostReason")}</dt><dd>{lead.lost_reason}</dd></>}
            {lead.notes && <><dt>{t("crmNotes")}</dt><dd style={{ whiteSpace: "pre-wrap" }}>{lead.notes}</dd></>}
            {lead.customer && <><dt>{t("crmCustomer")}</dt><dd>{fill(t("crmConvertedTo"), { customer: `${lead.customer.name} (${lead.customer.code})` })}{lead.converted_at ? ` · ${formatDateTime(lead.converted_at, locale)}` : ""}</dd></>}
            {lead.opportunity && <><dt>{t("crmOpportunity")}</dt><dd><Link href={`/erp/crm/opportunities/${lead.opportunity.id}`}>{lead.opportunity.number} · {lead.opportunity.title}</Link> <StageBadge stage={lead.opportunity.stage} /></dd></>}
          </dl>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("crmActivities")} pad={false}
          action={can("crm.manage") && <button className="btn btn-secondary btn-sm" onClick={() => setScheduling(true)}><Icon name="ph-plus" size={15} /> {t("crmNewActivity")}</button>}>
          <ActivityList rows={lead.activities ?? []} onChanged={load} manage={can("crm.manage")} empty={t("crmNoActivities")} />
        </GlassCard>

        {has("documents") && can("documents.view") && (
          <div className="erp-span-3"><RecordFiles type="lead" id={lead.id} /></div>
        )}
      </div>

      <ActivityDialog open={scheduling} onClose={() => setScheduling(false)} onSaved={load} link={{ lead_id: lead.id, customer_id: lead.customer_id }} />

      {editing && (
        <Dialog open wide title={lead.number} onClose={() => setEditing(null)} busy={busy}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setEditing(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" disabled={busy || !editing.contact_name.trim()} onClick={() => run(() => api.put(`/erp/crm/leads/${lead.id}`, {
              ...editing, estimated_value: Number(editing.estimated_value || 0),
              company_name: editing.company_name || null, phone: editing.phone || null, email: editing.email || null, region: editing.region || null,
              notes: editing.notes || null, lost_reason: editing.lost_reason || null,
            }), () => { setEditing(null); toast(t("erpSaved"), lead.number, "ok"); })}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            {(["contact_name", "company_name", "phone", "email", "region", "estimated_value"] as const).map((k) => (
              <Field key={k} label={t(({ contact_name: "crmContact", company_name: "crmBusiness", phone: "erpPhone", email: "erpEmail", region: "crmRegion", estimated_value: "crmEstValue" } as const)[k])} htmlFor={`le-${k}`} error={formError?.field(k)}>
                <input id={`le-${k}`} className="input" type={k === "estimated_value" ? "number" : k === "email" ? "email" : "text"} value={editing[k]} onChange={(e) => set(k, e.target.value)} />
              </Field>
            ))}
            <Field label={t("crmSource")} htmlFor="le-source" error={formError?.field("source")}>
              <select id="le-source" className="input" value={editing.source} onChange={(e) => set("source", e.target.value)}>
                {SOURCES.map((s) => <option key={s} value={s}>{t(SOURCE_LABEL[s])}</option>)}
              </select>
            </Field>
            <Field label={t("erpStatus")} htmlFor="le-status" error={formError?.field("status")}>
              <select id="le-status" className="input" value={editing.status} onChange={(e) => set("status", e.target.value)}>
                {LEAD_STATUSES.map((s) => <option key={s} value={s}>{t(LEAD_STATUS_LABEL[s])}</option>)}
              </select>
            </Field>
          </div>
          {editing.status === "lost" && (
            <Field label={t("crmLostReason")} htmlFor="le-lost" required error={formError?.field("lost_reason")}>
              <input id="le-lost" className="input" value={editing.lost_reason} onChange={(e) => set("lost_reason", e.target.value)} />
            </Field>
          )}
          <Field label={t("crmNotes")} htmlFor="le-notes" error={formError?.field("notes")}>
            <textarea id="le-notes" className="input" rows={3} value={editing.notes} onChange={(e) => set("notes", e.target.value)} />
          </Field>
        </Dialog>
      )}

      <Dialog open={converting} title={t("crmConvert")} sub={t("crmConvertSub")} icon="ph-user-circle-plus" onClose={() => setConverting(false)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConverting(false)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy} onClick={() => run(async () => {
            const r = await api.post<{ message: string; data: { opportunity: { id: number } } }>(`/erp/crm/leads/${lead.id}/convert`, {
              customer_id: convert.customer_id ? Number(convert.customer_id) : null, title: convert.title || null,
              value: convert.value === "" ? null : Number(convert.value), expected_close_date: convert.expected_close_date || null, stage: convert.stage,
            });
            toast(r.message, undefined, "ok");
            router.push(`/erp/crm/opportunities/${r.data.opportunity.id}`);
          }, () => setConverting(false))}>{t("crmConvert")}</button>
        </>}>
        {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
        {can("customers.view") && (
          <Field label={t("crmExistingCustomer")} htmlFor="cv-customer" hint={t("crmExistingCustomerHint")} error={formError?.field("customer_id")}>
            <select id="cv-customer" className="input" value={convert.customer_id} onChange={(e) => setConvert({ ...convert, customer_id: e.target.value })}>
              <option value="">{t("crmNone")}</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name} ({c.code})</option>)}
            </select>
          </Field>
        )}
        <Field label={t("crmTitleField")} htmlFor="cv-title" error={formError?.field("title")}>
          <input id="cv-title" className="input" value={convert.title} onChange={(e) => setConvert({ ...convert, title: e.target.value })} />
        </Field>
        <div className="erp-form-grid">
          <Field label={t("crmValue")} htmlFor="cv-value" error={formError?.field("value")}>
            <input id="cv-value" className="input" type="number" min={0} value={convert.value} onChange={(e) => setConvert({ ...convert, value: e.target.value })} />
          </Field>
          <Field label={t("crmCloseDate")} htmlFor="cv-date" error={formError?.field("expected_close_date")}>
            <input id="cv-date" className="input" type="date" value={convert.expected_close_date} onChange={(e) => setConvert({ ...convert, expected_close_date: e.target.value })} />
          </Field>
          <Field label={t("crmStage")} htmlFor="cv-stage">
            <select id="cv-stage" className="input" value={convert.stage} onChange={(e) => setConvert({ ...convert, stage: e.target.value as Stage })}>
              {OPEN_STAGES.map((s) => <option key={s} value={s}>{t(STAGE_LABEL[s])}</option>)}
            </select>
          </Field>
        </div>
      </Dialog>

      <Dialog open={assigning !== null} title={t("crmAssign")} onClose={() => setAssigning(null)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setAssigning(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy || !assigning} onClick={() => run(() => api.post(`/erp/crm/leads/${lead.id}/assign`, { owner_id: Number(assigning) }), () => setAssigning(null))}>{t("crmAssign")}</button>
        </>}>
        {formError && <div className="field-error" role="alert">{formError.message}</div>}
        <Field label={t("crmAssignTo")} htmlFor="as-owner">
          <select id="as-owner" className="input" value={assigning ?? ""} onChange={(e) => setAssigning(e.target.value)}>
            <option value="" disabled>-</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
      </Dialog>
    </div>
  );
}
