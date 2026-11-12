"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { type HrEmployee, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { type FieldSpec, FormDialog, HrGate, HrStatus, payload, Tzs, useLookups } from "@/components/hr-ui";
import { CONTRACT_KEY, CONTRACT_TYPES, useEmploymentTypes } from "@/components/hr-employee-fields";

export default function EmployeesPage() {
  return <HrGate anyOf={["hr.view"]}><Employees /></HrGate>;
}

function Employees() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const lookups = useLookups();
  const types = useEmploymentTypes();
  const wantsNew = useQueryValue("new");
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [department, setDepartment] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<HrEmployee> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAddingState] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [users, setUsers] = useState<{ id: number; name: string; email: string }[]>([]);
  const salary = can("hr.salary");
  // ?new=1 from the overview opens the form once.
  const addOpen = adding || (wantsNew === "1" && can("hr.manage") && !dismissed);
  const setAdding = (v: boolean) => { setAddingState(v); if (!v) setDismissed(true); };

  const load = useCallback(() => {
    api.get<Paginated<HrEmployee>>("/erp/hr/employees", { q: q || undefined, status: status || undefined, department_id: department || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [q, status, department, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);
  useEffect(() => { if (addOpen) api.get<{ data: typeof users }>("/erp/hr/linkable-users").then((r) => setUsers(r.data)).catch(() => undefined); }, [addOpen]);

  const fields: FieldSpec[] = [
    { name: "full_name", label: t("hrFullName"), required: true },
    { name: "employee_number", label: t("hrEmployeeNumber"), hint: t("hrNumberAuto") },
    { name: "user_id", label: t("hrLinkUser"), type: "select", options: users.map((u) => ({ value: u.id, label: `${u.name} (${u.email})` })), hint: t("hrLinkUserHint") },
    { name: "job_title", label: t("hrJobTitle") },
    { name: "grade", label: t("hrGrade") },
    { name: "department_id", label: t("hrDepartment"), type: "select", options: lookups.departments.map((d) => ({ value: d.id, label: d.name })) },
    { name: "manager_id", label: t("hrManager"), type: "select", options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
    { name: "employment_type", label: t("hrEmploymentType"), type: "select", required: true, options: types },
    { name: "hire_date", label: t("hrHireDate"), type: "date", required: true },
    { name: "probation_end", label: t("hrProbationEnd"), type: "date" },
    { name: "phone", label: t("erpPhone") },
    { name: "email", label: t("erpEmail"), type: "email" },
    { name: "gender", label: t("hrGender"), type: "select", options: [{ value: "female", label: t("hrFemale") }, { value: "male", label: t("hrMale") }] },
    { name: "date_of_birth", label: t("hrDateOfBirth"), type: "date" },
    { name: "national_id", label: t("hrNationalId") },
    { name: "tin", label: t("erpTin") },
    { name: "nssf_number", label: t("hrNssfNumber") },
    ...(salary ? [
      { name: "bank_name", label: t("hrBank") },
      { name: "bank_account_number", label: t("hrBankAccount") },
      { name: "contract_type", label: t("hrContractType"), type: "select", options: CONTRACT_TYPES.map((c) => ({ value: c, label: t(CONTRACT_KEY[c]) })) },
      { name: "basic_salary", label: t("hrBasic"), type: "number" },
      { name: "housing_allowance", label: t("hrHousing"), type: "number" },
      { name: "transport_allowance", label: t("hrTransport"), type: "number" },
      { name: "contract_end", label: t("hrContractEnd"), type: "date" },
    ] as FieldSpec[] : []),
    { name: "heslb_beneficiary", label: t("hrHeslbBeneficiary"), type: "checkbox" },
  ];

  return (
    <div className="erp-page">
      <PageHeader title={t("hrEmployees")} subtitle={t("hrEmployeesSub")}
        actions={can("hr.manage") && <button className="btn btn-primary" onClick={() => setAdding(true)}><Icon name="ph-user-plus" size={18} /> {t("hrNewEmployee")}</button>} />

      <Toolbar end={
        <select className="input" aria-label={t("hrDepartment")} value={department} onChange={(e) => { setDepartment(e.target.value); setPage(1); }} style={{ maxWidth: 220 }}>
          <option value="">{t("hrAllDepartments")}</option>
          {lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
      }>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("hrEmployeeNumber")}`} />
        <FilterChips value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("hrCurrent") }, { value: "active", label: t("hrStActive") },
          { value: "suspended", label: t("hrStSuspended") }, { value: "exited", label: t("hrStExited") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-users-three" title={t("hrNoEmployees")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrEmployee")}</th><th>{t("hrDepartment")}</th><th>{t("hrEmploymentType")}</th><th>{t("hrHireDate")}</th>{salary && <th className="num">{t("hrBasic")}</th>}<th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((e) => (
                  <tr key={e.id} className="is-clickable" onClick={() => router.push(`/erp/hr/employees/${e.id}`)}>
                    <td><Link href={`/erp/hr/employees/${e.id}`} className="erp-cell-link"><span className="erp-cell-title">{e.full_name}</span><span className="erp-cell-sub tnum">{e.employee_number}{e.job_title ? ` · ${e.job_title}` : ""}</span></Link></td>
                    <td>{e.department?.name ?? "-"}</td>
                    <td>{types.find((x) => x.value === e.employment_type)?.label ?? e.employment_type}</td>
                    <td className="tnum">{formatDate(e.hire_date, locale)}</td>
                    {salary && <td className="num">{e.contract?.basic_salary !== undefined ? <Tzs value={e.contract.basic_salary} /> : "-"}</td>}
                    <td><HrStatus status={e.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <FormDialog open={addOpen} title={t("hrNewEmployee")} fields={fields} onClose={() => setAdding(false)}
        initial={{ employment_type: "permanent", hire_date: today(), contract_type: "permanent", heslb_beneficiary: false }}
        onSubmit={async (v) => {
          const body = payload(v, ["user_id", "department_id", "manager_id"]);
          const contract = salary && v.basic_salary ? {
            type: v.contract_type || "permanent", start_date: v.hire_date, end_date: v.contract_end || null,
            basic_salary: Number(v.basic_salary), housing_allowance: Number(v.housing_allowance || 0), transport_allowance: Number(v.transport_allowance || 0),
          } : undefined;
          for (const k of ["contract_type", "basic_salary", "housing_allowance", "transport_allowance", "contract_end"]) delete body[k];
          const r = await api.post<{ data: HrEmployee }>("/erp/hr/employees", { ...body, contract });
          toast(t("erpSaved"), r.data.full_name, "ok");
          setAdding(false);
          router.push(`/erp/hr/employees/${r.data.id}`);
        }} />
    </div>
  );
}
