"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { monthLabel } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { HrGate, HrStatus, Tzs } from "@/components/hr-ui";

interface RunSummary { id: number; number: string; period: string; status: string; employees_count: number; net: number | null; gross: number | null }
interface Overview {
  headcount: number; suspended: number;
  by_department: { department_id: number | null; department: string | null; headcount: number }[];
  on_leave_today: { id: number; employee: string; employee_id: number; leave_type: string; end_date: string }[];
  pending_leave: number;
  attendance_today: { present: number; late: number; absent: number; leave: number };
  payroll: { current_period: string; current: RunSummary | null; latest: RunSummary | null };
  contracts_expiring: { contract_id: number; employee_id: number; employee: string; type: string; end_date: string }[];
  probation_ending: { employee_id: number; employee: string; probation_end: string }[];
  open_vacancies: number; applicants_in_pipeline: number; exits_in_progress: number; open_discipline_cases: number | null;
}

export default function HrOverviewPage() {
  return <HrGate anyOf={["hr.view"]}><HrOverview /></HrGate>;
}

function HrOverview() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { api.get<{ data: Overview }>("/erp/hr/overview").then((r) => setData(r.data)).catch((e) => setError(e.message)); }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const max = Math.max(1, ...data.by_department.map((d) => d.headcount));
  const current = data.payroll.current;

  return (
    <div className="erp-page">
      <PageHeader title={t("hrOverview")} subtitle={t("hrOverviewSub")}
        actions={<>
          {can("hr.manage") && <Link className="btn btn-primary" href="/erp/hr/employees?new=1"><Icon name="ph-user-plus" size={18} /> {t("hrNewEmployee")}</Link>}
          <Link className="btn btn-secondary" href="/erp/hr/me"><Icon name="ph-identification-badge" size={18} /> {t("hrMyHr")}</Link>
        </>} />

      <StatPills items={[
        { label: t("hrHeadcount"), value: data.headcount, icon: "ph-users-three", href: "/erp/hr/employees", hint: data.suspended ? `${data.suspended} ${t("hrStSuspended").toLowerCase()}` : undefined },
        { label: t("hrOnLeaveToday"), value: data.on_leave_today.length, icon: "ph-airplane-tilt", href: "/erp/hr/leave?tab=calendar" },
        { label: t("hrPendingLeave"), value: data.pending_leave, icon: "ph-hourglass", tone: data.pending_leave ? "warn" : "neutral", href: "/erp/hr/leave" },
        { label: t("hrPresentToday"), value: data.attendance_today.present + data.attendance_today.late, icon: "ph-fingerprint", href: "/erp/hr/attendance", hint: `${data.attendance_today.late} ${t("hrStLate").toLowerCase()} · ${data.attendance_today.absent} ${t("hrStAbsent").toLowerCase()}` },
      ]} />

      <div className="erp-grid">
        <GlassCard title={t("hrPayrollStatus")} subtitle={monthLabel(data.payroll.current_period, locale)}
          action={<Link className="vf-card-link" href="/erp/hr/payroll">{t("hrPayroll")}</Link>}>
          {current ? (
            <div className="erp-list">
              <Link className="erp-list-row" href={`/erp/hr/payroll/${current.id}`}>
                <span className="erp-list-main"><span className="erp-list-title tnum">{current.number}</span>
                  <span className="erp-list-sub">{current.employees_count} {t("hrPayslips").toLowerCase()}{current.net !== null && <> · {t("hrNet")} <Tzs value={current.net} /></>}</span></span>
                <HrStatus status={current.status} />
              </Link>
            </div>
          ) : <EmptyState icon="ph-money" title={t("hrNoRunThisMonth")} />}
          {data.payroll.latest && data.payroll.latest.id !== current?.id && (
            <p className="erp-muted">{t("hrLatestRun")}: {data.payroll.latest.number} · <HrStatus status={data.payroll.latest.status} /></p>
          )}
        </GlassCard>

        <GlassCard title={t("hrHeadcountByDept")}>
          {data.by_department.length === 0 ? <EmptyState icon="ph-users" title={t("hrNoEmployees")} /> : (
            <ul className="erp-hbars">
              {data.by_department.map((d) => (
                <li key={d.department_id ?? 0}>
                  <span className="erp-hbar-label">{d.department ?? t("hrNoDepartment")}</span>
                  <span className="erp-hbar-track"><span className="erp-hbar-fill" style={{ width: `${(d.headcount / max) * 100}%` }} /></span>
                  <span className="erp-hbar-value tnum">{d.headcount}</span>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        <GlassCard title={t("hrOnLeaveToday")}>
          {data.on_leave_today.length === 0 ? <EmptyState icon="ph-sun" title={t("hrNobodyAway")} /> : (
            <div className="erp-list">
              {data.on_leave_today.map((r) => (
                <Link key={r.id} className="erp-list-row" href={`/erp/hr/employees/${r.employee_id}`}>
                  <span className="erp-list-main"><span className="erp-list-title">{r.employee}</span><span className="erp-list-sub">{r.leave_type} · {t("hrUntil")} {formatDate(r.end_date, locale)}</span></span>
                </Link>
              ))}
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("hrContractsExpiring")} subtitle={t("hrNext60Days")}>
          {data.contracts_expiring.length === 0 && data.probation_ending.length === 0 ? <EmptyState icon="ph-file-text" title={t("hrNothingExpiring")} /> : (
            <div className="erp-list">
              {data.contracts_expiring.map((c) => (
                <Link key={c.contract_id} className="erp-list-row" href={`/erp/hr/employees/${c.employee_id}`}>
                  <span className="erp-list-main"><span className="erp-list-title">{c.employee}</span><span className="erp-list-sub">{t("hrContractEnds")} {formatDate(c.end_date, locale)}</span></span>
                </Link>
              ))}
              {data.probation_ending.map((p) => (
                <Link key={`p${p.employee_id}`} className="erp-list-row" href={`/erp/hr/employees/${p.employee_id}`}>
                  <span className="erp-list-main"><span className="erp-list-title">{p.employee}</span><span className="erp-list-sub">{t("hrProbationEnds")} {formatDate(p.probation_end, locale)}</span></span>
                </Link>
              ))}
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("hrPeopleWork")}>
          <div className="erp-list">
            {can("hr.recruit") && <Link className="erp-list-row" href="/erp/hr/recruitment"><span className="erp-list-main"><span className="erp-list-title">{t("hrRecruitment")}</span><span className="erp-list-sub">{data.open_vacancies} {t("hrOpenVacancies")} · {data.applicants_in_pipeline} {t("hrInPipeline")}</span></span></Link>}
            <Link className="erp-list-row" href="/erp/hr/exits"><span className="erp-list-main"><span className="erp-list-title">{t("hrExits")}</span><span className="erp-list-sub">{data.exits_in_progress} {t("hrStInProgress").toLowerCase()}</span></span></Link>
            {data.open_discipline_cases !== null && <Link className="erp-list-row" href="/erp/hr/discipline"><span className="erp-list-main"><span className="erp-list-title">{t("hrDiscipline")}</span><span className="erp-list-sub">{data.open_discipline_cases} {t("hrStOpen").toLowerCase()}</span></span></Link>}
            <Link className="erp-list-row" href="/erp/hr/performance"><span className="erp-list-main"><span className="erp-list-title">{t("hrPerformance")}</span><span className="erp-list-sub">{t("hrPerformanceSub")}</span></span></Link>
          </div>
        </GlassCard>
      </div>
    </div>
  );
}
