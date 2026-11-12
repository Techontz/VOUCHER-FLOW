"use client";

import Link from "next/link";
import { type ReactNode, useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type AttendanceRecord, currentPeriod, type LeaveBalance, type LeaveRequest, type LeaveType, monthLabel, n, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Tabs, Toolbar } from "@/components/app-ui";
import { BalanceTable, FormDialog, HrGate, HrStatus, payload, Tzs } from "@/components/hr-ui";

interface Me {
  id: number; employee_number: string; full_name: string; email: string | null; phone: string | null; job_title: string | null; grade: string | null;
  department: string | null; manager: string | null; hire_date: string; employment_type: string; status: string; national_id: string | null; tin: string | null;
  nssf_number: string | null; bank_name: string | null; bank_account_number: string | null; address: string | null;
  next_of_kin_name: string | null; next_of_kin_phone: string | null; next_of_kin_relation: string | null;
  shift: { name: string; start_time: string; end_time: string } | null;
  contract: { type: string; start_date: string; end_date: string | null; basic_salary: number; housing_allowance: number; transport_allowance: number; other_allowance: number } | null;
  leave_balances: LeaveBalance[];
}
interface MySlip { id: number; gross: string; total_deductions: string; net: string; run?: { number: string; period: string; status: string; payment_date: string | null } }
interface MyAppraisal { id: number; status: string; overall_rating: string | null; employee_comments: string | null; reviewer_comments: string | null; period?: { name: string }; reviewer?: { name: string } | null; objectives: { id: number; title: string; target: string | null; weight: number; rating: number | null }[] }
type Tab = "overview" | "leave" | "payslips" | "attendance" | "appraisals";

export default function MyHrPage() {
  return <HrGate anyOf={["hr.self"]}><MyHr /></HrGate>;
}

function MyHr() {
  const { t, locale } = useApp();
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [editing, setEditing] = useState(false);

  const load = useCallback(() => { api.get<{ data: Me }>("/erp/hr/me").then((r) => setMe(r.data)).catch((e) => setError(e)); }, []);
  useEffect(load, [load]);

  if (error) return error.status === 404 ? <EmptyState icon="ph-identification-badge" title={t("hrNoRecordTitle")} body={error.message} /> : <ErrorState message={error.message} />;
  if (!me) return <LoadingBlock rows={5} />;

  const kv = (label: string, value: ReactNode) => <Field label={label}><div>{value || "-"}</div></Field>;

  return (
    <div className="erp-page">
      <PageHeader kicker={me.employee_number} title={t("hrMyHr")} subtitle={`${me.full_name} · ${me.job_title ?? "-"} · ${me.department ?? "-"}`}
        actions={<button className="btn btn-primary" onClick={() => setTab("leave")}><Icon name="ph-airplane-tilt" size={18} /> {t("hrRequestLeave")}</button>} />
      <Tabs label={t("hrMyHr")} value={tab} onChange={setTab} items={[
        { value: "overview", label: t("hrProfile") }, { value: "leave", label: t("hrLeave") }, { value: "payslips", label: t("hrPayslips") },
        { value: "attendance", label: t("hrAttendance") }, { value: "appraisals", label: t("hrAppraisals") },
      ]} />

      {tab === "overview" && (
        <div className="erp-grid">
          <GlassCard className="erp-span-2" title={t("hrEmployment")}>
            <div className="erp-form-grid">
              {kv(t("hrEmployeeNumber"), me.employee_number)}{kv(t("hrHireDate"), formatDate(me.hire_date, locale))}
              {kv(t("hrManager"), me.manager)}{kv(t("hrGrade"), me.grade)}
              {kv(t("hrShift"), me.shift ? `${me.shift.name} ${me.shift.start_time.slice(0, 5)}-${me.shift.end_time.slice(0, 5)}` : null)}
              {kv(t("hrNationalId"), me.national_id)}{kv(t("erpTin"), me.tin)}{kv(t("hrNssfNumber"), me.nssf_number)}
            </div>
          </GlassCard>
          <GlassCard title={t("hrPay")}>
            {me.contract ? (
              <div className="erp-form-grid">
                {kv(t("hrBasic"), <Tzs value={me.contract.basic_salary} />)}
                {kv(t("hrAllowances"), <Tzs value={me.contract.housing_allowance + me.contract.transport_allowance + me.contract.other_allowance} />)}
                {kv(t("hrBank"), `${me.bank_name ?? "-"} ${me.bank_account_number ?? ""}`)}
                {kv(t("hrContractEnd"), formatDate(me.contract.end_date, locale))}
              </div>
            ) : <EmptyState icon="ph-file-text" title={t("hrNoContract")} />}
          </GlassCard>
          <GlassCard className="erp-span-2" title={t("hrContactDetails")} action={<button className="btn btn-secondary btn-sm" onClick={() => setEditing(true)}>{t("erpEdit")}</button>}>
            <div className="erp-form-grid">
              {kv(t("erpPhone"), me.phone)}{kv(t("erpAddress"), me.address)}
              {kv(t("hrNextOfKin"), me.next_of_kin_name)}{kv(t("hrNextOfKinPhone"), me.next_of_kin_phone)}{kv(t("hrRelation"), me.next_of_kin_relation)}
            </div>
          </GlassCard>
          <GlassCard title={t("hrBalances")} pad={false}><BalanceTable balances={me.leave_balances} /></GlassCard>
        </div>
      )}

      {tab === "leave" && <MyLeave onChange={load} />}
      {tab === "payslips" && <MyPayslips />}
      {tab === "attendance" && <MyAttendance />}
      {tab === "appraisals" && <MyAppraisals />}

      <FormDialog open={editing} title={t("hrContactDetails")} onClose={() => setEditing(false)}
        initial={{ phone: me.phone ?? "", address: me.address ?? "", next_of_kin_name: me.next_of_kin_name ?? "", next_of_kin_phone: me.next_of_kin_phone ?? "", next_of_kin_relation: me.next_of_kin_relation ?? "" }}
        fields={[
          { name: "phone", label: t("erpPhone") }, { name: "address", label: t("erpAddress") },
          { name: "next_of_kin_name", label: t("hrNextOfKin") }, { name: "next_of_kin_phone", label: t("hrNextOfKinPhone") }, { name: "next_of_kin_relation", label: t("hrRelation") },
        ]}
        onSubmit={async (v) => { await api.put("/erp/hr/me", payload(v)); setEditing(false); load(); }} />
    </div>
  );
}

