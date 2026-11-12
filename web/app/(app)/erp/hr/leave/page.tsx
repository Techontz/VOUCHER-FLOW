"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { currentPeriod, type LeaveBalance, type LeaveRequest, type LeaveType, monthLabel, n, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Tabs, Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload, useLookups } from "@/components/hr-ui";

type Tab = "requests" | "calendar" | "balances" | "types";

export default function LeavePage() {
  return <HrGate anyOf={["hr.view", "hr.leave.approve"]}><Leave /></HrGate>;
}

function Leave() {
  const { t } = useApp();
  const { can } = useErp();
  const initial = useQueryValue("tab");
  const [chosen, setTab] = useState<Tab | null>(null);
  const tab: Tab = chosen ?? (initial === "calendar" || initial === "balances" ? initial : "requests");

  return (
    <div className="erp-page">
      <PageHeader title={t("hrLeave")} subtitle={t("hrLeaveSub")}
        actions={<>
          {!can("hr.view") && <Link className="btn btn-secondary" href="/erp/hr/attendance"><Icon name="ph-fingerprint" size={18} /> {t("hrTeamAttendance")}</Link>}
          <Link className="btn btn-secondary" href="/erp/hr/me"><Icon name="ph-airplane-tilt" size={18} /> {t("hrRequestMyLeave")}</Link>
        </>} />
      <Tabs label={t("hrLeave")} value={tab} onChange={setTab} items={[
        { value: "requests", label: t("hrRequests") }, { value: "calendar", label: t("hrCalendar") },
        ...(can("hr.view") ? [{ value: "balances" as Tab, label: t("hrBalances") }, { value: "types" as Tab, label: t("hrLeaveTypes") }] : []),
      ]} />
      {tab === "requests" && <Requests />}
      {tab === "calendar" && <Calendar />}
      {tab === "balances" && <Balances />}
      {tab === "types" && <Types />}
    </div>
  );
}

