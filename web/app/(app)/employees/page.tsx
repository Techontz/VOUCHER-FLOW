"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination, Spinner } from "@/components/ui";
import type { Department, Paginated, User } from "@/lib/types";

const ROLES = [
  { value: "employee", label: "Employee" },
  { value: "hod", label: "Head of department" },
  { value: "manager", label: "Manager" },
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

  return (
    <div style={{ maxWidth: 1200 }}>
      <PageHeader kicker={t("settings")} title={t("employees")}
        sub="People in this company, their role and what they may act on."
        actions={<button className="btn btn-primary" onClick={openCreate}><Icon name="ph-user-plus" size={15} /> {t("inviteUser")}</button>} />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        <input className="input" placeholder={t("search")} value={filters.q} onChange={set("q")} aria-label={t("search")} />
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

      {error && <ErrorState message={error} onRetry={load} />}
      {!result && !error && <LoadingBlock rows={6} />}
      {result && rows.length === 0 && <EmptyState icon="ph-users-three" title={t("noResults")} />}

      {rows.length > 0 && (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("fullName")}</th><th>{t("employeeId")}</th><th>{t("department")}</th>
                  <th>{t("role")}</th><th>{t("status")}</th><th style={{ textAlign: "right" }}>{t("vouchers")}</th>
                  <th>{t("joined")}</th><th />
                </tr>
              </thead>
              <tbody>
                {rows.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
                        <span style={{ width: 28, height: 28, borderRadius: "50%", background: "var(--color-accent-200)", color: "var(--color-accent-800)", display: "grid", placeItems: "center", fontSize: 11.5, fontWeight: 600, flex: "none" }}>
                          {user.initials}
                        </span>
                        <span>
                          <span style={{ display: "block", fontWeight: 500 }}>{user.name}</span>
                          <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{user.email}</span>
                        </span>
                      </div>
                    </td>
                    <td style={{ fontVariantNumeric: "tabular-nums" }}>{user.employee_code ?? "—"}</td>
                    <td>{user.department?.name ?? "—"}</td>
                    <td>{user.role_label}</td>
                    <td>
                      <span className={`tag ${user.status === "active" ? "tag-accent" : user.status === "invited" ? "tag-outline" : "tag-accent-2"}`}>
                        {user.status}
                      </span>
                    </td>
                    <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{user.voucher_count ?? 0}</td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDate(user.joined_at, locale)}</td>
                    <td style={{ whiteSpace: "nowrap", textAlign: "right" }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => openEdit(user)} aria-label={`Edit ${user.name}`}>
                        <Icon name="ph-pencil-simple" size={14} />
                      </button>
                      {user.status !== "suspended" ? (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(user, "suspended")} title={t("suspend")}>
                          <Icon name="ph-prohibit" size={14} />
                        </button>
                      ) : (
                        <button className="btn btn-ghost btn-sm" onClick={() => setStatus(user, "active")} title={t("activate")}>
                          <Icon name="ph-check-circle" size={14} />
                        </button>
                      )}
                      <button className="btn btn-ghost btn-sm" onClick={() => remove(user)} title={t("delete")} style={{ color: "var(--color-accent-2-700)" }}>
                        <Icon name="ph-trash" size={14} />
                      </button>
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
            <div style={{ fontSize: 13.5, color: "var(--color-neutral-600)" }}>
              A temporary password is generated and shown once. The user is asked to sign in with it.
            </div>
          )}
        </div>
      </Dialog>
    </div>
  );
}
