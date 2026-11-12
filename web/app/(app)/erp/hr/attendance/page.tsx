"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { type AttendanceRecord, currentPeriod, n, type Shift, today } from "@/lib/hr";
import { EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Tabs, Toolbar } from "@/components/app-ui";
import { fill } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload } from "@/components/hr-ui";

interface DayRow { employee: { id: number; full_name: string; employee_number: string; department: string | null; shift: string | null }; record: AttendanceRecord | null; on_leave: string | null }
interface SumRow { employee: { id: number; full_name: string; employee_number: string; department: string | null }; present: number; late: number; absent: number; leave: number; off: number; hours: number; overtime: number }
type Tab = "daily" | "summary" | "shifts";

export default function AttendancePage() {
  return <HrGate anyOf={["hr.view", "hr.leave.approve"]}><Attendance /></HrGate>;
}

function Attendance() {
  const { t, toast } = useApp();
  const { can } = useErp();
  // HR reads everyone; a department head reads the team routes, scoped to their people.
  const base = can("hr.view") ? "/erp/hr/attendance" : "/erp/hr/team/attendance";
  const [tab, setTab] = useState<Tab>("daily");
  const [date, setDate] = useState(today());
  const [period, setPeriod] = useState(currentPeriod());
  const [day, setDay] = useState<DayRow[] | null>(null);
  const [summary, setSummary] = useState<SumRow[] | null>(null);
  const [shifts, setShifts] = useState<Shift[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [recording, setRecording] = useState<DayRow | null>(null);
  const [importing, setImporting] = useState(false);
  const [importErrors, setImportErrors] = useState<{ line: number; message: string }[]>([]);
  const [shiftEdit, setShiftEdit] = useState<Shift | "new" | null>(null);
  const record = can("hr.attendance");

  const load = useCallback(() => {
    if (tab === "daily") api.get<{ data: DayRow[] }>(base, { date }).then((r) => setDay(r.data)).catch((e) => setError(e.message));
    if (tab === "summary") api.get<{ data: SumRow[] }>(`${base}/summary`, { period }).then((r) => setSummary(r.data)).catch((e) => setError(e.message));
    if (tab === "shifts") api.get<{ data: Shift[] }>("/erp/hr/shifts").then((r) => setShifts(r.data)).catch((e) => setError(e.message));
  }, [tab, base, date, period]);
  useEffect(load, [load]);

  const counts = (day ?? []).reduce<Record<string, number>>((acc, r) => {
    const s = r.on_leave ? "leave" : r.record?.status ?? "none";
    acc[s] = (acc[s] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <div className="erp-page">
      <PageHeader title={t("hrAttendance")} subtitle={t("hrAttendanceSub")}
        actions={record && <button className="btn btn-primary" onClick={() => { setImportErrors([]); setImporting(true); }}><Icon name="ph-upload-simple" size={18} /> {t("hrImportCsv")}</button>} />

      <Tabs label={t("hrAttendance")} value={tab} onChange={setTab} items={[
        { value: "daily", label: t("hrDaily") }, { value: "summary", label: t("hrMonthlySummary") },
        ...(can("hr.view") ? [{ value: "shifts" as Tab, label: t("hrShifts") }] : []),
      ]} />

      {importErrors.length > 0 && (
        <div className="vf-alert tone-warn" role="alert">
          <div className="vf-alert-text"><div className="vf-alert-title">{t("hrImportSkipped")}</div>
            <ul>{importErrors.map((e) => <li key={e.line}>{fill(t("hrLineN"), { n: e.line })}: {e.message}</li>)}</ul></div>
        </div>
      )}

      {error && <ErrorState message={error} onRetry={load} />}

      {tab === "daily" && (
        <>
          <Toolbar>
            <Field label={t("erpDate")} htmlFor="att-date"><input id="att-date" className="input" type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} /></Field>
            <span className="erp-muted">{t("hrStPresent")} {counts.present ?? 0} · {t("hrStLate")} {counts.late ?? 0} · {t("hrStAbsent")} {counts.absent ?? 0} · {t("hrStLeave")} {counts.leave ?? 0} · {t("hrNotRecorded")} {counts.none ?? 0}</span>
          </Toolbar>
          {!day ? <LoadingBlock /> : day.length === 0 ? <EmptyState icon="ph-fingerprint" title={t("hrNoEmployees")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("hrEmployee")}</th><th>{t("hrShift")}</th><th>{t("hrCheckIn")}</th><th>{t("hrCheckOut")}</th><th className="num">{t("hrOvertime")}</th><th>{t("erpStatus")}</th>{record && <th />}</tr></thead>
                <tbody>
                  {day.map((r) => (
                    <tr key={r.employee.id}>
                      <td><Link className="erp-cell-link" href={`/erp/hr/employees/${r.employee.id}`}><span className="erp-cell-title">{r.employee.full_name}</span><span className="erp-cell-sub tnum">{r.employee.employee_number}{r.employee.department ? ` · ${r.employee.department}` : ""}</span></Link></td>
                      <td>{r.employee.shift ?? "-"}</td>
                      <td className="tnum">{r.record?.check_in?.slice(0, 5) ?? "-"}</td>
                      <td className="tnum">{r.record?.check_out?.slice(0, 5) ?? "-"}</td>
                      <td className="num">{r.record ? n(r.record.overtime_hours) : "-"}</td>
                      <td>{r.on_leave ? <HrStatus status="leave" /> : r.record ? <HrStatus status={r.record.status} /> : <span className="erp-muted">{t("hrNotRecorded")}</span>}</td>
                      {record && <td><button className="btn btn-secondary btn-sm" onClick={() => setRecording(r)}>{t("hrRecord")}</button></td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {tab === "summary" && (
        <>
          <Toolbar><Field label={t("hrPeriod")} htmlFor="att-period"><input id="att-period" className="input" type="month" value={period} onChange={(e) => setPeriod(e.target.value)} /></Field></Toolbar>
          {!summary ? <LoadingBlock /> : summary.length === 0 ? <EmptyState icon="ph-calendar" title={t("hrNoAttendance")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("hrEmployee")}</th><th className="num">{t("hrStPresent")}</th><th className="num">{t("hrStLate")}</th><th className="num">{t("hrStAbsent")}</th><th className="num">{t("hrStLeave")}</th><th className="num">{t("hrHours")}</th><th className="num">{t("hrOvertime")}</th></tr></thead>
                <tbody>
                  {summary.map((r) => (
                    <tr key={r.employee.id}>
                      <td><span className="erp-cell-title">{r.employee.full_name}</span><span className="erp-cell-sub tnum">{r.employee.employee_number}</span></td>
                      <td className="num">{r.present}</td><td className="num">{r.late}</td><td className="num">{r.absent}</td><td className="num">{r.leave}</td>
                      <td className="num">{n(r.hours)}</td><td className="num">{n(r.overtime)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p className="erp-muted">{t("hrSummaryFeedsPayroll")}</p>
        </>
      )}

      {tab === "shifts" && (
        <>
          {record && <Toolbar><button className="btn btn-secondary" onClick={() => setShiftEdit("new")}><Icon name="ph-plus" size={16} /> {t("hrNewShift")}</button></Toolbar>}
          {!shifts ? <LoadingBlock /> : shifts.length === 0 ? <EmptyState icon="ph-clock" title={t("hrNoShifts")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpName")}</th><th>{t("hrStart")}</th><th>{t("hrEnd")}</th><th className="num">{t("hrGrace")}</th><th className="num">{t("hrHours")}</th><th /></tr></thead>
                <tbody>
                  {shifts.map((s) => (
                    <tr key={s.id} className={record ? "is-clickable" : undefined} onClick={record ? () => setShiftEdit(s) : undefined}>
                      <td>{s.name}{s.is_default && <span className="erp-cell-sub">{t("hrDefaultShift")}</span>}</td>
                      <td className="tnum">{s.start_time.slice(0, 5)}</td><td className="tnum">{s.end_time.slice(0, 5)}</td>
                      <td className="num">{s.grace_minutes}</td><td className="num">{s.hours}</td><td />
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      <FormDialog open={!!recording} title={`${t("hrRecord")} · ${recording?.employee.full_name ?? ""}`} onClose={() => setRecording(null)}
        initial={{ date, check_in: recording?.record?.check_in?.slice(0, 5) ?? "", check_out: recording?.record?.check_out?.slice(0, 5) ?? "", status: "", note: recording?.record?.note ?? "" }}
        fields={[
          { name: "date", label: t("erpDate"), type: "date", required: true },
          { name: "check_in", label: t("hrCheckIn"), type: "time" },
          { name: "check_out", label: t("hrCheckOut"), type: "time" },
          { name: "status", label: t("erpStatus"), type: "select", hint: t("hrStatusAuto"), options: ["present", "late", "absent", "leave", "off"].map((s) => ({ value: s, label: s })) },
          { name: "note", label: t("hrNotes"), wide: true },
        ]}
        onSubmit={async (v) => {
          await api.post("/erp/hr/attendance", { ...payload(v), employee_id: recording?.employee.id });
          toast(t("erpSaved"), undefined, "ok"); setRecording(null); load();
        }} />

      <FormDialog open={importing} title={t("hrImportCsv")} onClose={() => setImporting(false)} submitLabel={t("hrImport")}
        intro={<p className="erp-muted">{t("hrImportHint")} <code>employee_number, date, time_in, time_out</code></p>}
        fields={[{ name: "file", label: t("hrCsvFile"), type: "file", required: true, wide: true }]}
        onSubmit={async (v) => {
          const form = new FormData();
          if (v.file instanceof File) form.append("file", v.file);
          const r = await api.upload<{ message: string; data: { imported: number; errors: { line: number; message: string }[] } }>("/erp/hr/attendance/import", form);
          toast(r.message, undefined, r.data.errors.length ? "warn" : "ok");
          setImportErrors(r.data.errors); setImporting(false); load();
        }} />

      <FormDialog open={!!shiftEdit} title={shiftEdit === "new" ? t("hrNewShift") : (shiftEdit as Shift | null)?.name ?? ""} onClose={() => setShiftEdit(null)}
        initial={shiftEdit && shiftEdit !== "new" ? { name: shiftEdit.name, start_time: shiftEdit.start_time.slice(0, 5), end_time: shiftEdit.end_time.slice(0, 5), grace_minutes: String(shiftEdit.grace_minutes), is_default: shiftEdit.is_default } : { start_time: "08:00", end_time: "17:00", grace_minutes: "10", is_default: false }}
        fields={[
          { name: "name", label: t("erpName"), required: true },
          { name: "start_time", label: t("hrStart"), type: "time", required: true },
          { name: "end_time", label: t("hrEnd"), type: "time", required: true },
          { name: "grace_minutes", label: t("hrGrace"), type: "number" },
          { name: "is_default", label: t("hrDefaultShift"), type: "checkbox" },
        ]}
        onSubmit={async (v) => {
          const body = payload(v, ["grace_minutes"]);
          if (shiftEdit === "new") await api.post("/erp/hr/shifts", body); else if (shiftEdit) await api.put(`/erp/hr/shifts/${shiftEdit.id}`, body);
          setShiftEdit(null); load();
        }} />
    </div>
  );
}
