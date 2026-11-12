"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { type AttendanceRecord, type HrContract, type HrEmployee, type LeaveBalance, type LeaveRequest, monthLabel, n, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { BalanceTable, type FieldSpec, FormDialog, HrGate, HrStatus, payload, Tzs, useLookups } from "@/components/hr-ui";
import { CONTRACT_KEY, CONTRACT_TYPES, MOVEMENT_KEY, MOVEMENT_TYPES, useEmploymentTypes } from "@/components/hr-employee-fields";

interface Movement { id: number; type: keyof typeof MOVEMENT_KEY; effective_date: string; from_job_title: string | null; to_job_title: string | null; from_grade: string | null; to_grade: string | null; reason: string | null; from_department?: { name: string } | null; to_department?: { name: string } | null; creator?: { name: string } | null }
interface Task { id: number; title: string; done_at: string | null; doer?: { name: string } | null }
interface Detail {
  data: HrEmployee; contracts: HrContract[]; movements: Movement[]; onboarding: Task[]; leave_balances: LeaveBalance[];
  leave_requests: LeaveRequest[]; attendance: AttendanceRecord[];
  trainings: { id: number; title: string; provider: string | null; start_date: string; status: string }[];
  appraisals: { id: number; status: string; overall_rating: string | null; period?: { name: string } }[];
  exit: { id: number; type: string; status: string; last_working_day: string } | null;
  payslips: { id: number; gross: string; net: string; total_deductions: string; run?: { number: string; period: string; status: string } }[] | null;
  discipline: { id: number; number: string; category: string; incident_date: string; action: string | null; status: string }[] | null;
}
type Tab = "profile" | "contracts" | "history" | "leave" | "attendance" | "onboarding" | "development" | "payslips" | "discipline";

export default function EmployeePage() {
  return <HrGate anyOf={["hr.view"]}><Employee /></HrGate>;
}

