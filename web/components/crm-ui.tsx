"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { formatDateTime } from "@/lib/format";
import {
  ACTIVITY_ICON, ACTIVITY_LABEL, ACTIVITY_TYPES, type Activity, type ActivityType, LEAD_STATUS_LABEL, type LeadStatus, leadTone,
  LOSS_REASONS, type Opportunity, type Person, REASON_LABEL, type Stage, STAGE_LABEL, stageTone, WIN_REASONS,
} from "@/lib/crm-types";
import { Badge, Dialog, Field, Icon } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { fill } from "@/components/erp-ui";

/** The CRM's own tab row: the sidebar carries one CRM entry, the areas live here. */
export function CrmTabs() {
  const { t } = useApp();
  const router = useRouter();
  const pathname = usePathname();
  const items = [
    { value: "/erp/crm", label: t("crmNavOverview"), icon: "ph-handshake" },
    { value: "/erp/crm/leads", label: t("crmNavLeads"), icon: "ph-user-plus" },
    { value: "/erp/crm/pipeline", label: t("crmNavPipeline"), icon: "ph-kanban" },
    { value: "/erp/crm/opportunities", label: t("crmNavOpportunities"), icon: "ph-target" },
    { value: "/erp/crm/activities", label: t("crmNavActivities"), icon: "ph-calendar-check" },
    { value: "/erp/crm/forecast", label: t("crmNavForecast"), icon: "ph-chart-line-up" },
  ];
  const current = [...items].reverse().find((i) => pathname === i.value || pathname.startsWith(`${i.value}/`))?.value ?? "/erp/crm";
  return <Tabs label={t("crmTitle")} value={current} onChange={(v) => router.push(v)} items={items} />;
}

export function StageBadge({ stage }: { stage: Stage }) {
  const { t } = useApp();
  return <Badge tone={stageTone(stage)} dot>{t(STAGE_LABEL[stage])}</Badge>;
}

export function LeadBadge({ status }: { status: LeadStatus }) {
  const { t } = useApp();
  return <Badge tone={leadTone(status)} dot>{t(LEAD_STATUS_LABEL[status])}</Badge>;
}

/** "TZS 4,500,000" in the company's base currency. */
export function useMoney() {
  const { config } = useErp();
  const currency = config?.settings.base_currency ?? "TZS";
  return (value: string | number | null | undefined) => `${currency} ${amount(value ?? 0)}`;
}

/** Everyone a CRM record may be assigned to. */
export function usePeople(): Person[] {
  const [people, setPeople] = useState<Person[]>([]);
  useEffect(() => { api.get<{ data: Person[] }>("/erp/crm/people").then((r) => setPeople(r.data)).catch(() => setPeople([])); }, []);
  return people;
}

/** What an activity hangs on, as a link. */
export function ActivityLink({ a }: { a: Activity }) {
  if (a.opportunity) return <Link href={`/erp/crm/opportunities/${a.opportunity.id}`} className="erp-cell-sub">{a.opportunity.number} · {a.opportunity.title}</Link>;
  if (a.lead) return <Link href={`/erp/crm/leads/${a.lead.id}`} className="erp-cell-sub">{a.lead.number} · {a.lead.contact_name}</Link>;
  if (a.customer) return <span className="erp-cell-sub">{a.customer.name}</span>;
  return null;
}

function isOverdue(a: Activity): boolean {
  return !a.completed_at && !!a.due_at && new Date(a.due_at) < new Date(new Date().toDateString());
}

/**
 * Activities as a list with their actions: complete with an outcome, reopen.
 * Used on the overview, the activities screen and both detail pages.
 */