function Requests() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const [status, setStatus] = useState("pending");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<LeaveRequest> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deciding, setDeciding] = useState<{ request: LeaveRequest; action: "approve" | "reject" | "cancel" } | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [filing, setFiling] = useState(false);
  const [types, setTypes] = useState<LeaveType[]>([]);

  const load = useCallback(() => {
    api.get<Paginated<LeaveRequest>>("/erp/hr/leave/requests", { status: status || undefined, page }).then(setRows).catch((e) => setError(e.message));
  }, [status, page]);
  useEffect(load, [load]);
  useEffect(() => { api.get<{ data: LeaveType[] }>("/erp/hr/leave-types").then((r) => setTypes(r.data)).catch(() => undefined); }, []);

  async function decide() {
    if (!deciding) return;
    setBusy(true); setActionError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/hr/leave/requests/${deciding.request.id}/${deciding.action}`, deciding.action === "cancel" ? undefined : { note: note || null });
      toast(r.message, undefined, "ok"); setDeciding(null); setNote(""); load();
    } catch (e) { setActionError((e as Error).message); } finally { setBusy(false); }
  }

  return (
    <>
      <Toolbar end={can("hr.manage") && <button className="btn btn-secondary" onClick={() => setFiling(true)}><Icon name="ph-plus" size={16} /> {t("hrFileLeave")}</button>}>
        <FilterChips value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "pending", label: t("hrStPending") }, { value: "approved", label: t("hrStApproved") },
          { value: "rejected", label: t("hrStRejected") }, { value: "cancelled", label: t("hrStCancelled") }, { value: "", label: t("erpAll") },
        ]} />
      </Toolbar>
      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-airplane-tilt" title={t("hrNoLeave")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrEmployee")}</th><th>{t("hrLeaveType")}</th><th>{t("hrDates")}</th><th className="num">{t("hrDays")}</th><th>{t("erpStatus")}</th><th /></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id}>
                    <td><span className="erp-cell-title">{r.employee?.full_name}</span><span className="erp-cell-sub">{r.employee?.department?.name ?? ""}{r.reason ? ` · ${r.reason}` : ""}</span></td>
                    <td>{r.leave_type?.name}{r.leave_type?.paid === false && <span className="erp-cell-sub">{t("hrUnpaid")}</span>}</td>
                    <td className="tnum">{formatDate(r.start_date, locale)} - {formatDate(r.end_date, locale)}</td>
                    <td className="num">{n(r.days)}</td>
                    <td><HrStatus status={r.status} />{r.decision_note && <span className="erp-cell-sub">{r.decider?.name}: {r.decision_note}</span>}</td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      {r.can_decide && <>
                        <button className="btn btn-primary btn-sm" onClick={() => setDeciding({ request: r, action: "approve" })}>{t("hrApprove")}</button>{" "}
                        <button className="btn btn-secondary btn-sm" onClick={() => setDeciding({ request: r, action: "reject" })}>{t("hrReject")}</button>
                      </>}
                      {can("hr.manage") && (r.status === "approved" || r.status === "pending") && <button className="btn btn-secondary btn-sm" onClick={() => setDeciding({ request: r, action: "cancel" })}>{t("erpCancel")}</button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <Dialog open={!!deciding} busy={busy} tone={deciding?.action === "approve" ? "ok" : "warn"} onClose={() => setDeciding(null)}
        title={deciding?.action === "approve" ? t("hrApproveLeave") : deciding?.action === "reject" ? t("hrRejectLeave") : t("hrCancelLeave")}
        summary={deciding ? [
          { label: t("hrEmployee"), value: deciding.request.employee?.full_name },
          { label: t("hrLeaveType"), value: deciding.request.leave_type?.name },
          { label: t("hrDates"), value: `${formatDate(deciding.request.start_date, locale)} - ${formatDate(deciding.request.end_date, locale)} (${n(deciding.request.days)})` },
        ] : undefined}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setDeciding(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={decide} disabled={busy || (deciding?.action === "reject" && note.trim().length < 3)}>{t("hrConfirm")}</button>
        </>}>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
        {deciding?.action !== "cancel" && (
          <Field label={deciding?.action === "reject" ? t("hrReasonRequired") : t("hrNoteOptional")} htmlFor="leave-note">
            <textarea id="leave-note" className="input" rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        )}
      </Dialog>

      <FormDialog open={filing} title={t("hrFileLeave")} onClose={() => setFiling(false)} initial={{ start_date: today(), end_date: today() }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "leave_type_id", label: t("hrLeaveType"), type: "select", required: true, options: types.filter((x) => x.is_active).map((x) => ({ value: x.id, label: x.name })) },
          { name: "start_date", label: t("hrStart"), type: "date", required: true },
          { name: "end_date", label: t("hrEnd"), type: "date", required: true },
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { await api.post("/erp/hr/leave/requests", payload(v, ["employee_id", "leave_type_id"])); toast(t("erpSaved"), undefined, "ok"); setFiling(false); load(); }} />
    </>
  );
}

function Calendar() {
  const { t, locale } = useApp();
  const [month, setMonth] = useState(currentPeriod());
  const [rows, setRows] = useState<LeaveRequest[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { api.get<{ data: LeaveRequest[] }>("/erp/hr/leave/calendar", { month }).then((r) => setRows(r.data)).catch((e) => setError(e.message)); }, [month]);

  const [y, m] = month.split("-").map(Number);
  const days = new Date(y, m, 0).getDate();
  const people = new Map<number, { name: string; requests: LeaveRequest[] }>();
  (rows ?? []).forEach((r) => {
    const p = people.get(r.employee_id) ?? { name: r.employee?.full_name ?? "", requests: [] };
    p.requests.push(r);
    people.set(r.employee_id, p);
  });
  const cell = (requests: LeaveRequest[], day: number) => {
    const date = `${month}-${String(day).padStart(2, "0")}`;
    return requests.find((r) => r.start_date.slice(0, 10) <= date && r.end_date.slice(0, 10) >= date);
  };

  return (
    <>
      <Toolbar>
        <Field label={t("hrMonth")} htmlFor="cal-month"><input id="cal-month" className="input" type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></Field>
        <span className="erp-muted">{monthLabel(month, locale)} · <Badge tone="ok">{t("hrStApproved")}</Badge> <Badge tone="info">{t("hrStPending")}</Badge></span>
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : people.size === 0 ? <EmptyState icon="ph-sun" title={t("hrNobodyAway")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table hr-calendar">
            <thead><tr><th>{t("hrEmployee")}</th>{Array.from({ length: days }, (_, i) => <th key={i} className="num">{i + 1}</th>)}</tr></thead>
            <tbody>
              {[...people.entries()].map(([id, p]) => (
                <tr key={id}>
                  <td style={{ whiteSpace: "nowrap" }}>{p.name}</td>
                  {Array.from({ length: days }, (_, i) => {
                    const r = cell(p.requests, i + 1);
                    return <td key={i} title={r ? `${r.leave_type?.name} (${r.status})` : undefined}
                      style={{ padding: 2, background: r ? (r.status === "approved" ? "var(--st-ok-bg, #d7f5e3)" : "var(--st-info-bg, #dbe8ff)") : undefined }} />;
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function Balances() {
  const { t } = useApp();
  const { can } = useErp();
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<{ types: { id: number; name: string }[]; data: { employee: { id: number; full_name: string; employee_number: string }; balances: LeaveBalance[] }[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [adjusting, setAdjusting] = useState<{ balance: LeaveBalance; name: string } | null>(null);

  const load = useCallback(() => { api.get<NonNullable<typeof data>>("/erp/hr/leave/balances", { year }).then(setData).catch((e) => setError(e.message)); }, [year]);
  useEffect(load, [load]);

  return (
    <>
      <Toolbar><Field label={t("hrYear")} htmlFor="bal-year"><input id="bal-year" className="input" type="number" value={year} onChange={(e) => setYear(Number(e.target.value))} style={{ maxWidth: 120 }} /></Field></Toolbar>
      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrEmployee")}</th>{data.types.map((x) => <th key={x.id} className="num">{x.name}</th>)}</tr></thead>
            <tbody>
              {data.data.map((row) => (
                <tr key={row.employee.id}>
                  <td><span className="erp-cell-title">{row.employee.full_name}</span><span className="erp-cell-sub tnum">{row.employee.employee_number}</span></td>
                  {data.types.map((x) => {
                    const b = row.balances.find((bal) => bal.leave_type_id === x.id);
                    return (
                      <td key={x.id} className="num">
                        {b ? (can("hr.manage")
                          ? <button className="btn btn-ghost btn-sm tnum" title={t("hrAdjust")} onClick={() => setAdjusting({ balance: b, name: row.employee.full_name })}>{b.available ?? `${b.taken}`}</button>
                          : <span className="tnum">{b.available ?? b.taken}</span>) : "-"}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="erp-muted">{t("hrBalancesHint")}</p>
      <FormDialog open={!!adjusting} title={`${t("hrAdjust")} · ${adjusting?.name ?? ""} · ${adjusting?.balance.leave_type.name ?? ""}`} onClose={() => setAdjusting(null)}
        intro={adjusting && <p className="erp-muted">{t("hrEntitled")} {adjusting.balance.entitled} · {t("hrAccrued")} {adjusting.balance.accrued} · {t("hrTaken")} {adjusting.balance.taken} · {t("hrAvailable")} {adjusting.balance.available ?? "-"}</p>}
        initial={{ adjustment: String(adjusting?.balance.adjustment ?? 0), carried_forward: String(adjusting?.balance.carried_forward ?? 0) }}
        fields={[
          { name: "carried_forward", label: t("hrCarriedForward"), type: "number" },
          { name: "adjustment", label: t("hrAdjustment"), type: "number" },
          { name: "reason", label: t("hrReason"), required: true, wide: true },
        ]}
        onSubmit={async (v) => { await api.put(`/erp/hr/leave/balances/${adjusting?.balance.id}`, payload(v, ["adjustment", "carried_forward"])); setAdjusting(null); load(); }} />
    </>
  );
}

function Types() {
  const { t } = useApp();
  const { can } = useErp();
  const [types, setTypes] = useState<LeaveType[] | null>(null);
  const [editing, setEditing] = useState<LeaveType | "new" | null>(null);
  const load = useCallback(() => { api.get<{ data: LeaveType[] }>("/erp/hr/leave-types").then((r) => setTypes(r.data)).catch(() => setTypes([])); }, []);
  useEffect(load, [load]);
  const manage = can("hr.manage");

  return (
    <>
      {manage && <Toolbar><button className="btn btn-secondary" onClick={() => setEditing("new")}><Icon name="ph-plus" size={16} /> {t("hrNewLeaveType")}</button></Toolbar>}
      {!types ? <LoadingBlock /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpName")}</th><th className="num">{t("hrDaysPerYear")}</th><th>{t("hrPaid")}</th><th>{t("hrAccrual")}</th><th>{t("hrCounting")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {types.map((x) => (
                <tr key={x.id} className={manage ? "is-clickable" : undefined} onClick={manage ? () => setEditing(x) : undefined}>
                  <td>{x.name}<span className="erp-cell-sub">{x.code}</span></td>
                  <td className="num">{x.days_per_year === null ? t("hrUnlimited") : n(x.days_per_year)}</td>
                  <td>{x.paid ? t("hrYes") : t("hrNo")}</td>
                  <td>{x.accrues_monthly ? t("hrMonthly") : t("hrUpfront")}</td>
                  <td>{x.counting === "calendar" ? t("hrCalendarDays") : t("hrWorkingDays")}</td>
                  <td><HrStatus status={x.is_active ? "active" : "cancelled"} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <FormDialog open={!!editing} title={editing === "new" ? t("hrNewLeaveType") : (editing as LeaveType | null)?.name ?? ""} onClose={() => setEditing(null)}
        initial={editing && editing !== "new" ? { code: editing.code, name: editing.name, days_per_year: editing.days_per_year ?? "", paid: editing.paid, accrues_monthly: editing.accrues_monthly, counting: editing.counting, is_active: editing.is_active } : { paid: true, accrues_monthly: false, counting: "working", is_active: true }}
        fields={[
          { name: "code", label: t("erpCode"), required: true },
          { name: "name", label: t("erpName"), required: true },
          { name: "days_per_year", label: t("hrDaysPerYear"), type: "number", hint: t("hrBlankUnlimited") },
          { name: "counting", label: t("hrCounting"), type: "select", options: [{ value: "working", label: t("hrWorkingDays") }, { value: "calendar", label: t("hrCalendarDays") }] },
          { name: "paid", label: t("hrPaid"), type: "checkbox" },
          { name: "accrues_monthly", label: t("hrAccruesMonthly"), type: "checkbox" },
          { name: "is_active", label: t("erpActive"), type: "checkbox" },
        ]}
        onSubmit={async (v) => {
          const body = payload(v, ["days_per_year"]);
          if (editing === "new") await api.post("/erp/hr/leave-types", body); else if (editing) await api.put(`/erp/hr/leave-types/${editing.id}`, body);
          setEditing(null); load();
        }} />
    </>
  );
}
