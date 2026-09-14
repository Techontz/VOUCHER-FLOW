"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, Spinner } from "@/components/ui";
import { SettingsLayout } from "@/components/app-ui";
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

  const [removing, setRemoving] = useState<Department | null>(null);
  const setField = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));
  const fe = (name: string) => formError?.field(name);

  return (
    <SettingsLayout title={t("departments")}
      sub="Each department names a head and an approving manager. Workflow steps resolve their actor from these."
      actions={<button className="btn btn-primary" onClick={openCreate}><Icon name="ph-plus" size={15} /> {t("addDepartment")}</button>}>

      <section className="vf-panel">
        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!rows && !error && <div className="vf-panel-pad"><LoadingBlock rows={5} /></div>}
        {rows && rows.length === 0 && (
          <EmptyState icon="ph-tree-structure" title="No departments yet"
            body="Create your first department so vouchers can be routed to the right head."
            action={<button className="btn btn-primary" onClick={openCreate}>{t("addDepartment")}</button>} />
        )}

        {rows && rows.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("department")}</th><th>{t("headOfDept")}</th><th>{t("approvingManager")}</th>
                  <th className="num">{t("people")}</th>
                  <th className="num">{t("vouchers")}</th>
                  <th className="num">{t("spendQuarter")}</th><th aria-label={t("actions")} />
                </tr>
              </thead>
              <tbody>
                {rows.map((dept) => (
                  <tr key={dept.id}>
                    <td>
                      <div style={{ fontWeight: 500 }}>{dept.name}</div>
                      {dept.cost_centre && <div className="app-cell-sub">{dept.cost_centre}</div>}
                    </td>
                    <td>{dept.hod?.name ?? <span className="badge tone-warn">Not assigned</span>}</td>
                    <td>{dept.manager?.name ?? <span className="badge tone-warn">Not assigned</span>}</td>
                    <td className="num">{dept.users_count ?? 0}</td>
                    <td className="num">{dept.vouchers_count ?? 0}</td>
                    <td className="num" style={{ whiteSpace: "nowrap", fontWeight: 600 }}>{money(dept.spend ?? 0, company?.currency)}</td>
                    <td className="app-row-actions">
                      <button className="btn btn-ghost btn-sm btn-icon" onClick={() => openEdit(dept)} aria-label={`Edit ${dept.name}`} title={t("edit")}>
                        <Icon name="ph-pencil-simple" size={14} />
                      </button>
                      <button className="btn btn-ghost btn-sm btn-icon vf-text-bad" onClick={() => setRemoving(dept)} aria-label={`Delete ${dept.name}`} title={t("delete")}>
                        <Icon name="ph-trash" size={14} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <Dialog
        open={!!removing} icon="ph-trash" tone="bad"
        title={`${t("delete")} ${removing?.name ?? ""}?`}
        sub="Vouchers already raised in this department keep their record."
        onClose={() => setRemoving(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setRemoving(null)}>{t("cancel")}</button>
            <button className="btn btn-danger-solid" onClick={() => { const d = removing; setRemoving(null); if (d) void remove(d); }}>
              <Icon name="ph-trash" size={15} /> {t("delete")}
            </button>
          </>
        }
      />

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
    </SettingsLayout>
  );
}
