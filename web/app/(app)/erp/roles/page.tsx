"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Permission, type PermissionInfo, refreshErpConfig, type RoleRow } from "@/lib/erp";
import { Badge, Banner, Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";

/**
 * Roles & permissions: every role down the side, every permission grouped by
 * module, and a tick where the role holds it. A built-in role can be re-scoped
 * and restored; a company can add roles of its own.
 */
export default function RolesPage() {
  return <ErpGate permission="roles.manage"><Roles /></ErpGate>;
}

function Roles() {
  const { t, toast } = useApp();
  const [roles, setRoles] = useState<RoleRow[] | null>(null);
  const [catalogue, setCatalogue] = useState<PermissionInfo[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<string>("");
  const [draft, setDraft] = useState<Permission[]>([]);
  const [busy, setBusy] = useState(false);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback((keep?: string) => {
    api.get<{ data: RoleRow[]; catalogue: PermissionInfo[] }>("/erp/roles").then((r) => {
      setRoles(r.data); setCatalogue(r.catalogue);
      const pick = r.data.find((x) => x.key === (keep ?? selected)) ?? r.data.find((x) => !x.locked) ?? r.data[0];
      setSelected(pick.key); setDraft(pick.permissions);
    }).catch((e) => setError(e.message));
  }, [selected]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => load(), []);

  const role = roles?.find((r) => r.key === selected);
  const groups = useMemo(() => {
    const map = new Map<string, PermissionInfo[]>();
    catalogue.forEach((p) => map.set(p.group, [...(map.get(p.group) ?? []), p]));
    return [...map.entries()];
  }, [catalogue]);
  const dirty = role && [...draft].sort().join() !== [...role.permissions].sort().join();

  function choose(r: RoleRow) { setSelected(r.key); setDraft(r.permissions); }

  async function save() {
    if (!role) return;
    setBusy(true);
    try {
      await api.put(`/erp/roles/${role.key}`, { permissions: draft });
      toast(t("erpSaved"), role.name, "ok");
      await refreshErpConfig();
      load(role.key);
    } catch (e) { toast(e instanceof ApiError ? e.message : String(e), undefined, "bad"); } finally { setBusy(false); }
  }

  async function reset() {
    if (!role) return;
    setBusy(true);
    try {
      const r = await api.delete<{ message: string }>(`/erp/roles/${role.key}`);
      toast(r.message, undefined, "ok");
      await refreshErpConfig();
      load(role.built_in ? role.key : undefined);
    } catch (e) { toast(e instanceof ApiError ? e.message : String(e), undefined, "bad"); } finally { setBusy(false); }
  }

  async function create() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: { key: string } }>("/erp/roles", { name, description: description || null, permissions: [] });
      setCreating(false); setName(""); setDescription("");
      load(r.data.key);
    } catch (e) { setFormError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} />;
  if (!roles || !role) return <LoadingBlock rows={6} />;

  return (
    <div className="erp-page">
      <PageHeader title={t("erpRoles")} subtitle={t("erpRolesSub")}
        actions={<button className="btn btn-primary" onClick={() => { setFormError(null); setCreating(true); }}><Icon name="ph-plus" size={18} /> {t("erpNewRole")}</button>} />
      <Banner icon="ph-info">{t("erpRoleVoucherNote")}</Banner>

      <div className="erp-roles">
        <GlassCard pad={false} className="erp-roles-list">
          <ul className="erp-list">
            {roles.map((r) => (
              <li key={r.key}>
                <button type="button" className="erp-list-row" aria-current={r.key === selected ? "true" : undefined} onClick={() => choose(r)}>
                  <span className="erp-list-main">
                    <span className="erp-list-title">{r.name}</span>
                    <span className="erp-list-sub">{fill(t("erpPeople"), { n: r.users })} · {r.permissions.length}</span>
                  </span>
                  {!r.built_in ? <Badge tone="info">{t("erpCustomRole")}</Badge> : r.customised ? <Badge tone="warn">{t("erpCustomised")}</Badge> : null}
                </button>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard title={role.name} subtitle={role.locked ? t("erpAdminLocked") : role.description ?? (role.built_in ? t("erpBuiltIn") : t("erpCustomRole"))}
          action={!role.locked && <>
            {role.customised && <button className="btn btn-secondary btn-sm" disabled={busy} onClick={reset}>{role.built_in ? t("erpRestoreDefaults") : t("erpDelete")}</button>}
            <button className="btn btn-primary btn-sm" disabled={busy || !dirty} onClick={save}>{t("erpSaveChanges")}</button>
          </>}>
          <div className="erp-perm-groups">
            {groups.map(([group, perms]) => (
              <fieldset key={group} className="erp-perm-group" disabled={role.locked}>
                <legend>{group}</legend>
                {perms.map((p) => (
                  <label key={p.key} className="erp-check">
                    <input type="checkbox" checked={draft.includes(p.key)}
                      onChange={(e) => setDraft((d) => (e.target.checked ? [...d, p.key] : d.filter((x) => x !== p.key)))} />
                    <span>
                      <span className="erp-check-label">{p.label}</span>
                      <span className="erp-check-hint tnum">{p.key}</span>
                    </span>
                  </label>
                ))}
              </fieldset>
            ))}
          </div>
        </GlassCard>
      </div>

      <Dialog open={creating} title={t("erpNewRole")} onClose={() => setCreating(false)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setCreating(false)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={create} disabled={busy || !name.trim()}>{t("erpSave")}</button>
        </>}>
        <Field label={t("erpName")} htmlFor="r-name" required><input id="r-name" className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></Field>
        <Field label={t("erpDescription")} htmlFor="r-desc" hint={t("erpOptional")}><input id="r-desc" className="input" value={description} onChange={(e) => setDescription(e.target.value)} /></Field>
        {formError && <div className="field-error" role="alert">{formError}</div>}
      </Dialog>
    </div>
  );
}
