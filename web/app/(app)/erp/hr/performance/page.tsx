"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { n, today } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Tabs, Toolbar } from "@/components/app-ui";
import { FormDialog, HrGate, HrStatus, payload, Tzs, useLookups, useStatusLabel } from "@/components/hr-ui";

interface Period { id: number; name: string; start_date: string; end_date: string; status: string; appraisals_count: number }
interface Objective { id: number; title: string; target: string | null; weight: number; rating: number | null; comment: string | null }
interface Appraisal { id: number; status: string; overall_rating: string | null; reviewer_comments: string | null; employee_comments: string | null; objectives_count?: number; employee?: { full_name: string; employee_number: string; job_title?: string; department?: { name: string } | null }; period?: { id?: number; name: string }; reviewer?: { name: string } | null; objectives?: Objective[] }
interface Training { id: number; employee_id: number; title: string; provider: string | null; start_date: string; end_date: string | null; cost: string; status: string; notes: string | null; employee?: { full_name: string } }
type Tab = "appraisals" | "periods" | "training";

export default function PerformancePage() {
  return <HrGate anyOf={["hr.view"]}><Performance /></HrGate>;
}

function Performance() {
  const { t } = useApp();
  const [tab, setTab] = useState<Tab>("appraisals");
  return (
    <div className="erp-page">
      <PageHeader title={t("hrPerformance")} subtitle={t("hrPerformanceSub")} />
      <Tabs label={t("hrPerformance")} value={tab} onChange={setTab} items={[{ value: "appraisals", label: t("hrAppraisals") }, { value: "periods", label: t("hrPeriods") }, { value: "training", label: t("hrTraining") }]} />
      {tab === "appraisals" && <Appraisals />}
      {tab === "periods" && <Periods />}
      {tab === "training" && <Trainings />}
    </div>
  );
}

