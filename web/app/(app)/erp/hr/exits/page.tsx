"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload, Tzs, useLookups } from "@/components/hr-ui";

interface Item { id: number; area: string; item: string; note: string | null; cleared_at: string | null; cleared_by: string | null }
interface Exit {
  id: number; employee_id: number; employee?: { id: number; full_name: string; employee_number: string; job_title: string | null; status: string };
  type: string; notice_date: string; last_working_day: string; reason: string | null; status: string; leave_days_payable: number;
  leave_pay?: number; other_dues?: number; outstanding_loans?: number; final_dues?: number; items?: Item[];
}
const TYPES = ["resignation", "termination", "retirement", "end_of_contract", "redundancy", "death"];
const human = (s: string) => s.replace(/_/g, " ");

export default function ExitsPage() {
  return <HrGate anyOf={["hr.view"]}><Exits /></HrGate>;
}

function Exits() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const preselect = useQueryValue("employee");
  const [status, setStatus] = useState("in_progress");
  const [rows, setRows] = useState<Paginated<Exit> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<Exit | null>(null);
  const [openingState, setOpeningState] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [editing, setEditing] = useState(false);
  const [completing, setCompleting] = useState(false);
  const [busy, setBusy] = useState(false);
  const manage = can("hr.manage");

  const load = useCallback(() => { api.get<Paginated<Exit>>("/erp/hr/exits", { status: status || undefined }).then(setRows).catch((e) => setError(e.message)); }, [status]);
  useEffect(load, [load]);
  // ?employee= from a profile opens the form once.
  const opening = openingState || (!!preselect && manage && !dismissed);
  const setOpening = (v: boolean) => { setOpeningState(v); if (!v) setDismissed(true); };
  const show = (id: number) => api.get<{ data: Exit }>(`/erp/hr/exits/${id}`).then((r) => setOpen(r.data));

  async function clear(item: Item) {
    if (!open) return;
    try { const r = await api.post<{ data: Exit }>(`/erp/hr/exits/${open.id}/items/${item.id}`, { cleared: !item.cleared_at }); setOpen(r.data); load(); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }
  async function complete() {
    if (!open) return;
    setBusy(true);
    try { const r = await api.post<{ message: string; data: Exit }>(`/erp/hr/exits/${open.id}/complete`); toast(r.message, undefined, "ok"); setOpen(r.data); setCompleting(false); load(); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); } finally { setBusy(false); }
  }

  const pending = (open?.items ?? []).filter((i) => !i.cleared_at).length;

  return (
    <div className="erp-page">
      <PageHeader title={t("hrExits")} subtitle={t("hrExitsSub")}
        actions={manage && <button className="btn btn-primary" onClick={() => setOpening(true)}><Icon name="ph-sign-out" size={18} /> {t("hrStartExit")}</button>} />
      <Toolbar><FilterChips value={status} onChange={setStatus} items={[{ value: "in_progress", label: t("hrStInProgress") }, { value: "completed", label: t("hrStCompleted") }, { value: "", label: t("erpAll") }]} /></Toolbar>

      {error && <ErrorState message={error} />}
      <div className="erp-grid">
        <GlassCard title={t("hrExits")} pad={false}>
          {!rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-sign-out" title={t("hrNoExits")} /> : (
            <div className="erp-list">
              {rows.data.map((x) => (
                <button key={x.id} type="button" className="erp-list-row" aria-current={open?.id === x.id} onClick={() => show(x.id)}>
                  <span className="erp-list-main"><span className="erp-list-title">{x.employee?.full_name}</span><span className="erp-list-sub">{human(x.type)} · {t("hrLastDay")} {formatDate(x.last_working_day, locale)}</span></span>
                  <HrStatus status={x.status} />
                </button>
              ))}
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={open ? `${open.employee?.full_name} · ${human(open.type)}` : t("hrChooseExit")}
          action={open && manage && open.status === "in_progress" && <>
            <button className="btn btn-secondary btn-sm" onClick={() => setEditing(true)}>{t("erpEdit")}</button>{" "}
            <button className="btn btn-primary btn-sm" disabled={pending > 0} title={pending ? t("hrClearFirst") : undefined} onClick={() => setCompleting(true)}>{t("hrCompleteExit")}</button>
          </>}>
          {!open ? <EmptyState icon="ph-hand-pointing" title={t("hrChooseExit")} /> : (
            <>
              <div className="erp-form-grid">
                <Field label={t("hrNoticeDate")}><div>{formatDate(open.notice_date, locale)}</div></Field>
                <Field label={t("hrLastDay")}><div>{formatDate(open.last_working_day, locale)}</div></Field>
                <Field label={t("hrLeaveDaysPayable")}><div className="tnum">{open.leave_days_payable}</div></Field>
                {open.final_dues !== undefined && <>
                  <Field label={t("hrLeavePay")}><div><Tzs value={open.leave_pay} /></div></Field>
                  <Field label={t("hrOtherDues")}><div><Tzs value={open.other_dues} /></div></Field>
                  <Field label={t("hrOutstandingLoans")}><div>-<Tzs value={open.outstanding_loans} /></div></Field>
                  <Field label={t("hrFinalDues")}><div><strong><Tzs value={open.final_dues} /></strong></div></Field>
                </>}
              </div>
              {open.reason && <p className="erp-muted">{open.reason}</p>}
              <h3 className="erp-subhead">{t("hrClearance")}</h3>
              <div className="erp-checks">
                {(open.items ?? []).map((i) => (
                  <label key={i.id} className="erp-check">
                    <input type="checkbox" checked={!!i.cleared_at} disabled={!manage || open.status !== "in_progress"} onChange={() => clear(i)} />
                    <span><span className="erp-check-label">{i.area}: {i.item}</span>{i.cleared_at && <span className="erp-check-hint">{i.cleared_by} · {formatDate(i.cleared_at, locale)}</span>}</span>
                  </label>
                ))}
              </div>
              {open.employee && <p><Link href={`/erp/hr/employees/${open.employee.id}`}>{t("hrOpenRecord")}</Link></p>}
            </>
          )}
        </GlassCard>
      </div>

      <FormDialog open={opening} title={t("hrStartExit")} onClose={() => setOpening(false)}
        initial={{ employee_id: preselect ?? "", type: "resignation", notice_date: today(), last_working_day: today() }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "type", label: t("erpType"), type: "select", required: true, options: TYPES.map((x) => ({ value: x, label: human(x) })) },
          { name: "notice_date", label: t("hrNoticeDate"), type: "date", required: true },
          { name: "last_working_day", label: t("hrLastDay"), type: "date", required: true },
          ...(can("hr.salary") ? [{ name: "other_dues", label: t("hrOtherDues"), type: "number" as const }] : []),
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { const r = await api.post<{ data: Exit }>("/erp/hr/exits", payload(v, ["employee_id", "other_dues"])); setOpening(false); setOpen(r.data); load(); }} />

      <FormDialog open={editing} title={t("erpEdit")} onClose={() => setEditing(false)}
        initial={open ? { type: open.type, last_working_day: open.last_working_day.slice(0, 10), reason: open.reason ?? "", other_dues: String(open.other_dues ?? 0) } : {}}
        fields={[
          { name: "type", label: t("erpType"), type: "select", options: TYPES.map((x) => ({ value: x, label: human(x) })) },
          { name: "last_working_day", label: t("hrLastDay"), type: "date" },
          ...(can("hr.salary") ? [{ name: "other_dues", label: t("hrOtherDues"), type: "number" as const }] : []),
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { if (!open) return; const body = payload(v, ["other_dues"]); if (!can("hr.salary")) delete body.other_dues; const r = await api.put<{ data: Exit }>(`/erp/hr/exits/${open.id}`, body); setOpen(r.data); setEditing(false); load(); }} />

      <Dialog open={completing} busy={busy} tone="warn" title={t("hrCompleteExit")} onClose={() => setCompleting(false)}
        actions={<><button className="btn btn-secondary" onClick={() => setCompleting(false)} disabled={busy}>{t("erpCancel")}</button><button className="btn btn-primary" onClick={complete} disabled={busy}>{t("hrConfirm")}</button></>}>
        <p>{t("hrCompleteExitHint")}</p>
      </Dialog>
    </div>
  );
}
