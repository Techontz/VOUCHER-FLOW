"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator } from "@/components/app-ui";
import type { Paginated, User } from "@/lib/types";

type BulkResult = { deleted: number; skipped: { id: number; name: string; reason: string }[]; message: string };

export default function PlatformUsersPage() {
  const { t, locale, toast, reportError, user: me } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", role: "", status: "" });
  const [result, setResult] = useState<Paginated<User> | null>(null);
  const [error, setError] = useState<string | null>(null);
  // The user listing carries company_id only; name it from the companies list,
  // which the platform operator can already read, rather than showing "#1".
  const [companyNames, setCompanyNames] = useState<Record<number, string> | null>(null);
  const [selected, setSelected] = useState<Set<number>>(() => new Set());
  // One account, or every selected one, waiting for the operator to confirm.
  const [removing, setRemoving] = useState<User[] | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get<{ data: { id: number; name: string }[] }>("/platform/companies", { per_page: 500 })
      .then((r) => setCompanyNames(Object.fromEntries(r.data.map((c) => [c.id, c.name]))))
      .catch(() => setCompanyNames({}));
  }, []);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<User>>("/platform/users", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q, locale]);

  async function setStatus(user: User, status: "active" | "suspended") {
    try {
      await api.put(`/platform/users/${user.id}`, { status });
      toast(status === "suspended" ? "User suspended" : "User activated", user.name, status === "suspended" ? "warn" : "ok");
      load();
    } catch (err) { reportError(err); }
  }

  async function confirmRemove() {
    if (!removing) return;
    setBusy(true);
    try {
      if (removing.length === 1) {
        await api.delete(`/platform/users/${removing[0].id}`);
        toast("User deleted", removing[0].name, "warn");
      } else {
        const res = await api.post<BulkResult>("/platform/users/bulk-delete", { ids: removing.map((u) => u.id) });
        toast(res.message, res.skipped.length
          ? `Kept ${res.skipped.length}: ${res.skipped.map((s) => `${s.name} — ${s.reason}`).join(" ")}`
          : undefined, res.skipped.length ? "warn" : "ok");
      }
      setRemoving(null);
      setSelected(new Set());
      load();
    } catch (err) {
      reportError(err, "Could not delete");
    } finally {
      setBusy(false);
    }
  }

  const rows = result?.data ?? [];
  const selectable = rows.filter((u) => u.id !== me?.id);
  const allChosen = selectable.length > 0 && selectable.every((u) => selected.has(u.id));
  const chosen = rows.filter((u) => selected.has(u.id));
  const toggle = (id: number) => setSelected((s) => {
    const next = new Set(s);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });

  const companyCell = (user: User) => {
    if (!user.company_id) return <span className="badge tone-info">Platform</span>;
    if (!companyNames) return "—";
    return companyNames[user.company_id] ?? <span className="badge tag-outline" title="This company was deleted">Deleted company</span>;
  };

  return (
    <div className="app-page">
      <PageHeader kicker="Platform" title={t("users")} sub="Every account across all tenants." />

      <section className="vf-panel">
      <div className="app-toolbar">
        <div className="app-toolbar-main">
        <input className="input app-toolbar-search" placeholder={t("search")} value={filters.q}
          onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, q: e.target.value })); }} aria-label={t("search")} />
        <select className="input" value={filters.role} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, role: e.target.value })); }} aria-label={t("role")}>
          <option value="">All roles</option>
          <option value="super_admin">Super Admin</option><option value="company_admin">Administrator</option>
          <option value="hod">HOD</option><option value="manager">Manager</option><option value="ceo">CEO</option><option value="cashier">Cashier</option>
          <option value="finance">Finance</option><option value="employee">Employee</option>
        </select>
        <select className="input" value={filters.status} onChange={(e) => { setPage(1); setFilters((f) => ({ ...f, status: e.target.value })); }} aria-label={t("status")}>
          <option value="">{t("allStatuses")}</option>
          <option value="active">{t("active")}</option><option value="invited">{t("invited")}</option><option value="suspended">{t("suspended")}</option>
        </select>
        </div>
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
                  <th style={{ width: 36 }}>
                    <input type="checkbox" aria-label="Select every user on this page" checked={allChosen}
                      onChange={() => setSelected(allChosen ? new Set() : new Set(selectable.map((u) => u.id)))}
                      style={{ accentColor: "var(--primary)" }} />
                  </th>
                  <th>{t("fullName")}</th><th>{t("companyName")}</th><th>{t("role")}</th>
                  <th>{t("status")}</th><th>Last seen</th><th><span className="sr-only">{t("actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((user) => (
                  <tr key={user.id} style={selected.has(user.id) ? { background: "var(--primary-soft)" } : undefined}>
                    <td>
                      {user.id !== me?.id && (
                        <input type="checkbox" aria-label={`Select ${user.name}`} checked={selected.has(user.id)}
                          onChange={() => toggle(user.id)} style={{ accentColor: "var(--primary)" }} />
                      )}
                    </td>
                    <td>
                      <span style={{ fontWeight: 500 }}>{user.name}</span>
                      <span style={{ display: "block", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{user.email}</span>
                    </td>
                    <td>{companyCell(user)}</td>
                    <td>{user.role_label}</td>
                    <td>
                      <span className={`badge ${user.status === "active" ? "tag-accent" : user.status === "invited" ? "tag-outline" : "tag-accent-2"}`}>
                        {user.status}
                      </span>
                    </td>
                    <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDateTime(user.last_login_at, locale)}</td>
                    <td className="app-row-actions">
                      {user.id !== me?.id && (
                        <Dropdown floating label={user.name}
                          trigger={({ open, toggle: toggleMenu, id }) => (
                            <button type="button" className="btn btn-icon btn-sm" onClick={toggleMenu} aria-expanded={open} aria-controls={id}
                              aria-haspopup="menu" aria-label={`${t("actions")}: ${user.name}`}>
                              <Icon name="ph-dots-three" size={16} />
                            </button>
                          )}>
                          {(close) => (
                            <>
                              {user.status !== "suspended"
                                ? <MenuItem icon="ph-prohibit" onSelect={() => { close(); void setStatus(user, "suspended"); }}>{t("suspend")}</MenuItem>
                                : <MenuItem icon="ph-check-circle" onSelect={() => { close(); void setStatus(user, "active"); }}>{t("activate")}</MenuItem>}
                              <MenuSeparator />
                              <MenuItem icon="ph-trash" tone="danger" onSelect={() => { close(); setRemoving([user]); }}>{t("delete")}</MenuItem>
                            </>
                          )}
                        </Dropdown>
                      )}
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

      {chosen.length > 0 && (
        <div className="app-bulk-bar" role="region" aria-label="Selected users">
          <span><strong className="tnum">{chosen.length}</strong> {t("selected")}</span>
          <div className="app-bulk-bar-actions">
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelected(new Set())}>{t("clearSelection")}</button>
            <button type="button" className="btn btn-danger-solid btn-sm" onClick={() => setRemoving(chosen)}>
              <Icon name="ph-trash" size={15} /> {t("delete")} ({chosen.length})
            </button>
          </div>
        </div>
      )}

      <Dialog
        open={!!removing} busy={busy}
        icon="ph-trash" tone="bad"
        title={removing?.length === 1 ? `${t("delete")} ${removing[0].name}?` : `${t("delete")} ${removing?.length ?? 0} users?`}
        sub="They are signed out and can no longer sign in. Vouchers they raised or acted on stay on the record. A company's last administrator is kept — delete the company instead."
        summary={removing?.length === 1
          ? [{ label: t("email"), value: removing[0].email }, { label: t("role"), value: removing[0].role_label }]
          : undefined}
        onClose={() => setRemoving(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setRemoving(null)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-danger-solid" onClick={() => void confirmRemove()} disabled={busy}>
              <Icon name="ph-trash" size={15} /> {t("delete")}
            </button>
          </>
        }
      >
        {removing && removing.length > 1 && (
          <ul className="app-bulk-list">
            {removing.map((u) => (
              <li key={u.id}><Icon name="ph-user" size={15} /><span className="app-bulk-list-purpose">{u.name} · {u.email}</span><span>{u.role_label}</span></li>
            ))}
          </ul>
        )}
      </Dialog>
    </div>
  );
}
