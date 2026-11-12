"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useQueryValue } from "@/lib/erp";
import { today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Toolbar } from "@/components/app-ui";
import { FilterChips } from "@/components/erp-ui";
import { FormDialog, HrGate, HrStatus, payload, useLookups } from "@/components/hr-ui";

interface Case { id: number; number: string; employee_id: number; category: string; incident_date: string; description: string; action: string | null; status: string; outcome: string | null; closed_at: string | null; employee?: { id: number; full_name: string; employee_number: string }; opener?: { name: string } | null; closer?: { name: string } | null }
const CATEGORIES = ["absenteeism", "lateness", "misconduct", "negligence", "insubordination", "theft", "safety", "other"];
const ACTIONS = ["none", "counselling", "verbal_warning", "written_warning", "final_warning", "suspension", "dismissal"];
const human = (s: string | null) => (s ? s.replace(/_/g, " ") : "-");

export default function DisciplinePage() {
  return <HrGate anyOf={["hr.discipline"]}><Discipline /></HrGate>;
}

function Discipline() {
  const { t, locale, toast } = useApp();
  const lookups = useLookups();
  const deep = useQueryValue("case");
  const [status, setStatus] = useState("open");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Case> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<Case | null>(null);
  const [dialog, setDialog] = useState<"new" | "edit" | "close" | null>(null);

  const load = useCallback(() => { api.get<Paginated<Case>>("/erp/hr/discipline", { status: status || undefined, page }).then(setRows).catch((e) => setError(e.message)); }, [status, page]);
  useEffect(load, [load]);
  const show = useCallback((id: number) => { api.get<{ data: Case }>(`/erp/hr/discipline/${id}`).then((r) => setOpen(r.data)).catch((e) => setError(e.message)); }, []);
  useEffect(() => { if (deep) show(Number(deep)); }, [deep, show]);
  const options = (list: string[]) => list.map((x) => ({ value: x, label: human(x) }));

  return (
    <div className="erp-page">
      <PageHeader title={t("hrDiscipline")} subtitle={t("hrDisciplineSub")}
        actions={<button className="btn btn-primary" onClick={() => setDialog("new")}><Icon name="ph-plus" size={18} /> {t("hrNewCase")}</button>} />
      <div className="vf-alert tone-warn"><Icon name="ph-lock-simple" size={18} /><span className="vf-alert-text">{t("hrConfidential")}</span></div>
      <Toolbar>
        <FilterChips value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[{ value: "open", label: t("hrStOpen") }, { value: "closed", label: t("hrStClosed") }, { value: "", label: t("erpAll") }]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-scales" title={t("hrNoCases")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrCase")}</th><th>{t("hrEmployee")}</th><th>{t("hrCategory")}</th><th>{t("hrIncidentDate")}</th><th>{t("hrActionTaken")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((c) => (
                  <tr key={c.id} className="is-clickable" onClick={() => show(c.id)}>
                    <td className="tnum">{c.number}</td><td>{c.employee?.full_name}</td><td>{human(c.category)}</td>
                    <td className="tnum">{formatDate(c.incident_date, locale)}</td><td>{human(c.action)}</td><td><HrStatus status={c.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {open && !dialog && (
        <Dialog open wide title={`${open.number} · ${open.employee?.full_name ?? ""}`} onClose={() => setOpen(null)}
          summary={[{ label: t("hrCategory"), value: human(open.category) }, { label: t("hrIncidentDate"), value: formatDate(open.incident_date, locale) }, { label: t("hrActionTaken"), value: human(open.action) }, { label: t("hrOpenedBy"), value: open.opener?.name ?? "-" }]}
          actions={<>
            {open.employee && <Link className="btn btn-secondary" href={`/erp/hr/employees/${open.employee.id}`}>{t("hrOpenRecord")}</Link>}
            {open.status === "open" && <button className="btn btn-secondary" onClick={() => setDialog("edit")}>{t("erpEdit")}</button>}
            {open.status === "open" && <button className="btn btn-primary" onClick={() => setDialog("close")}>{t("hrCloseCase")}</button>}
          </>}>
          <HrStatus status={open.status} />
          <p>{open.description}</p>
          {open.outcome && <p><strong>{t("hrOutcome")}:</strong> {open.outcome}{open.closer ? ` (${open.closer.name}, ${formatDate(open.closed_at, locale)})` : ""}</p>}
        </Dialog>
      )}

      <FormDialog open={dialog === "new"} title={t("hrNewCase")} onClose={() => setDialog(null)} initial={{ incident_date: today(), category: "misconduct" }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "category", label: t("hrCategory"), type: "select", required: true, options: options(CATEGORIES) },
          { name: "incident_date", label: t("hrIncidentDate"), type: "date", required: true },
          { name: "action", label: t("hrActionTaken"), type: "select", options: options(ACTIONS) },
          { name: "description", label: t("hrDescription"), type: "textarea", required: true, wide: true },
        ]}
        onSubmit={async (v) => { const r = await api.post<{ message: string; data: Case }>("/erp/hr/discipline", payload(v, ["employee_id"])); toast(r.message, undefined, "ok"); setDialog(null); load(); show(r.data.id); }} />

      <FormDialog open={dialog === "edit"} title={open?.number ?? ""} onClose={() => setDialog(null)}
        initial={open ? { category: open.category, action: open.action ?? "", description: open.description, outcome: open.outcome ?? "" } : {}}
        fields={[
          { name: "category", label: t("hrCategory"), type: "select", options: options(CATEGORIES) },
          { name: "action", label: t("hrActionTaken"), type: "select", options: options(ACTIONS) },
          { name: "description", label: t("hrDescription"), type: "textarea", wide: true },
          { name: "outcome", label: t("hrOutcome"), type: "textarea", wide: true },
        ]}
        onSubmit={async (v) => { if (!open) return; await api.put(`/erp/hr/discipline/${open.id}`, payload(v)); setDialog(null); show(open.id); load(); }} />

      <FormDialog open={dialog === "close"} title={t("hrCloseCase")} onClose={() => setDialog(null)} initial={{ action: open?.action ?? "", outcome: "" }}
        fields={[
          { name: "action", label: t("hrActionTaken"), type: "select", required: true, options: options(ACTIONS) },
          { name: "outcome", label: t("hrOutcome"), type: "textarea", required: true, wide: true },
        ]}
        onSubmit={async (v) => { if (!open) return; await api.post(`/erp/hr/discipline/${open.id}/close`, payload(v)); setDialog(null); show(open.id); load(); }} />
    </div>
  );
}