function Appraisals() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const deep = useQueryValue("appraisal");
  const [periods, setPeriods] = useState<Period[]>([]);
  const [periodId, setPeriodId] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Appraisal> | null>(null);
  const [open, setOpen] = useState<Appraisal | null>(null);
  const [starting, setStarting] = useState(false);
  const [objective, setObjective] = useState<Objective | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const manage = can("hr.manage");

  useEffect(() => { api.get<{ data: Period[] }>("/erp/hr/appraisal-periods").then((r) => setPeriods(r.data)).catch(() => undefined); }, []);
  const load = useCallback(() => { api.get<Paginated<Appraisal>>("/erp/hr/appraisals", { period_id: periodId || undefined, page }).then(setRows).catch((e) => setError(e.message)); }, [periodId, page]);
  useEffect(load, [load]);
  const show = useCallback((id: number) => { api.get<{ data: Appraisal }>(`/erp/hr/appraisals/${id}`).then((r) => setOpen(r.data)).catch((e) => toast(t("hrActionFailed"), e.message, "bad")); }, [t, toast]);
  useEffect(() => { if (deep) show(Number(deep)); }, [deep, show]);

  async function complete() {
    if (!open) return;
    try { await api.post(`/erp/hr/appraisals/${open.id}/complete`); toast(t("erpSaved"), undefined, "ok"); show(open.id); load(); }
    catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); }
  }
  async function saveComments(text: string) {
    if (!open) return;
    await api.put(`/erp/hr/appraisals/${open.id}`, { reviewer_comments: text });
  }

  const openPeriods = periods.filter((p) => p.status === "open");

  return (
    <>
      <Toolbar end={manage && openPeriods.length > 0 && <button className="btn btn-primary" onClick={() => setStarting(true)}><Icon name="ph-play" size={16} /> {t("hrStartAppraisals")}</button>}>
        <select className="input" aria-label={t("hrPeriod")} value={periodId} onChange={(e) => { setPeriodId(e.target.value); setPage(1); }} style={{ maxWidth: 260 }}>
          <option value="">{t("erpAll")}</option>{periods.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-target" title={t("hrNoAppraisals")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrEmployee")}</th><th>{t("hrPeriod")}</th><th>{t("hrReviewer")}</th><th className="num">{t("hrObjectives")}</th><th className="num">{t("hrRating")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((a) => (
                  <tr key={a.id} className="is-clickable" onClick={() => show(a.id)}>
                    <td><span className="erp-cell-title">{a.employee?.full_name}</span><span className="erp-cell-sub">{a.employee?.department?.name}</span></td>
                    <td>{a.period?.name}</td><td>{a.reviewer?.name ?? "-"}</td><td className="num">{a.objectives_count}</td>
                    <td className="num">{a.overall_rating ? n(a.overall_rating) : "-"}</td><td><HrStatus status={a.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {open && (
        <Dialog open wide title={`${open.employee?.full_name ?? ""} · ${open.period?.name ?? ""}`} onClose={() => setOpen(null)}
          actions={<>
            {manage && open.status !== "completed" && <button className="btn btn-secondary" onClick={() => setObjective("new")}><Icon name="ph-plus" size={15} /> {t("hrAddObjective")}</button>}
            {manage && open.status !== "completed" && <button className="btn btn-primary" onClick={complete}>{t("hrComplete")}</button>}
            <button className="btn btn-secondary" onClick={() => setOpen(null)}>{t("hrClose")}</button>
          </>}>
          <HrStatus status={open.status} /> {open.overall_rating && <strong>{t("hrRating")}: {n(open.overall_rating)} / 5</strong>}
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrObjective")}</th><th>{t("hrTarget")}</th><th className="num">{t("hrWeight")}</th><th className="num">{t("hrRating")}</th><th /></tr></thead>
              <tbody>
                {(open.objectives ?? []).map((o) => (
                  <tr key={o.id}><td>{o.title}{o.comment && <span className="erp-cell-sub">{o.comment}</span>}</td><td>{o.target ?? "-"}</td><td className="num">{o.weight}</td><td className="num">{o.rating ?? "-"}</td>
                    <td>{manage && open.status !== "completed" && <button className="btn btn-ghost btn-sm" onClick={() => setObjective(o)}>{t("hrRate")}</button>}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
          {open.employee_comments && <p><strong>{t("hrEmployeeComments")}:</strong> {open.employee_comments}</p>}
          <ReviewerComments key={open.id} initial={open.reviewer_comments ?? ""} editable={manage && open.status !== "completed"} onSave={saveComments} />
        </Dialog>
      )}

      <FormDialog open={!!objective} title={objective === "new" ? t("hrAddObjective") : t("hrRate")} onClose={() => setObjective(null)}
        initial={objective && objective !== "new" ? { title: objective.title, target: objective.target ?? "", weight: String(objective.weight), rating: String(objective.rating ?? ""), comment: objective.comment ?? "" } : { weight: "1" }}
        fields={[
          { name: "title", label: t("hrObjective"), required: true, wide: true }, { name: "target", label: t("hrTarget") },
          { name: "weight", label: t("hrWeight"), type: "number" },
          { name: "rating", label: t("hrRating"), type: "select", options: [1, 2, 3, 4, 5].map((r) => ({ value: r, label: String(r) })) },
          { name: "comment", label: t("hrComment"), wide: true },
        ]}
        onSubmit={async (v) => {
          if (!open) return;
          const body = payload(v, ["weight", "rating"]);
          if (objective === "new") await api.post(`/erp/hr/appraisals/${open.id}/objectives`, body); else if (objective) await api.put(`/erp/hr/appraisal-objectives/${objective.id}`, body);
          setObjective(null); show(open.id);
        }} />

      <FormDialog open={starting} title={t("hrStartAppraisals")} onClose={() => setStarting(false)} intro={<p className="erp-muted">{t("hrStartAppraisalsHint")}</p>}
        initial={{ period_id: String(openPeriods[0]?.id ?? "") }}
        fields={[{ name: "period_id", label: t("hrPeriod"), type: "select", required: true, options: openPeriods.map((p) => ({ value: p.id, label: p.name })) }]}
        onSubmit={async (v) => { const r = await api.post<{ message: string }>("/erp/hr/appraisals", payload(v, ["period_id"])); toast(r.message, undefined, "ok"); setStarting(false); load(); }} />
    </>
  );
}

function ReviewerComments({ initial, editable, onSave }: { initial: string; editable: boolean; onSave: (text: string) => Promise<void> }) {
  const { t, toast } = useApp();
  const [text, setText] = useState(initial);
  if (!editable) return initial ? <p><strong>{t("hrReviewerComments")}:</strong> {initial}</p> : null;
  return (
    <div className="field">
      <label htmlFor="rev-comments">{t("hrReviewerComments")}</label>
      <textarea id="rev-comments" className="input" rows={3} value={text} onChange={(e) => setText(e.target.value)} />
      <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={async () => { try { await onSave(text); toast(t("erpSaved"), undefined, "ok"); } catch (e) { toast(t("hrActionFailed"), (e as Error).message, "bad"); } }}>{t("erpSave")}</button>
    </div>
  );
}

function Periods() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const label = useStatusLabel();
  const [rows, setRows] = useState<Period[] | null>(null);
  const [adding, setAdding] = useState(false);
  const load = useCallback(() => { api.get<{ data: Period[] }>("/erp/hr/appraisal-periods").then((r) => setRows(r.data)).catch(() => setRows([])); }, []);
  useEffect(load, [load]);
  const manage = can("hr.manage");
  return (
    <>
      {manage && <Toolbar><button className="btn btn-primary" onClick={() => setAdding(true)}><Icon name="ph-plus" size={16} /> {t("hrNewPeriod")}</button></Toolbar>}
      {!rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-calendar" title={t("hrNoPeriods")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpName")}</th><th>{t("hrStart")}</th><th>{t("hrEnd")}</th><th className="num">{t("hrAppraisals")}</th><th>{t("erpStatus")}</th><th /></tr></thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}><td>{p.name}</td><td className="tnum">{formatDate(p.start_date, locale)}</td><td className="tnum">{formatDate(p.end_date, locale)}</td><td className="num">{p.appraisals_count}</td><td><HrStatus status={p.status} /></td>
                  <td>{manage && <button className="btn btn-secondary btn-sm" onClick={async () => { await api.put(`/erp/hr/appraisal-periods/${p.id}`, { status: p.status === "open" ? "closed" : "open" }); load(); }}>{p.status === "open" ? label("closed") : label("open")}</button>}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <FormDialog open={adding} title={t("hrNewPeriod")} onClose={() => setAdding(false)}
        fields={[{ name: "name", label: t("erpName"), required: true }, { name: "start_date", label: t("hrStart"), type: "date", required: true }, { name: "end_date", label: t("hrEnd"), type: "date", required: true }]}
        onSubmit={async (v) => { await api.post("/erp/hr/appraisal-periods", payload(v)); setAdding(false); load(); }} />
    </>
  );
}

function Trainings() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const lookups = useLookups();
  const label = useStatusLabel();
  const [rows, setRows] = useState<Paginated<Training> | null>(null);
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<Training | "new" | null>(null);
  const load = useCallback(() => { api.get<Paginated<Training>>("/erp/hr/trainings", { page }).then(setRows).catch(() => undefined); }, [page]);
  useEffect(load, [load]);
  const manage = can("hr.manage");
  return (
    <>
      {manage && <Toolbar><button className="btn btn-primary" onClick={() => setEditing("new")}><Icon name="ph-plus" size={16} /> {t("hrNewTraining")}</button></Toolbar>}
      {!rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-graduation-cap" title={t("hrNoTraining")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("hrTraining")}</th><th>{t("hrEmployee")}</th><th>{t("hrDates")}</th><th className="num">{t("hrCost")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className={manage ? "is-clickable" : undefined} onClick={manage ? () => setEditing(r) : undefined}>
                    <td><span className="erp-cell-title">{r.title}</span><span className="erp-cell-sub">{r.provider}</span></td><td>{r.employee?.full_name}</td>
                    <td className="tnum">{formatDate(r.start_date, locale)}{r.end_date ? ` - ${formatDate(r.end_date, locale)}` : ""}</td>
                    <td className="num"><Tzs value={r.cost} /></td><td><HrStatus status={r.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
      <FormDialog open={!!editing} title={editing === "new" ? t("hrNewTraining") : (editing as Training | null)?.title ?? ""} onClose={() => setEditing(null)}
        initial={editing && editing !== "new" ? { employee_id: String(editing.employee_id), title: editing.title, provider: editing.provider ?? "", start_date: editing.start_date.slice(0, 10), end_date: editing.end_date?.slice(0, 10) ?? "", cost: String(n(editing.cost)), status: editing.status, notes: editing.notes ?? "" } : { start_date: today(), status: "planned" }}
        fields={[
          { name: "employee_id", label: t("hrEmployee"), type: "select", required: true, options: lookups.employees.map((e) => ({ value: e.id, label: e.full_name })) },
          { name: "title", label: t("hrTraining"), required: true }, { name: "provider", label: t("hrProvider") },
          { name: "start_date", label: t("hrStart"), type: "date", required: true }, { name: "end_date", label: t("hrEnd"), type: "date" },
          { name: "cost", label: t("hrCost"), type: "number" },
          { name: "status", label: t("erpStatus"), type: "select", required: true, options: ["planned", "in_progress", "completed", "cancelled"].map((s) => ({ value: s, label: label(s) })) },
          { name: "notes", label: t("hrNotes"), wide: true },
        ]}
        onSubmit={async (v) => {
          const body = payload(v, ["employee_id", "cost"]);
          if (editing === "new") await api.post("/erp/hr/trainings", body); else if (editing) await api.put(`/erp/hr/trainings/${editing.id}`, body);
          setEditing(null); load();
        }} />
    </>
  );
}
