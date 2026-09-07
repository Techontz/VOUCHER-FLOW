"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import type { Department } from "@/lib/types";

interface DirectoryUser { id: number; name: string; role: string }

const blank = { name: "", code: "", cost_centre: "", hod_user_id: "", manager_user_id: "" };

export default function DepartmentsPage() {
  const { t, company, toast, reportError } = useApp();
  const [rows, setRows] = useState<Department[] | null>(null);
  const [people, setPeople] = useState<DirectoryUser[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState(false);
  const [editing, setEditing] = useState<Department | null>(null);
  const [form, setForm] = useState(blank);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Department[] }>("/departments")
      .then((r) => setRows(r.data))
      .catch((err) => setError(err.message));
  }, []);

  useEffect(() => {
    load();
    api.get<{ data: DirectoryUser[] }>("/directory").then((r) => setPeople(r.data)).catch(() => undefined);
  }, [load]);

  function openCreate() { setEditing(null); setForm(blank); setFormError(null); setDialog(true); }

  function openEdit(dept: Department) {
    setEditing(dept);
    setForm({
      name: dept.name, code: dept.code ?? "", cost_centre: dept.cost_centre ?? "",
      hod_user_id: dept.hod_user_id ? String(dept.hod_user_id) : "",
      manager_user_id: dept.manager_user_id ? String(dept.manager_user_id) : "",
    });
    setFormError(null);
    setDialog(true);
  }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const payload = {
        ...form,
        hod_user_id: form.hod_user_id ? Number(form.hod_user_id) : null,
        manager_user_id: form.manager_user_id ? Number(form.manager_user_id) : null,
      };
      if (editing) await api.put(`/departments/${editing.id}`, payload);
      else await api.post("/departments", payload);
      toast(editing ? "Department updated" : "Department created", form.name, "ok");
      setDialog(false);
      load();
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the department");
    } finally { setBusy(false); }
  }

  async function remove(dept: Department) {
    try {
      await api.delete(`/departments/${dept.id}`);
      toast("Department deleted", dept.name, "warn");
      load();
    } catch (err) { reportError(err, "Could not delete the department"); }
  }

  const setField = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));
  const fe = (name: string) => formError?.field(name);

  return (
    <div style={{ maxWidth: 1100 }}>
      <PageHeader kicker={t("settings")} title={t("departments")}
        sub="Each department names a head and an approving manager. Workflow steps resolve their actor from these."
        actions={<button className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus-circle" size={15} /> {t("addDepartment")}</button>} />

      {error && <ErrorState message={error} onRetry={load} />}
      {!rows && !error && <LoadingBlock rows={5} />}
      {rows && rows.length === 0 && (
        <EmptyState icon="ph-buildings" title="No departments yet"
          body="Create your first department so vouchers can be routed to the right head."
          action={<button className="btn btn-primary" onClick={openCreate}>{t("addDepartment")}</button>} />
      )}

      {rows && rows.length > 0 && (
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>{t("department")}</th><th>{t("headOfDept")}</th><th>{t("approvingManager")}</th>
                <th style={{ textAlign: "right" }}>{t("people")}</th>
                <th style={{ textAlign: "right" }}>{t("vouchers")}</th>
                <th style={{ textAlign: "right" }}>{t("spendQuarter")}</th><th />
              </tr>
            </thead>
            <tbody>
              {rows.map((dept) => (
                <tr key={dept.id}>
                  <td>
                    <span style={{ fontWeight: 500 }}>{dept.name}</span>
                    {dept.cost_centre && <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{dept.cost_centre}</span>}
                  </td>
                  <td>{dept.hod?.name ?? <span style={{ color: "var(--color-accent-2-700)" }}>Not assigned</span>}</td>
                  <td>{dept.manager?.name ?? <span style={{ color: "var(--color-accent-2-700)" }}>Not assigned</span>}</td>
                  <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{dept.users_count ?? 0}</td>
                  <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{dept.vouchers_count ?? 0}</td>
                  <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                    {money(dept.spend ?? 0, company?.currency)}
                  </td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(dept)} aria-label={`Edit ${dept.name}`}>
                      <Icon name="ph-pencil-simple" size={14} />
                    </button>
                    <button className="btn btn-ghost btn-sm" onClick={() => remove(dept)} aria-label={`Delete ${dept.name}`} style={{ color: "var(--color-accent-2-700)" }}>
                      <Icon name="ph-trash" size={14} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Dialog open={dialog} title={editing ? t("edit") : t("addDepartment")} onClose={() => setDialog(false)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(false)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.name}>{busy ? <Spinner /> : t("save")}</button>
          </>
        }>
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <Field label={t("department")} htmlFor="d-name" error={fe("name")} required>
            <input id="d-name" className="input" value={form.name} onChange={setField("name")} required />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-3)" }}>
            <Field label="Code" htmlFor="d-code"><input id="d-code" className="input" value={form.code} onChange={setField("code")} /></Field>
            <Field label={t("costCentre")} htmlFor="d-cc"><input id="d-cc" className="input" value={form.cost_centre} onChange={setField("cost_centre")} /></Field>
          </div>
          <Field label={t("headOfDept")} htmlFor="d-hod" hint="Signs at any workflow step assigned to the HOD role">
            <select id="d-hod" className="input" value={form.hod_user_id} onChange={setField("hod_user_id")}>
              <option value="">—</option>
              {people.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.role})</option>)}
            </select>
          </Field>
          <Field label={t("approvingManager")} htmlFor="d-mgr" hint="Acts at any step assigned to the Manager role">
            <select id="d-mgr" className="input" value={form.manager_user_id} onChange={setField("manager_user_id")}>
              <option value="">—</option>
              {people.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.role})</option>)}
            </select>
          </Field>
        </div>
      </Dialog>
    </div>
  );
}
