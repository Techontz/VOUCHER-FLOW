"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { relativeTime } from "@/lib/format";
import { USER_STATUS, fill, initialsOf } from "@/lib/platform";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination, Spinner } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator, SearchInput, Toolbar } from "@/components/app-ui";
import type { Paginated, User } from "@/lib/types";

/*
 * Every account on the platform, across all companies. The operator can
 * suspend or reactivate people (one or many), change a role within that
 * company's roles, send a link to set a password, and delete accounts. The
 * API refuses the operator's own account, the last active operator and a
 * company's last active administrator, and says why.
 */

type PlatformUser = User & { company_name?: string | null };
type BulkResult = { skipped: { id: number; name: string; reason: string }[]; message: string };
type RoleOption = { key: string; label: string };

type Pending =
  | { kind: "delete" | "suspend" | "activate"; users: PlatformUser[] }
  | { kind: "role"; users: [PlatformUser] }
  | { kind: "invite"; users: [PlatformUser] };

export default function PlatformUsersPage() {
  const { t, locale, toast, reportError, user: me } = useApp();
  const [page, setPage] = useState(1);
  const [filters, setFilters] = useState({ q: "", company_id: "", role: "", status: "", sort: "" });
  const [result, setResult] = useState<Paginated<PlatformUser> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [companies, setCompanies] = useState<{ id: number; name: string }[]>([]);
  const [roles, setRoles] = useState<RoleOption[]>([]);
  const [selected, setSelected] = useState<Set<number>>(() => new Set());
  const [pending, setPending] = useState<Pending | null>(null);
  const [roleChoices, setRoleChoices] = useState<RoleOption[] | null>(null);
  const [role, setRole] = useState("");
  const [link, setLink] = useState<{ url: string; sent: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get<{ data: { id: number; name: string }[] }>("/platform/companies", { per_page: 500 })
      .then((r) => setCompanies(r.data)).catch(() => setCompanies([]));
    api.get<{ data: RoleOption[] }>("/platform/users/roles").then((r) => setRoles(r.data)).catch(() => setRoles([]));
  }, []);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<PlatformUser>>("/platform/users", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q]);

  const filter = (key: keyof typeof filters) => (value: string) => { setPage(1); setSelected(new Set()); setFilters((f) => ({ ...f, [key]: value })); };

  function ask(next: Pending) {
    setLink(null);
    setPending(next);
    if (next.kind === "role") {
      const u = next.users[0];
      setRole(u.role);
      setRoleChoices(null);
      api.get<{ data: RoleOption[] }>("/platform/users/roles", { company_id: u.company_id ?? "" })
        .then((r) => setRoleChoices(r.data)).catch(() => setRoleChoices(roles));
    }
  }

  async function confirm() {
    if (!pending) return;
    const { kind, users } = pending;
    const one = users.length === 1 ? users[0] : null;
    setBusy(true);
    try {
      if (kind === "delete") {
        if (one) {
          await api.delete(`/platform/users/${one.id}`);
          toast(t("pfUserDeleted"), one.name, "warn");
        } else {
          const res = await api.post<BulkResult>("/platform/users/bulk-delete", { ids: users.map((u) => u.id) });
          report(res);
        }
      } else if (kind === "suspend" || kind === "activate") {
        const status = kind === "suspend" ? "suspended" : "active";
        if (one) {
          await api.put(`/platform/users/${one.id}`, { status });
          toast(kind === "suspend" ? t("pfUserSuspended") : t("pfUserActivated"), one.name, kind === "suspend" ? "warn" : "ok");
        } else {
          const res = await api.post<BulkResult>("/platform/users/bulk-status", { ids: users.map((u) => u.id), status });
          report(res);
        }
      } else if (kind === "role" && one) {
        await api.put(`/platform/users/${one.id}`, { role });
        toast(t("pfRoleChanged"), one.name, "ok");
      } else if (kind === "invite" && one) {
        const res = await api.post<{ invitation_url: string; invitation_sent: boolean; message: string }>(`/platform/users/${one.id}/invite`);
        setLink({ url: res.invitation_url, sent: res.invitation_sent });
        toast(res.invitation_sent ? t("pfLinkSent") : t("pfLinkNotSent"), one.email, res.invitation_sent ? "ok" : "warn");
        load();
        return;
      }
      setPending(null);
      setSelected(new Set());
      load();
    } catch (err) {
      reportError(err, t("pfActionFailed"));
    } finally { setBusy(false); }
  }

  function report(res: BulkResult) {
    toast(res.message, res.skipped.length
      ? fill(t("pfSkipped"), { n: res.skipped.length, list: res.skipped.map((s) => `${s.name}: ${s.reason}`).join(" ") })
      : undefined, res.skipped.length ? "warn" : "ok");
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

  const p = pending;
  const one = p && p.users.length === 1 ? p.users[0] : null;
  const title = !p ? "" : p.kind === "role" ? fill(t("pfChangeRoleOf"), { name: p.users[0].name })
    : p.kind === "invite" ? fill(t("pfSendLinkTo"), { name: p.users[0].name })
    : fill(t(p.kind === "delete" ? "pfDeleteUsersQ" : p.kind === "suspend" ? "pfSuspendUsersQ" : "pfActivateUsersQ"),
      { who: one ? one.name : fill(t("pfNUsers"), { n: p.users.length }) });
  const sub = !p ? undefined : {
    delete: t("pfDeleteUsersSub"), suspend: t("pfSuspendUsersSub"), activate: t("pfActivateUsersSub"),
    role: t("pfChangeRoleSub"), invite: t("pfSendLinkSub"),
  }[p.kind];

  return (
    <div className="app-page pf-page">
      <PageHeader kicker={t("pfPlatform")} title={t("users")} subtitle={t("pfUsersSub")} />

      <section className="vf-panel">
        <Toolbar end={result?.meta && <span className="pf-muted pf-nowrap">{fill(t("pfResults"), { n: result.meta.total })}</span>}>
          <SearchInput value={filters.q} onChange={filter("q")} placeholder={t("pfSearchPeople")} />
          <select className="input" value={filters.company_id} onChange={(e) => filter("company_id")(e.target.value)} aria-label={t("companyName")}>
            <option value="">{t("pfAllCompanies")}</option>
            <option value="platform">{t("pfPlatformTeam")}</option>
            {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select className="input" value={filters.role} onChange={(e) => filter("role")(e.target.value)} aria-label={t("role")}>
            <option value="">{t("pfAllRoles")}</option>
            <option value="super_admin">{t("pfRoleSuperAdmin")}</option>
            {roles.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
          </select>
          <select className="input" value={filters.status} onChange={(e) => filter("status")(e.target.value)} aria-label={t("status")}>
            <option value="">{t("allStatuses")}</option>
            <option value="active">{t("pfStatusActive")}</option>
            <option value="invited">{t("invited")}</option>
            <option value="suspended">{t("pfStatusSuspended")}</option>
          </select>
          <select className="input" value={filters.sort} onChange={(e) => filter("sort")(e.target.value)} aria-label={t("pfSort")}>
            <option value="">{t("pfSortName")}</option>
            <option value="recent">{t("pfSortNewest")}</option>
          </select>
        </Toolbar>

        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
        {result && rows.length === 0 && <EmptyState icon="ph-users-three" title={t("noResults")} />}

        {rows.length > 0 && (
          <>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead>
                  <tr>
                    <th style={{ width: 40 }}>
                      <input type="checkbox" className="pf-sel" aria-label={t("pfSelectPage")} checked={allChosen}
                        onChange={() => setSelected(allChosen ? new Set() : new Set(selectable.map((u) => u.id)))} />
                    </th>
                    <th>{t("fullName")}</th><th>{t("companyName")}</th><th>{t("role")}</th>
                    <th>{t("status")}</th><th>{t("pfLastSeen")}</th><th><span className="sr-only">{t("actions")}</span></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((u) => {
                    const st = USER_STATUS[u.status];
                    const self = u.id === me?.id;
                    return (
                      <tr key={u.id} aria-selected={selected.has(u.id)} style={selected.has(u.id) ? { background: "var(--table-row-selected)" } : undefined}>
                        <td>
                          {!self && <input type="checkbox" className="pf-sel" aria-label={fill(t("pfSelectUser"), { name: u.name })}
                            checked={selected.has(u.id)} onChange={() => toggle(u.id)} />}
                        </td>
                        <td>
                          <div className="app-person">
                            <span className="app-avatar" aria-hidden="true">{u.initials ?? initialsOf(u.name)}</span>
                            <span className="app-person-text"><strong>{u.name}{self && <> · {t("pfYou")}</>}</strong><span>{u.email}</span></span>
                          </div>
                        </td>
                        <td>
                          {!u.company_id ? <Badge tone="info">{t("pfPlatformTeam")}</Badge>
                            : u.company_name ? <Link className="pf-link" href={`/platform/companies/${u.company_id}`}>{u.company_name}</Link>
                            : <Badge tone="neutral">{t("pfDeletedCompany")}</Badge>}
                        </td>
                        <td>{u.role === "super_admin" ? t("pfRoleSuperAdmin") : u.role_label}</td>
                        <td><Badge tone={st?.tone ?? "neutral"} dot>{st ? t(st.label) : u.status}</Badge></td>
                        <td className="pf-nowrap">{u.last_login_at ? relativeTime(u.last_login_at, locale) : <span className="pf-muted">{t("pfNever")}</span>}</td>
                        <td className="app-row-actions">
                          {!self && (
                            <Dropdown floating label={fill(t("pfActionsFor"), { name: u.name })}
                              trigger={({ open, toggle: toggleMenu, id }) => (
                                <button type="button" className="btn btn-icon btn-sm" onClick={toggleMenu} aria-expanded={open} aria-controls={id}
                                  aria-haspopup="menu" aria-label={fill(t("pfActionsFor"), { name: u.name })}>
                                  <Icon name="ph-dots-three-outline" size={18} />
                                </button>
                              )}>
                              {(close) => (
                                <>
                                  {u.company_id && <MenuItem icon="ph-user-switch" onSelect={() => { close(); ask({ kind: "role", users: [u] }); }}>{t("pfChangeRole")}</MenuItem>}
                                  {u.company_id && u.status !== "suspended" && (
                                    <MenuItem icon="ph-key" onSelect={() => { close(); ask({ kind: "invite", users: [u] }); }}>{u.last_login_at ? t("pfSendReset") : t("pfSendInvite")}</MenuItem>
                                  )}
                                  {u.status !== "suspended"
                                    ? <MenuItem icon="ph-prohibit" onSelect={() => { close(); ask({ kind: "suspend", users: [u] }); }}>{t("suspend")}</MenuItem>
                                    : <MenuItem icon="ph-check-circle" onSelect={() => { close(); ask({ kind: "activate", users: [u] }); }}>{t("activate")}</MenuItem>}
                                  <MenuSeparator />
                                  <MenuItem icon="ph-trash" tone="danger" onSelect={() => { close(); ask({ kind: "delete", users: [u] }); }}>{t("delete")}</MenuItem>
                                </>
                              )}
                            </Dropdown>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1}
              total={result?.meta?.total ?? rows.length} onChange={(n) => { setSelected(new Set()); setPage(n); }} />
          </>
        )}
      </section>

      {chosen.length > 0 && (
        <div className="app-bulk-bar" role="region" aria-label={t("pfSelectedUsers")}>
          <span><strong className="tnum">{chosen.length}</strong> {t("selected")}</span>
          <div className="app-bulk-bar-actions">
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelected(new Set())}>{t("clearSelection")}</button>
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => ask({ kind: "activate", users: chosen })}>
              <Icon name="ph-check-circle" size={15} /> {t("activate")}
            </button>
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => ask({ kind: "suspend", users: chosen })}>
              <Icon name="ph-prohibit" size={15} /> {t("suspend")}
            </button>
            <button type="button" className="btn btn-danger-solid btn-sm" onClick={() => ask({ kind: "delete", users: chosen })}>
              <Icon name="ph-trash" size={15} /> {t("delete")} ({chosen.length})
            </button>
          </div>
        </div>
      )}

      <Dialog open={!!p} busy={busy} onClose={() => setPending(null)}
        icon={p?.kind === "delete" ? "ph-trash" : p?.kind === "suspend" ? "ph-prohibit" : p?.kind === "role" ? "ph-user-switch" : p?.kind === "invite" ? "ph-key" : "ph-check-circle"}
        tone={p?.kind === "delete" ? "bad" : p?.kind === "suspend" ? "warn" : p?.kind === "activate" ? "ok" : "info"}
        title={title} sub={sub}
        summary={one ? [
          { label: t("email"), value: one.email },
          { label: t("companyName"), value: one.company_name ?? t("pfPlatformTeam") },
          { label: t("role"), value: one.role_label },
        ] : undefined}
        actions={link ? (
          <button type="button" className="btn btn-primary" onClick={() => setPending(null)}>{t("close")}</button>
        ) : <>
          <button type="button" className="btn btn-secondary" onClick={() => setPending(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className={p?.kind === "delete" ? "btn btn-danger-solid" : "btn btn-primary"} onClick={() => void confirm()}
            disabled={busy || (p?.kind === "role" && (!role || role === one?.role))}>
            {busy ? <Spinner /> : p?.kind === "delete" ? t("delete") : p?.kind === "suspend" ? t("suspend") : p?.kind === "activate" ? t("activate")
              : p?.kind === "invite" ? t("pfSendLink") : t("save")}
          </button>
        </>}>
        {p && p.users.length > 1 && (
          <ul className="app-bulk-list">
            {p.users.map((u) => (
              <li key={u.id}><Icon name="ph-user" size={15} /><span className="app-bulk-list-purpose">{u.name} · {u.email}</span><span>{u.role_label}</span></li>
            ))}
          </ul>
        )}
        {p?.kind === "role" && (
          <Field label={t("role")} htmlFor="pu-role">
            {roleChoices === null ? <Spinner /> : (
              <select id="pu-role" className="input" value={role} onChange={(e) => setRole(e.target.value)}>
                {roleChoices.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
              </select>
            )}
          </Field>
        )}
        {p?.kind === "invite" && link && (
          <Field label={link.sent ? t("pfLinkSentLabel") : t("pfLinkShareLabel")} htmlFor="pu-link" hint={t("pfLinkHint")}>
            <div className="pf-copy">
              <input id="pu-link" className="input" readOnly value={link.url} onFocus={(e) => e.currentTarget.select()} />
              <button type="button" className="btn btn-secondary" onClick={() => { void navigator.clipboard?.writeText(link.url); toast(t("pfCopied"), undefined, "ok"); }}>
                <Icon name="ph-copy" size={15} /> {t("pfCopy")}
              </button>
            </div>
          </Field>
        )}
      </Dialog>
    </div>
  );
}
