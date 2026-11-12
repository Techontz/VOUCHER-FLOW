"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp } from "@/lib/erp";
import { today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { FilterChips } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload, useLookups, useStatusLabel } from "@/components/hr-ui";
import { CONTRACT_KEY, CONTRACT_TYPES, useEmploymentTypes } from "@/components/hr-employee-fields";

interface Applicant { id: number; name: string; email: string | null; phone: string | null; stage: string; notes: string | null; employee_id: number | null; employee?: { id: number; full_name: string } | null }
interface Vacancy { id: number; title: string; department?: { name: string } | null; department_id: number | null; positions: number; employment_type: string; location: string | null; description: string | null; closing_date: string | null; status: string; applicants_count?: number; hired_count?: number; applicants?: Applicant[] }
const STAGES = ["applied", "screening", "interview", "offer", "hired", "rejected"];

export default function RecruitmentPage() {
  return <HrGate anyOf={["hr.recruit"]}><Recruitment /></HrGate>;
}

function Recruitment() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const types = useEmploymentTypes();
  const stage = useStatusLabel();
  const [status, setStatus] = useState("open");
  const [rows, setRows] = useState<Paginated<Vacancy> | null>(null);
  const [selected, setSelected] = useState<Vacancy | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"vacancy" | "edit" | "applicant" | null>(null);
  const [hiring, setHiring] = useState<Applicant | null>(null);

  const load = useCallback(() => { api.get<Paginated<Vacancy>>("/erp/hr/vacancies", { status: status || undefined }).then(setRows).catch((e) => setError(e.message)); }, [status]);
  useEffect(load, [load]);
  const open = useCallback((id: number) => { api.get<{ data: Vacancy }>(`/erp/hr/vacancies/${id}`).then((r) => setSelected(r.data)).catch((e) => setError(e.message)); }, []);

  async function move(a: Applicant, to: string) {
    try { await api.put(`/erp/hr/applicants/${a.id}`, { stage: to }); if (selected) open(selected.id); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }

  const vacancyFields = [
    { name: "title", label: t("hrJobTitle"), required: true },
    { name: "department_id", label: t("hrDepartment"), type: "select" as const, options: lookups.departments.map((d) => ({ value: d.id, label: d.name })) },
    { name: "positions", label: t("hrPositions"), type: "number" as const, required: true },
    { name: "employment_type", label: t("hrEmploymentType"), type: "select" as const, required: true, options: types },
    { name: "location", label: t("hrLocation") },
    { name: "closing_date", label: t("hrClosingDate"), type: "date" as const },
    { name: "description", label: t("hrDescription"), type: "textarea" as const, wide: true },
  ];

  return (
    <div className="erp-page">
      <PageHeader title={t("hrRecruitment")} subtitle={t("hrRecruitmentSub")}
        actions={<button className="btn btn-primary" onClick={() => setDialog("vacancy")}><Icon name="ph-megaphone" size={18} /> {t("hrNewVacancy")}</button>} />
      <FilterChips value={status} onChange={setStatus} items={[{ value: "open", label: t("hrStOpen") }, { value: "filled", label: t("hrStFilled") }, { value: "closed", label: t("hrStClosed") }, { value: "", label: t("erpAll") }]} />

      {error && <ErrorState message={error} />}
      <div className="erp-grid">
        <GlassCard title={t("hrVacancies")} pad={false}>
          {!rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-megaphone" title={t("hrNoVacancies")} /> : (
            <div className="erp-list">
              {rows.data.map((v) => (
                <button key={v.id} type="button" className="erp-list-row" aria-current={selected?.id === v.id} onClick={() => open(v.id)}>
                  <span className="erp-list-main"><span className="erp-list-title">{v.title}</span><span className="erp-list-sub">{v.department?.name ?? "-"} · {v.applicants_count} {t("hrApplicants").toLowerCase()} · {v.hired_count}/{v.positions}</span></span>
                  <HrStatus status={v.status} />
                </button>
              ))}
            </div>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={selected?.title ?? t("hrChooseVacancy")}
          subtitle={selected ? `${selected.location ?? ""}${selected.closing_date ? ` · ${t("hrClosingDate")} ${formatDate(selected.closing_date, locale)}` : ""}` : undefined}
          action={selected && <>
            <button className="btn btn-secondary btn-sm" onClick={() => setDialog("edit")}>{t("erpEdit")}</button>{" "}
            {selected.status === "open" && <button className="btn btn-primary btn-sm" onClick={() => setDialog("applicant")}><Icon name="ph-user-plus" size={15} /> {t("hrAddApplicant")}</button>}
          </>}>
          {!selected ? <EmptyState icon="ph-hand-pointing" title={t("hrChooseVacancy")} /> : (
            <>
              {selected.description && <p className="erp-muted">{selected.description}</p>}
              {(selected.applicants ?? []).length === 0 ? <EmptyState icon="ph-users" title={t("hrNoApplicants")} /> : (
                <div className="vf-table-wrap">
                  <table className="table vf-table">
                    <thead><tr><th>{t("erpName")}</th><th>{t("hrStage")}</th><th /></tr></thead>
                    <tbody>
                      {selected.applicants!.map((a) => (
                        <tr key={a.id}>
                          <td><span className="erp-cell-title">{a.name}</span><span className="erp-cell-sub">{[a.phone, a.email, a.notes].filter(Boolean).join(" · ")}</span></td>
                          <td>{a.stage === "hired" || a.stage === "rejected" ? <HrStatus status={a.stage} /> : (
                            <select className="input" aria-label={t("hrStage")} value={a.stage} onChange={(e) => move(a, e.target.value)}>
                              {STAGES.filter((s) => s !== "hired").map((s) => <option key={s} value={s}>{stage(s)}</option>)}
                            </select>
                          )}</td>
                          <td>
                            {a.employee ? <Link className="btn btn-secondary btn-sm" href={`/erp/hr/employees/${a.employee.id}`}>{t("hrOpenRecord")}</Link>
                              : a.stage !== "rejected" && <button className="btn btn-primary btn-sm" onClick={() => setHiring(a)}>{t("hrHire")}</button>}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
        </GlassCard>
      </div>

      <FormDialog open={dialog === "vacancy"} title={t("hrNewVacancy")} onClose={() => setDialog(null)} initial={{ positions: "1", employment_type: "permanent" }} fields={vacancyFields}
        onSubmit={async (v) => { const r = await api.post<{ data: Vacancy }>("/erp/hr/vacancies", payload(v, ["department_id", "positions"])); setDialog(null); load(); open(r.data.id); }} />

      <FormDialog open={dialog === "edit"} title={selected?.title ?? ""} onClose={() => setDialog(null)}
        initial={selected ? { title: selected.title, department_id: String(selected.department_id ?? ""), positions: String(selected.positions), employment_type: selected.employment_type, location: selected.location ?? "", closing_date: selected.closing_date?.slice(0, 10) ?? "", description: selected.description ?? "", status: selected.status } : {}}
        fields={[...vacancyFields, { name: "status", label: t("erpStatus"), type: "select", options: ["open", "closed", "filled"].map((s) => ({ value: s, label: stage(s) })) }]}
        onSubmit={async (v) => { if (!selected) return; await api.put(`/erp/hr/vacancies/${selected.id}`, payload(v, ["department_id", "positions"])); setDialog(null); load(); open(selected.id); }} />

      <FormDialog open={dialog === "applicant"} title={t("hrAddApplicant")} onClose={() => setDialog(null)}
        fields={[{ name: "name", label: t("erpName"), required: true }, { name: "phone", label: t("erpPhone") }, { name: "email", label: t("erpEmail"), type: "email" }, { name: "notes", label: t("hrNotes"), type: "textarea", wide: true }]}
        onSubmit={async (v) => { if (!selected) return; await api.post(`/erp/hr/vacancies/${selected.id}/applicants`, payload(v)); setDialog(null); open(selected.id); load(); }} />

      <FormDialog open={!!hiring} title={`${t("hrHire")} · ${hiring?.name ?? ""}`} onClose={() => setHiring(null)} submitLabel={t("hrHire")}
        intro={<p className="erp-muted">{t("hrHireHint")}</p>}
        initial={{ hire_date: today(), contract_type: "probation" }}
        fields={[
          { name: "hire_date", label: t("hrHireDate"), type: "date", required: true },
          { name: "probation_end", label: t("hrProbationEnd"), type: "date" },
          { name: "employee_number", label: t("hrEmployeeNumber"), hint: t("hrNumberAuto") },
          { name: "grade", label: t("hrGrade") },
          ...(can("hr.salary") ? [
            { name: "contract_type", label: t("hrContractType"), type: "select" as const, options: CONTRACT_TYPES.map((c) => ({ value: c, label: t(CONTRACT_KEY[c]) })) },
            { name: "basic_salary", label: t("hrBasic"), type: "number" as const },
            { name: "housing_allowance", label: t("hrHousing"), type: "number" as const },
            { name: "transport_allowance", label: t("hrTransport"), type: "number" as const },
          ] : []),
        ]}
        onSubmit={async (v) => {
          if (!hiring) return;
          const contract = v.basic_salary ? { type: v.contract_type || "probation", start_date: v.hire_date, basic_salary: Number(v.basic_salary), housing_allowance: Number(v.housing_allowance || 0), transport_allowance: Number(v.transport_allowance || 0) } : undefined;
          const r = await api.post<{ message: string; data: { id: number } }>(`/erp/hr/applicants/${hiring.id}/hire`, {
            hire_date: v.hire_date, probation_end: v.probation_end || null, employee_number: v.employee_number || null, grade: v.grade || null, contract,
          });
          toast(r.message, undefined, "ok"); setHiring(null); load(); if (selected) open(selected.id);
        }} />
    </div>
  );
}
