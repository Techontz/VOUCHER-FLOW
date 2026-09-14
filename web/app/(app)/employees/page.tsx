"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, Note, ErrorState, Field, Icon, LoadingBlock, Pagination, Spinner } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator, SearchInput, SettingsLayout } from "@/components/app-ui";
import type { Department, Paginated, User } from "@/lib/types";

const ROLES = [
  { value: "employee", label: "Employee" },
  { value: "hod", label: "Head of department" },
  { value: "ceo", label: "CEO / approving manager" },
  { value: "cashier", label: "Cashier · finance" },
  { value: "finance", label: "Finance" },
  { value: "director", label: "Director" },
  { value: "company_admin", label: "Administrator" },
];

const blank = { name: "", email: "", phone: "", employee_code: "", job_title: "", role: "employee", department_id: "" };

export default function EmployeesPage() {
  const { t, locale, toast, reportError } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", role: "", status: "", department_id: "" });
  const [result, setResult] = useState<Paginated<User> | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [error, setError] = useState<string | null>(null);

  const [dialog, setDialog] = useState<"create" | "edit" | null>(null);
  const [editing, setEditing] = useState<User | null>(null);
  const [form, setForm] = useState(blank);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const [removing, setRemoving] = useState<User | null>(null);

  useEffect(() => {
    api.get<{ data: Department[] }>("/departments").then((r) => setDepartments(r.data)).catch(() => undefined);
  }, []);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<User>>("/employees", { ...filters, page, per_page: 25 })
      .then(setResult)
      .catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q]);

  function openCreate() {
    setForm(blank); setEditing(null); setFormError(null); setDialog("create");
  }

  function openEdit(user: User) {
    setEditing(user);
    setForm({
      name: user.name, email: user.email, phone: user.phone ?? "", employee_code: user.employee_code ?? "",
      job_title: user.job_title ?? "", role: user.role, department_id: user.department_id ? String(user.department_id) : "",
    });
    setFormError(null);
    setDialog("edit");
  }

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const payload = { ...form, department_id: form.department_id ? Number(form.department_id) : null };
      if (dialog === "create") {
        const res = await api.post<{ data: User; temporary_password?: string }>("/employees", { ...payload, send_invitation: true });
        toast("Invitation created", res.temporary_password
          ? `Temporary password for ${res.data.name}: ${res.temporary_password}`
          : `${res.data.name} has been invited.`, "ok");
      } else if (editing) {
        await api.put(`/employees/${editing.id}`, payload);
        toast("Updated", `${form.name} saved.`, "ok");
      }
      setDialog(null);
      load();
    } catch (err) {
      if (err instanceof ApiError) setFormError(err);
      reportError(err, "Could not save the user");
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(user: User, status: "active" | "suspended") {
    try {
      await api.put(`/employees/${user.id}`, { status });
      toast(status === "suspended" ? "User suspended" : "User activated", user.name, status === "suspended" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err, "Could not update the user"); }
  }

  async function remove(user: User) {
    try {
      await api.delete(`/employees/${user.id}`);
      toast("User removed", user.name, "warn");
      load();
    } catch (err) { reportError(err, "Could not remove the user"); }
  }

  const set = (key: keyof typeof filters) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setPage(1); setFilters((f) => ({ ...f, [key]: e.target.value }));
  };
  const setField = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  const rows = result?.data ?? [];
  const fe = (name: string) => formError?.field(name);

  const statusTone = (status: string) => status === "active" ? "tone-ok" : status === "invited" ? "tone-info" : "tone-bad";

  return (
    <SettingsLayout title={t("employees")}
      sub="People in this company, their role and what they may act on."
      actions={<button className="btn btn-primary" onClick={openCreate}><Icon name="ph-user-plus" size={15} /> {t("inviteUser")}</button>}>

      <section className="vf-panel">
        <div className="app-toolbar">
          <div className="app-toolbar-main">
            <SearchInput value={filters.q} onChange={(q) => { setPage(1); setFilters((f) => ({ ...f, q })); }} placeholder={t("search")} />
            <select className="input" value={filters.role} onChange={set("role")} aria-label={t("role")}>
              <option value="">All roles</option>
              {ROLES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
            </select>
            <select className="input" value={filters.status} onChange={set("status")} aria-label={t("status")}>
              <option value="">{t("allStatuses")}</option>
              <option value="active">{t("active")}</option>
              <option value="invited">{t("invited")}</option>
              <option value="suspended">{t("suspended")}</option>
            </select>
            <select className="input" value={filters.department_id} onChange={set("department_id")} aria-label={t("department")}>
              <option value="">{t("allDepartments")}</option>
              {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </div>
          {result?.meta?.total != null && <div className="app-toolbar-end"><span className="app-result-count">{result.meta.total} {t("users").toLowerCase()}</span></div>}
        </div>

        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
        {result && rows.length === 0 && <EmptyState icon="ph-users-three" title={t("noResults")} />}

        {rows.length > 0 && (
          <>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>
                    <th>{t("fullName")}</th><th>{t("employeeId")}</th><th>{t("department")}</th>
                    <th>{t("role")}</th><th>{t("status")}</th><th className="num">{t("vouchers")}</th>
                    <th>{t("joined")}</th><th aria-label={t("actions")} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((user) => (
                    <tr key={user.id}>
                      <td>
                        <div className="app-person">
                          <span className="app-avatar" aria-hidden="true">{user.initials}</span>
                          <span className="app-person-text">
                            <strong>{user.name}</strong>
                            <span>{user.email}</span>
                          </span>
                        </div>
                      </td>
                      <td className="tnum">{user.employee_code ?? "—"}</td>
                      <td>{user.department?.name ?? "—"}</td>
                      <td>
                        <div>{user.role_label}</div>
                        {user.job_title && <div className="app-cell-sub">{user.job_title}</div>}
                      </td>
                      <td><span className={`badge ${statusTone(user.status)}`}>{user.status}</span></td>
                      <td className="num">{user.voucher_count ?? 0}</td>
                      <td className="text-muted" style={{ whiteSpace: "nowrap" }}>{formatDate(user.joined_at, locale)}</td>
                      <td className="app-row-actions">
                        <Dropdown label={user.name}
                          trigger={({ open, toggle, id }) => (
                            <button type="button" className="btn btn-icon btn-sm" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu" aria-label={`${t("actions")}: ${user.name}`}>
                              <Icon name="ph-dots-three" size={16} />
                            </button>
                          )}>
                          {(close) => (
                            <>
                              <MenuItem icon="ph-pencil-simple" onSelect={() => { close(); openEdit(user); }}>{t("edit")}</MenuItem>
                              {user.status !== "suspended"
                                ? <MenuItem icon="ph-prohibit" onSelect={() => { close(); void setStatus(user, "suspended"); }}>{t("suspend")}</MenuItem>
                                : <MenuItem icon="ph-check-circle" onSelect={() => { close(); void setStatus(user, "active"); }}>{t("activate")}</MenuItem>}
                              <MenuSeparator />
                              <MenuItem icon="ph-trash" tone="danger" onSelect={() => { close(); setRemoving(user); }}>{t("delete")}</MenuItem>
                            </>
                          )}
                        </Dropdown>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1}
              total={result?.meta?.total ?? rows.length} onChange={setPage} />
          </>
        )}
      </section>

      <Dialog
        open={!!removing}
        icon="ph-trash" tone="bad"
        title={`${t("delete")} ${removing?.name ?? ""}?`}
        sub="They lose access immediately. Vouchers they raised or acted on stay on the record."
        summary={removing ? [{ label: t("email"), value: removing.email }, { label: t("role"), value: removing.role_label }] : undefined}
        onClose={() => setRemoving(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setRemoving(null)}>{t("cancel")}</button>
            <button className="btn btn-danger-solid" onClick={() => { const u = removing; setRemoving(null); if (u) void remove(u); }}>
              <Icon name="ph-trash" size={15} /> {t("delete")}
            </button>
          </>
        }
      />

      <Dialog
        open={dialog !== null}
        title={dialog === "create" ? t("inviteUser") : t("edit")}
        onClose={() => setDialog(null)}
        wide
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(null)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.name || !form.email}>
              {busy ? <Spinner /> : t("save")}
            </button>
          </>
        }
      >
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <Field label={t("fullName")} htmlFor="e-name" error={fe("name")} required>
            <input id="e-name" className="input" value={form.name} onChange={setField("name")} required />
          </Field>
          <Field label={t("email")} htmlFor="e-email" error={fe("email")} required>
            <input id="e-email" className="input" type="email" value={form.email} onChange={setField("email")} required />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-3)" }}>
            <Field label={t("phone")} htmlFor="e-phone"><input id="e-phone" className="input" value={form.phone} onChange={setField("phone")} /></Field>
            <Field label={t("employeeId")} htmlFor="e-code"><input id="e-code" className="input" value={form.employee_code} onChange={setField("employee_code")} /></Field>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-3)" }}>
            <Field label={t("role")} htmlFor="e-role" error={fe("role")} required>
              <select id="e-role" className="input" value={form.role} onChange={setField("role")}>
                {ROLES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </Field>
            <Field label={t("department")} htmlFor="e-dept">
              <select id="e-dept" className="input" value={form.department_id} onChange={setField("department_id")}>
                <option value="">—</option>
                {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </select>
            </Field>
          </div>
          <Field label={t("jobTitle")} htmlFor="e-title"><input id="e-title" className="input" value={form.job_title} onChange={setField("job_title")} /></Field>
          {dialog === "create" && (
            <Note>A temporary password is generated and shown once. The user is asked to sign in with it.</Note>
          )}
        </div>
      </Dialog>
    </SettingsLayout>
  );
}