function MyLeave({ onChange }: { onChange: () => void }) {
  const { t, locale, toast } = useApp();
  const [data, setData] = useState<{ data: LeaveRequest[]; balances: LeaveBalance[] } | null>(null);
  const [types, setTypes] = useState<LeaveType[]>([]);
  const [requesting, setRequesting] = useState(false);

  const load = useCallback(() => { api.get<NonNullable<typeof data>>("/erp/hr/me/leave").then(setData).catch(() => undefined); }, []);
  useEffect(load, [load]);
  useEffect(() => { api.get<{ data: LeaveType[] }>("/erp/hr/leave-types").then((r) => setTypes(r.data.filter((x) => x.is_active))).catch(() => undefined); }, []);

  async function cancel(r: LeaveRequest) {
    try { const res = await api.post<{ message: string }>(`/erp/hr/me/leave/${r.id}/cancel`); toast(res.message, undefined, "ok"); load(); onChange(); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }

  if (!data) return <LoadingBlock />;
  const available = (id: number) => data.balances.find((b) => b.leave_type_id === id)?.available;

  return (
    <div className="erp-grid">
      <GlassCard className="erp-span-2" title={t("hrMyRequests")} action={<button className="btn btn-primary btn-sm" onClick={() => setRequesting(true)}><Icon name="ph-plus" size={15} /> {t("hrRequestLeave")}</button>}>
        {data.data.length === 0 ? <EmptyState icon="ph-airplane-tilt" title={t("hrNoLeave")} /> : (
          <div className="erp-list">
            {data.data.map((r) => (
              <div key={r.id} className="erp-list-row">
                <span className="erp-list-main"><span className="erp-list-title">{r.leave_type?.name} · {n(r.days)} {t("hrDays")}</span>
                  <span className="erp-list-sub">{formatDate(r.start_date, locale)} - {formatDate(r.end_date, locale)}{r.decision_note ? ` · ${r.decider?.name}: ${r.decision_note}` : ""}</span></span>
                <HrStatus status={r.status} />
                {(r.status === "pending" || (r.status === "approved" && r.start_date.slice(0, 10) > today())) && <button className="btn btn-secondary btn-sm" onClick={() => cancel(r)}>{t("erpCancel")}</button>}
              </div>
            ))}
          </div>
        )}
      </GlassCard>
      <GlassCard title={t("hrBalances")} pad={false}><BalanceTable balances={data.balances} /></GlassCard>

      <FormDialog open={requesting} title={t("hrRequestLeave")} onClose={() => setRequesting(false)} initial={{ start_date: today(), end_date: today() }}
        intro={<p className="erp-muted">{t("hrRequestLeaveHint")}</p>}
        fields={[
          { name: "leave_type_id", label: t("hrLeaveType"), type: "select", required: true, options: types.map((x) => ({ value: x.id, label: `${x.name}${available(x.id) !== undefined && available(x.id) !== null ? ` (${available(x.id)} ${t("hrAvailable").toLowerCase()})` : ""}` })) },
          { name: "start_date", label: t("hrStart"), type: "date", required: true },
          { name: "end_date", label: t("hrEnd"), type: "date", required: true },
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { const r = await api.post<{ message: string }>("/erp/hr/me/leave", payload(v, ["leave_type_id"])); toast(r.message, undefined, "ok"); setRequesting(false); load(); onChange(); }} />
    </div>
  );
}

function MyPayslips() {
  const { t, locale } = useApp();
  const [rows, setRows] = useState<MySlip[] | null>(null);
  useEffect(() => { api.get<{ data: MySlip[] }>("/erp/hr/me/payslips").then((r) => setRows(r.data)).catch(() => setRows([])); }, []);
  if (!rows) return <LoadingBlock />;
  if (rows.length === 0) return <EmptyState icon="ph-money" title={t("hrNoPayslips")} />;
  return (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead><tr><th>{t("hrPeriod")}</th><th className="num">{t("hrGross")}</th><th className="num">{t("hrDeductions")}</th><th className="num">{t("hrNet")}</th><th>{t("hrPaymentDate")}</th></tr></thead>
        <tbody>
          {rows.map((p) => (
            <tr key={p.id}>
              <td><Link className="erp-cell-link" href={`/erp/hr/me/payslips/${p.id}`}><span className="erp-cell-title">{p.run ? monthLabel(p.run.period, locale) : "-"}</span><span className="erp-cell-sub tnum">{p.run?.number}</span></Link></td>
              <td className="num"><Tzs value={p.gross} /></td><td className="num"><Tzs value={p.total_deductions} /></td><td className="num"><strong><Tzs value={p.net} /></strong></td>
              <td>{p.run?.payment_date ? formatDate(p.run.payment_date, locale) : p.run && <HrStatus status={p.run.status} />}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function MyAttendance() {
  const { t, locale } = useApp();
  const [month, setMonth] = useState(currentPeriod());
  const [rows, setRows] = useState<AttendanceRecord[] | null>(null);
  useEffect(() => { api.get<{ data: AttendanceRecord[] }>("/erp/hr/me/attendance", { month }).then((r) => setRows(r.data)).catch(() => setRows([])); }, [month]);
  return (
    <>
      <Toolbar><Field label={t("hrMonth")} htmlFor="my-month"><input id="my-month" className="input" type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></Field></Toolbar>
      {!rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-fingerprint" title={t("hrNoAttendance")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpDate")}</th><th>{t("hrCheckIn")}</th><th>{t("hrCheckOut")}</th><th className="num">{t("hrHours")}</th><th className="num">{t("hrOvertime")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>{rows.map((a) => (
              <tr key={a.id}><td className="tnum">{formatDate(a.date, locale)}</td><td className="tnum">{a.check_in?.slice(0, 5) ?? "-"}</td><td className="tnum">{a.check_out?.slice(0, 5) ?? "-"}</td>
                <td className="num">{n(a.hours_worked)}</td><td className="num">{n(a.overtime_hours)}</td><td><HrStatus status={a.status} /></td></tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </>
  );
}

function MyAppraisals() {
  const { t, toast } = useApp();
  const [rows, setRows] = useState<MyAppraisal[] | null>(null);
  const [commenting, setCommenting] = useState<MyAppraisal | null>(null);
  const load = useCallback(() => { api.get<{ data: MyAppraisal[] }>("/erp/hr/me/appraisals").then((r) => setRows(r.data)).catch(() => setRows([])); }, []);
  useEffect(load, [load]);
  if (!rows) return <LoadingBlock />;
  if (rows.length === 0) return <EmptyState icon="ph-target" title={t("hrNoAppraisals")} />;
  return (
    <div className="erp-cards">
      {rows.map((a) => (
        <GlassCard key={a.id} title={a.period?.name} subtitle={a.reviewer?.name}
          action={<HrStatus status={a.status} />}>
          <ul className="erp-list">{a.objectives.map((o) => <li key={o.id} className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{o.title}</span><span className="erp-list-sub">{o.target ?? "-"} · {t("hrWeight")} {o.weight}</span></span><span className="tnum">{o.rating ? `${o.rating}/5` : "-"}</span></li>)}</ul>
          {a.overall_rating && <p><strong>{t("hrRating")}: {n(a.overall_rating)} / 5</strong></p>}
          {a.reviewer_comments && <p className="erp-muted">{a.reviewer_comments}</p>}
          {a.employee_comments && <p>{t("hrMyComments")}: {a.employee_comments}</p>}
          {a.status !== "completed" && <button className="btn btn-secondary btn-sm" onClick={() => setCommenting(a)}>{t("hrAddComments")}</button>}
        </GlassCard>
      ))}
      <FormDialog open={!!commenting} title={t("hrAddComments")} onClose={() => setCommenting(null)} initial={{ employee_comments: commenting?.employee_comments ?? "" }}
        fields={[{ name: "employee_comments", label: t("hrMyComments"), type: "textarea", required: true, wide: true }]}
        onSubmit={async (v) => { await api.put(`/erp/hr/me/appraisals/${commenting?.id}`, v); toast(t("erpSaved"), undefined, "ok"); setCommenting(null); load(); }} />
    </div>
  );
}