export function ActivityList({ rows, onChanged, manage, empty }: { rows: Activity[]; onChanged: () => void; manage: boolean; empty: string }) {
  const { t, locale, toast } = useApp();
  const [completing, setCompleting] = useState<Activity | null>(null);
  const [outcome, setOutcome] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function complete() {
    if (!completing) return;
    setBusy(true); setError(null);
    try {
      await api.post(`/erp/crm/activities/${completing.id}/complete`, { outcome: outcome || null });
      toast(t("erpSaved"), completing.subject, "ok");
      setCompleting(null); setOutcome(""); onChanged();
    } catch (e) { setError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  async function reopen(a: Activity) {
    try { await api.post(`/erp/crm/activities/${a.id}/reopen`); onChanged(); } catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); }
  }

  if (rows.length === 0) return <p className="erp-muted crm-empty">{empty}</p>;

  return (
    <>
      <ul className="erp-list">
        {rows.map((a) => (
          <li key={a.id} className="crm-activity" data-done={a.completed_at ? "" : undefined}>
            <span className="erp-list-icon"><Icon name={ACTIVITY_ICON[a.type]} size={17} /></span>
            <span className="erp-list-main">
              <span className="erp-list-title">{a.subject}</span>
              <span className="erp-list-sub">
                {t(ACTIVITY_LABEL[a.type])}{a.due_at ? ` · ${formatDateTime(a.due_at, locale)}` : ""}{a.owner ? ` · ${a.owner.name}` : ""}
              </span>
              <ActivityLink a={a} />
              {a.outcome && <span className="erp-list-sub">{a.outcome}</span>}
            </span>
            {isOverdue(a) && <Badge tone="bad">{t("crmFilterOverdue")}</Badge>}
            {manage && (a.completed_at
              ? <button className="btn btn-secondary btn-sm" onClick={() => reopen(a)}>{t("crmReopen")}</button>
              : <button className="btn btn-secondary btn-sm" onClick={() => { setCompleting(a); setError(null); }}><Icon name="ph-check" size={15} /> {t("crmMarkDone")}</button>)}
          </li>
        ))}
      </ul>
      <Dialog open={completing !== null} title={completing ? fill(t("crmCompleteQ"), { subject: completing.subject }) : ""} onClose={() => setCompleting(null)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setCompleting(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={complete} disabled={busy}>{t("crmMarkDone")}</button>
        </>}>
        {error && <div className="field-error" role="alert">{error}</div>}
        <Field label={t("crmOutcome")} htmlFor="act-outcome">
          <input id="act-outcome" className="input" value={outcome} onChange={(e) => setOutcome(e.target.value)} autoFocus />
        </Field>
      </Dialog>
    </>
  );
}

/** Schedules a call, meeting, visit or task, optionally tied to a lead, deal or customer. */
export function ActivityDialog({ open, onClose, onSaved, link }: {
  open: boolean; onClose: () => void; onSaved: () => void;
  link?: { lead_id?: number; opportunity_id?: number; customer_id?: number | null };
}) {
  const { t, toast } = useApp();
  const { can } = useErp();
  const people = usePeople();
  const [form, setForm] = useState({ type: "call" as ActivityType, subject: "", due_at: "", notes: "", owner_id: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  async function save() {
    setBusy(true); setError(null);
    try {
      await api.post("/erp/crm/activities", {
        type: form.type, subject: form.subject, notes: form.notes || null, due_at: form.due_at || null,
        owner_id: form.owner_id ? Number(form.owner_id) : undefined, ...link,
      });
      toast(t("erpSaved"), form.subject, "ok");
      setForm({ type: "call", subject: "", due_at: "", notes: "", owner_id: "" });
      onSaved(); onClose();
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <Dialog open={open} title={t("crmNewActivity")} onClose={onClose} busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.subject.trim()}>{t("erpSave")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <div className="erp-form-grid">
        <Field label={t("crmType")} htmlFor="act-type" error={error?.field("type")}>
          <select id="act-type" className="input" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as ActivityType })}>
            {ACTIVITY_TYPES.map((type) => <option key={type} value={type}>{t(ACTIVITY_LABEL[type])}</option>)}
          </select>
        </Field>
        <Field label={t("crmDue")} htmlFor="act-due" error={error?.field("due_at")}>
          <input id="act-due" className="input" type="datetime-local" value={form.due_at} onChange={(e) => setForm({ ...form, due_at: e.target.value })} />
        </Field>
      </div>
      <Field label={t("crmSubject")} htmlFor="act-subject" required error={error?.field("subject")}>
        <input id="act-subject" className="input" value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} />
      </Field>
      {can("crm.assign") && (
        <Field label={t("crmOwner")} htmlFor="act-owner" error={error?.field("owner_id")}>
          <select id="act-owner" className="input" value={form.owner_id} onChange={(e) => setForm({ ...form, owner_id: e.target.value })}>
            <option value="">{t("crmMe")}</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
      )}
      <Field label={t("crmNotes")} htmlFor="act-notes" error={error?.field("notes")}>
        <textarea id="act-notes" className="input" rows={3} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
      </Field>
    </Dialog>
  );
}

/** Asks why a deal closed (required when lost) and moves it. */
export function CloseDealDialog({ deal, stage, onClose, onDone }: {
  deal: Opportunity | null; stage: "won" | "lost"; onClose: () => void; onDone: (deal: Opportunity) => void;
}) {
  const { t } = useApp();
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reasons = stage === "won" ? WIN_REASONS : LOSS_REASONS;

  async function save() {
    if (!deal) return;
    setBusy(true); setError(null);
    try {
      const r = await api.post<{ data: Opportunity }>(`/erp/crm/opportunities/${deal.id}/stage`, { stage, reason: reason || null, note: note || null });
      setReason(""); setNote("");
      onDone(r.data);
    } catch (e) { setError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  return (
    <Dialog open={deal !== null} onClose={onClose} busy={busy} icon={stage === "won" ? "ph-trophy" : "ph-x-circle"} tone={stage === "won" ? "ok" : "warn"}
      title={deal ? fill(t("crmCloseQ"), { number: deal.number }) : ""} sub={t("crmCloseSub")}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className={stage === "won" ? "btn btn-primary" : "btn btn-danger"} onClick={save} disabled={busy || (stage === "lost" && !reason)}>
          {t(stage === "won" ? "crmCloseWon" : "crmCloseLost")}
        </button>
      </>}>
      {error && <div className="field-error" role="alert">{error}</div>}
      <Field label={t("crmReason")} htmlFor="close-reason" required={stage === "lost"}>
        <select id="close-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)}>
          <option value="">{t("crmNone")}</option>
          {reasons.map((r) => <option key={r} value={r}>{t(REASON_LABEL[r])}</option>)}
        </select>
      </Field>
      <Field label={t("crmNote")} htmlFor="close-note">
        <input id="close-note" className="input" value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
    </Dialog>
  );
}