function Employee() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const { id } = useParams<{ id: string }>();
  const lookups = useLookups();
  const types = useEmploymentTypes();
  const [d, setD] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("profile");
  const [dialog, setDialog] = useState<"edit" | "contract" | "move" | "task" | null>(null);

  const load = useCallback(() => { api.get<Detail>(`/erp/hr/employees/${id}`).then(setD).catch((e) => setError(e.message)); }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!d) return <LoadingBlock rows={6} />;

  const e = d.data;
  const manage = can("hr.manage") && e.status !== "exited";
  const kv = (label: string, value: ReactNode) => <Field label={label}><div>{value || "-"}</div></Field>;

  async function setStatus(status: "active" | "suspended") {
    try { await api.put(`/erp/hr/employees/${e.id}`, { status }); toast(t("erpSaved"), undefined, "ok"); load(); }
    catch (err) { toast(t("hrActionFailed"), (err as Error).message, "bad"); }
  }

  async function toggleTask(task: Task) {
    try { await api.put(`/erp/hr/onboarding/${task.id}`, { done: !task.done_at }); load(); }
    catch (err) { toast(t("hrActionFailed"), (err as Error).message, "bad"); }
  }

  const tabs: { value: Tab; label: string; count?: number | null }[] = [
    { value: "profile", label: t("hrProfile") },
    { value: "contracts", label: t("hrContracts"), count: d.contracts.length },
    { value: "history", label: t("hrHistory"), count: d.movements.length },
    { value: "leave", label: t("hrLeave") },
    { value: "attendance", label: t("hrAttendance") },
    { value: "onboarding", label: t("hrOnboarding"), count: d.onboarding.filter((x) => !x.done_at).length || null },
    { value: "development", label: t("hrDevelopment") },
    ...(d.payslips ? [{ value: "payslips" as Tab, label: t("hrPayslips") }] : []),
    ...(d.discipline ? [{ value: "discipline" as Tab, label: t("hrDiscipline"), count: d.discipline.length || null }] : []),
  ];

  const editFields: FieldSpec[] = [
    { name: "full_name", label: t("hrFullName"), required: true },
    { name: "employment_type", label: t("hrEmploymentType"), type: "select", options: types },
    { name: "manager_id", label: t("hrManager"), type: "select", options: lookups.employees.filter((x) => x.id !== e.id).map((x) => ({ value: x.id, label: x.full_name })) },
    { name: "shift_id", label: t("hrShift"), type: "select", options: lookups.shifts.map((s) => ({ value: s.id, label: s.name })) },
    { name: "hire_date", label: t("hrHireDate"), type: "date" },
    { name: "probation_end", label: t("hrProbationEnd"), type: "date" },
    { name: "phone", label: t("erpPhone") },
    { name: "email", label: t("erpEmail"), type: "email" },
    { name: "gender", label: t("hrGender"), type: "select", options: [{ value: "female", label: t("hrFemale") }, { value: "male", label: t("hrMale") }] },
    { name: "date_of_birth", label: t("hrDateOfBirth"), type: "date" },
    { name: "national_id", label: t("hrNationalId") },
    { name: "tin", label: t("erpTin") },
    { name: "nssf_number", label: t("hrNssfNumber") },
    { name: "address", label: t("erpAddress") },
    { name: "next_of_kin_name", label: t("hrNextOfKin") },
    { name: "next_of_kin_phone", label: t("hrNextOfKinPhone") },
    { name: "next_of_kin_relation", label: t("hrRelation") },
    ...(e.salary_visible ? [{ name: "bank_name", label: t("hrBank") }, { name: "bank_account_number", label: t("hrBankAccount") }] : []),
    { name: "heslb_beneficiary", label: t("hrHeslbBeneficiary"), type: "checkbox" },
  ];
  const editInitial = Object.fromEntries(editFields.map((f) => {
    const v = (e as unknown as Record<string, unknown>)[f.name];
    return [f.name, typeof v === "boolean" ? v : v === null || v === undefined ? "" : String(v)];
  }));

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/hr/employees" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("hrEmployees")}</Link>}
        kicker={e.employee_number}
        title={e.full_name}
        subtitle={`${e.job_title ?? "-"} · ${e.department?.name ?? t("hrNoDepartment")}${e.grade ? ` · ${e.grade}` : ""}`}
        actions={<>
          <HrStatus status={e.status} />
          {manage && <button className="btn btn-secondary" onClick={() => setDialog("edit")}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {manage && <button className="btn btn-secondary" onClick={() => setDialog("move")}><Icon name="ph-arrows-left-right" size={17} /> {t("hrTransferPromote")}</button>}
          {manage && can("hr.salary") && <button className="btn btn-secondary" onClick={() => setDialog("contract")}><Icon name="ph-file-plus" size={17} /> {t("hrNewContract")}</button>}
          {manage && (e.status === "active"
            ? <button className="btn btn-secondary" onClick={() => setStatus("suspended")}>{t("hrSuspend")}</button>
            : <button className="btn btn-secondary" onClick={() => setStatus("active")}>{t("hrReactivate")}</button>)}
          {manage && !d.exit && <Link className="btn btn-secondary" href={`/erp/hr/exits?employee=${e.id}`}><Icon name="ph-sign-out" size={17} /> {t("hrStartExit")}</Link>}
        </>} />

      <Tabs label={t("hrProfile")} value={tab} onChange={setTab} items={tabs} />

      {tab === "profile" && (
        <div className="erp-grid">
          <GlassCard className="erp-span-2" title={t("hrEmployment")}>
            <div className="erp-form-grid">
              {kv(t("hrEmploymentType"), types.find((x) => x.value === e.employment_type)?.label)}
              {kv(t("hrHireDate"), formatDate(e.hire_date, locale))}
              {kv(t("hrProbationEnd"), formatDate(e.probation_end, locale))}
              {kv(t("hrManager"), e.manager?.full_name)}
              {kv(t("hrShift"), e.shift?.name)}
              {kv(t("hrLinkUser"), e.user ? `${e.user.name} · ${e.user.email}` : null)}
              {kv(t("hrHeslbBeneficiary"), e.heslb_beneficiary ? t("hrYes") : t("hrNo"))}
              {e.exit_date && kv(t("hrExitDate"), formatDate(e.exit_date, locale))}
            </div>
          </GlassCard>
          <GlassCard title={t("hrPay")}>
            {!e.salary_visible ? <EmptyState icon="ph-lock-simple" title={t("hrSalaryHidden")} /> : e.contract ? (
              <div className="erp-form-grid">
                {kv(t("hrBasic"), <Tzs value={e.contract.basic_salary} />)}
                {kv(t("hrAllowances"), <Tzs value={n(e.contract.housing_allowance) + n(e.contract.transport_allowance) + n(e.contract.other_allowance)} />)}
                {kv(t("hrGrossSalary"), <Tzs value={e.contract.gross_salary} />)}
                {kv(t("hrBank"), `${e.bank_name ?? "-"} ${e.bank_account_number ?? ""}`)}
              </div>
            ) : <EmptyState icon="ph-file-text" title={t("hrNoContract")} />}
          </GlassCard>
          <GlassCard className="erp-span-2" title={t("hrPersonal")}>
            <div className="erp-form-grid">
              {kv(t("erpPhone"), e.phone)}{kv(t("erpEmail"), e.email)}
              {kv(t("hrGender"), e.gender === "female" ? t("hrFemale") : e.gender === "male" ? t("hrMale") : null)}
              {kv(t("hrDateOfBirth"), formatDate(e.date_of_birth, locale))}
              {kv(t("hrNationalId"), e.national_id)}{kv(t("erpTin"), e.tin)}{kv(t("hrNssfNumber"), e.nssf_number)}
              {kv(t("erpAddress"), e.address)}
            </div>
          </GlassCard>
          <GlassCard title={t("hrNextOfKin")}>
            <div className="erp-form-grid">{kv(t("erpName"), e.next_of_kin_name)}{kv(t("erpPhone"), e.next_of_kin_phone)}{kv(t("hrRelation"), e.next_of_kin_relation)}</div>
          </GlassCard>
        </div>
      )}

      {tab === "contracts" && (d.contracts.length === 0 ? <EmptyState icon="ph-file-text" title={t("hrNoContract")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrContractType")}</th><th>{t("hrStart")}</th><th>{t("hrEnd")}</th>{e.salary_visible && <><th className="num">{t("hrBasic")}</th><th className="num">{t("hrAllowances")}</th></>}<th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {d.contracts.map((c) => (
                <tr key={c.id}>
                  <td>{CONTRACT_KEY[c.type as keyof typeof CONTRACT_KEY] ? t(CONTRACT_KEY[c.type as keyof typeof CONTRACT_KEY]) : c.type}{c.notes && <span className="erp-cell-sub">{c.notes}</span>}</td>
                  <td className="tnum">{formatDate(c.start_date, locale)}</td><td className="tnum">{formatDate(c.end_date, locale)}</td>
                  {e.salary_visible && <><td className="num"><Tzs value={c.basic_salary} /></td><td className="num"><Tzs value={n(c.housing_allowance) + n(c.transport_allowance) + n(c.other_allowance)} /></td></>}
                  <td><HrStatus status={c.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {tab === "history" && (d.movements.length === 0 ? <EmptyState icon="ph-clock-counter-clockwise" title={t("hrNoHistory")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpDate")}</th><th>{t("erpType")}</th><th>{t("hrFrom")}</th><th>{t("hrTo")}</th><th>{t("hrReason")}</th></tr></thead>
            <tbody>
              {d.movements.map((m) => (
                <tr key={m.id}>
                  <td className="tnum">{formatDate(m.effective_date, locale)}</td>
                  <td>{t(MOVEMENT_KEY[m.type])}</td>
                  <td>{m.from_job_title ?? "-"}<span className="erp-cell-sub">{m.from_department?.name}{m.from_grade ? ` · ${m.from_grade}` : ""}</span></td>
                  <td>{m.to_job_title ?? "-"}<span className="erp-cell-sub">{m.to_department?.name}{m.to_grade ? ` · ${m.to_grade}` : ""}</span></td>
                  <td>{m.reason ?? "-"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {tab === "leave" && (
        <div className="erp-grid">
          <GlassCard className="erp-span-2" title={t("hrBalances")} pad={false}>
            <BalanceTable balances={d.leave_balances} />
          </GlassCard>
          <GlassCard title={t("hrRecentRequests")}>
            {d.leave_requests.length === 0 ? <EmptyState icon="ph-airplane-tilt" title={t("hrNoLeave")} /> : (
              <div className="erp-list">
                {d.leave_requests.map((r) => (
                  <div key={r.id} className="erp-list-row">
                    <span className="erp-list-main"><span className="erp-list-title">{r.leave_type?.name} · {n(r.days)} {t("hrDays")}</span><span className="erp-list-sub">{formatDate(r.start_date, locale)} - {formatDate(r.end_date, locale)}</span></span>
                    <HrStatus status={r.status} />
                  </div>
                ))}
              </div>
            )}
          </GlassCard>
        </div>
      )}

      {tab === "attendance" && (d.attendance.length === 0 ? <EmptyState icon="ph-fingerprint" title={t("hrNoAttendance")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpDate")}</th><th>{t("hrCheckIn")}</th><th>{t("hrCheckOut")}</th><th className="num">{t("hrHours")}</th><th className="num">{t("hrOvertime")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {d.attendance.map((a) => (
                <tr key={a.id}><td className="tnum">{formatDate(a.date, locale)}</td><td className="tnum">{a.check_in?.slice(0, 5) ?? "-"}</td><td className="tnum">{a.check_out?.slice(0, 5) ?? "-"}</td>
                  <td className="num">{n(a.hours_worked)}</td><td className="num">{n(a.overtime_hours)}</td><td><HrStatus status={a.status} /></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {tab === "onboarding" && (
        <GlassCard title={t("hrOnboarding")} action={can("hr.recruit") && <button className="btn btn-secondary btn-sm" onClick={() => setDialog("task")}><Icon name="ph-plus" size={15} /> {t("hrAddTask")}</button>}>
          {d.onboarding.length === 0 ? <EmptyState icon="ph-list-checks" title={t("hrNoTasks")} /> : (
            <div className="erp-checks">
              {d.onboarding.map((task) => (
                <label key={task.id} className="erp-check">
                  <input type="checkbox" checked={!!task.done_at} disabled={!can("hr.recruit")} onChange={() => toggleTask(task)} />
                  <span><span className="erp-check-label">{task.title}</span>{task.done_at && <span className="erp-check-hint">{task.doer?.name} · {formatDate(task.done_at, locale)}</span>}</span>
                </label>
              ))}
            </div>
          )}
        </GlassCard>
      )}

      {tab === "development" && (
        <div className="erp-grid">
          <GlassCard title={t("hrAppraisals")}>
            {d.appraisals.length === 0 ? <EmptyState icon="ph-target" title={t("hrNoAppraisals")} /> : (
              <div className="erp-list">{d.appraisals.map((a) => (
                <Link key={a.id} className="erp-list-row" href={`/erp/hr/performance?appraisal=${a.id}`}>
                  <span className="erp-list-main"><span className="erp-list-title">{a.period?.name}</span><span className="erp-list-sub">{a.overall_rating ? `${t("hrRating")} ${n(a.overall_rating)} / 5` : "-"}</span></span>
                  <HrStatus status={a.status} />
                </Link>
              ))}</div>
            )}
          </GlassCard>
          <GlassCard title={t("hrTraining")}>
            {d.trainings.length === 0 ? <EmptyState icon="ph-graduation-cap" title={t("hrNoTraining")} /> : (
              <div className="erp-list">{d.trainings.map((tr) => (
                <div key={tr.id} className="erp-list-row">
                  <span className="erp-list-main"><span className="erp-list-title">{tr.title}</span><span className="erp-list-sub">{tr.provider ?? "-"} · {formatDate(tr.start_date, locale)}</span></span>
                  <HrStatus status={tr.status} />
                </div>
              ))}</div>
            )}
          </GlassCard>
          {d.exit && (
            <GlassCard title={t("hrExit")}>
              <Link className="erp-list-row" href="/erp/hr/exits"><span className="erp-list-main"><span className="erp-list-title">{d.exit.type.replace(/_/g, " ")}</span><span className="erp-list-sub">{t("hrLastDay")} {formatDate(d.exit.last_working_day, locale)}</span></span><HrStatus status={d.exit.status} /></Link>
            </GlassCard>
          )}
        </div>
      )}

      {tab === "payslips" && d.payslips && (d.payslips.length === 0 ? <EmptyState icon="ph-money" title={t("hrNoPayslips")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrPeriod")}</th><th className="num">{t("hrGross")}</th><th className="num">{t("hrDeductions")}</th><th className="num">{t("hrNet")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {d.payslips.map((p) => (
                <tr key={p.id}><td><Link className="erp-cell-link" href={`/erp/hr/payslips/${p.id}`}>{p.run ? monthLabel(p.run.period, locale) : "-"}<span className="erp-cell-sub tnum">{p.run?.number}</span></Link></td>
                  <td className="num"><Tzs value={p.gross} /></td><td className="num"><Tzs value={p.total_deductions} /></td><td className="num"><Tzs value={p.net} /></td>
                  <td>{p.run && <HrStatus status={p.run.status} />}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {tab === "discipline" && d.discipline && (d.discipline.length === 0 ? <EmptyState icon="ph-scales" title={t("hrNoCases")} /> : (
        <div className="erp-list">{d.discipline.map((c) => (
          <Link key={c.id} className="erp-list-row" href={`/erp/hr/discipline?case=${c.id}`}>
            <span className="erp-list-main"><span className="erp-list-title tnum">{c.number} · {c.category}</span><span className="erp-list-sub">{formatDate(c.incident_date, locale)} · {c.action?.replace(/_/g, " ") ?? "-"}</span></span>
            <HrStatus status={c.status} />
          </Link>
        ))}</div>
      ))}

      <FormDialog open={dialog === "edit"} title={`${t("erpEdit")} · ${e.full_name}`} fields={editFields} initial={editInitial} onClose={() => setDialog(null)}
        onSubmit={async (v) => { await api.put(`/erp/hr/employees/${e.id}`, payload(v, ["manager_id", "shift_id"])); toast(t("erpSaved"), undefined, "ok"); setDialog(null); load(); }} />

      <FormDialog open={dialog === "contract"} title={t("hrNewContract")} intro={<p className="erp-muted">{t("hrNewContractHint")}</p>} onClose={() => setDialog(null)}
        initial={{ type: e.contract?.type ?? "permanent", start_date: today(), basic_salary: String(e.contract?.basic_salary ?? ""), housing_allowance: String(e.contract?.housing_allowance ?? 0), transport_allowance: String(e.contract?.transport_allowance ?? 0), other_allowance: String(e.contract?.other_allowance ?? 0) }}
        fields={[
          { name: "type", label: t("hrContractType"), type: "select", required: true, options: CONTRACT_TYPES.map((c) => ({ value: c, label: t(CONTRACT_KEY[c]) })) },
          { name: "start_date", label: t("hrStart"), type: "date", required: true },
          { name: "end_date", label: t("hrEnd"), type: "date" },
          { name: "basic_salary", label: t("hrBasic"), type: "number", required: true },
          { name: "housing_allowance", label: t("hrHousing"), type: "number" },
          { name: "transport_allowance", label: t("hrTransport"), type: "number" },
          { name: "other_allowance", label: t("hrOtherAllowance"), type: "number" },
          { name: "notes", label: t("hrNotes"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { await api.post(`/erp/hr/employees/${e.id}/contracts`, payload(v, ["basic_salary", "housing_allowance", "transport_allowance", "other_allowance"])); toast(t("erpSaved"), undefined, "ok"); setDialog(null); load(); }} />

      <FormDialog open={dialog === "move"} title={t("hrTransferPromote")} onClose={() => setDialog(null)}
        initial={{ type: "transfer", effective_date: today(), to_department_id: String(e.department_id ?? ""), to_job_title: e.job_title ?? "", to_grade: e.grade ?? "" }}
        fields={[
          { name: "type", label: t("erpType"), type: "select", required: true, options: MOVEMENT_TYPES.map((m) => ({ value: m, label: t(MOVEMENT_KEY[m]) })) },
          { name: "effective_date", label: t("hrEffectiveDate"), type: "date", required: true },
          { name: "to_department_id", label: t("hrDepartment"), type: "select", options: lookups.departments.map((x) => ({ value: x.id, label: x.name })) },
          { name: "to_job_title", label: t("hrJobTitle") },
          { name: "to_grade", label: t("hrGrade") },
          { name: "reason", label: t("hrReason"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { await api.post(`/erp/hr/employees/${e.id}/movements`, payload(v, ["to_department_id"])); toast(t("erpSaved"), undefined, "ok"); setDialog(null); load(); }} />

      <FormDialog open={dialog === "task"} title={t("hrAddTask")} onClose={() => setDialog(null)} fields={[{ name: "title", label: t("hrTask"), required: true, wide: true }]}
        onSubmit={async (v) => { await api.post(`/erp/hr/employees/${e.id}/onboarding`, v); setDialog(null); load(); }} />
    </div>
  );
}
