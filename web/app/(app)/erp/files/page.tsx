"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { DOC_TYPE_LABEL, type DocumentRow, fileIcon, fileSize, type FolderRow } from "@/lib/crm-types";
import { Banner, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, fill, FilterChips } from "@/components/erp-ui";
import { DropZone, uploadDocuments, useFileCheck } from "@/components/crm-attachments";
import { AccessEditor, type AccessValue } from "@/components/crm-doc-access";

export default function FilesPage() {
  return <ErpGate module="documents" permission="documents.view"><Files /></ErpGate>;
}

interface Browse {
  folder: FolderRow | null;
  breadcrumbs: { id: number; name: string }[];
  folders: FolderRow[];
  documents: Paginated<DocumentRow>;
}

type FolderForm = AccessValue & { name: string; description: string; retention_years: string };

function Files() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const check = useFileCheck();
  const initial = useQueryValue("folder");
  const [chosen, setFolder] = useState<number | null | undefined>(undefined);
  const folder = chosen !== undefined ? chosen : (Number(initial) || null);
  const [view, setView] = useState<"files" | "deleted">("files");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Browse | null>(null);
  const [deleted, setDeleted] = useState<Paginated<DocumentRow> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [expiring, setExpiring] = useState(0);
  const [folderForm, setFolderForm] = useState<{ editing: FolderRow | null; form: FolderForm } | null>(null);
  const [formError, setFormError] = useState<ApiError | null>(null);
  const manage = can("documents.manage");

  useEffect(() => { api.get<{ data: DocumentRow[] }>("/erp/files/expiring", { days: 30 }).then((r) => setExpiring(r.data.length)).catch(() => undefined); }, []);

  const load = useCallback(() => {
    setError(null);
    if (view === "deleted") {
      api.get<Paginated<DocumentRow>>("/erp/files/documents", { deleted: 1, q: q || undefined, page }).then(setDeleted).catch((e) => setError(e.message));
    } else {
      api.get<Browse>("/erp/files/browse", { folder_id: folder ?? undefined, q: q || undefined, page }).then(setData).catch((e) => setError(e.message));
    }
  }, [view, folder, q, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  function open(id: number | null) {
    setFolder(id); setPage(1); setQ("");
    window.history.replaceState(null, "", id ? `/erp/files?folder=${id}` : "/erp/files");
  }

  async function upload(files: File[]) {
    const { ok, rejected } = check(files);
    rejected.forEach((r) => toast(r, undefined, "bad"));
    if (!ok.length) return;
    setBusy(true);
    const { done, failed } = await uploadDocuments(ok, { folder_id: folder });
    failed.forEach((f) => toast(f, undefined, "bad"));
    if (done.length === 1 && ok.length === 1) { router.push(`/erp/files/${done[0].id}`); return; }
    if (done.length) toast(fill(t("docUploadedN"), { n: done.length }), undefined, "ok");
    setBusy(false);
    load();
  }

  function editFolder(f: FolderRow | null) {
    setFormError(null);
    setFolderForm({ editing: f, form: {
      name: f?.name ?? "", description: f?.description ?? "", retention_years: f?.retention_years ? String(f.retention_years) : "",
      access_scope: f?.access_scope ?? "company", access_roles: f?.access_roles ?? [], access_users: f?.access_users ?? [],
    } });
  }

  async function saveFolder() {
    if (!folderForm) return;
    const { editing, form } = folderForm;
    setBusy(true); setFormError(null);
    const payload = {
      name: form.name, description: form.description || null, retention_years: form.retention_years ? Number(form.retention_years) : null,
      access_scope: form.access_scope, access_roles: form.access_roles, access_users: form.access_users,
      ...(editing ? {} : { parent_id: folder }),
    };
    try {
      if (editing) await api.put(`/erp/files/folders/${editing.id}`, payload);
      else await api.post("/erp/files/folders", payload);
      toast(t("erpSaved"), form.name, "ok");
      setFolderForm(null); load();
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  async function deleteFolder(f: FolderRow) {
    setBusy(true); setFormError(null);
    try {
      await api.delete(`/erp/files/folders/${f.id}`);
      setFolderForm(null); open(f.parent_id);
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  async function restore(d: DocumentRow) {
    try { await api.post(`/erp/files/documents/${d.id}/restore`); toast(t("docRestore"), d.title, "ok"); load(); }
    catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); }
  }

  const docs = view === "deleted" ? deleted : data?.documents;

  return (
    <div className="erp-page">
      <PageHeader title={t("docTitle")} subtitle={t("docSub")}
        actions={<>
          <Link className="btn btn-secondary" href="/erp/files/expiring"><Icon name="ph-hourglass-medium" size={17} /> {t("docExpiring")}</Link>
          {manage && view === "files" && <button className="btn btn-secondary" onClick={() => editFolder(null)}><Icon name="ph-folder-plus" size={17} /> {t("docNewFolder")}</button>}
        </>} />

      {expiring > 0 && (
        <Banner tone="warn" icon="ph-hourglass-medium" action={<Link className="btn btn-secondary btn-sm" href="/erp/files/expiring">{t("docExpiring")}</Link>}>
          {fill(t("docExpiringBanner"), { n: expiring })}
        </Banner>
      )}

      <Toolbar end={manage && (
        <FilterChips<"files" | "deleted"> value={view} onChange={(v) => { setView(v); setPage(1); }} items={[
          { value: "files", label: t("docTitle") }, { value: "deleted", label: t("docShowDeleted") },
        ]} />
      )}>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("docSearch")} />
      </Toolbar>

      {view === "files" && (
        <nav className="doc-crumbs" aria-label={t("docFolder")}>
          <Link href="/erp/files" onClick={(e) => { e.preventDefault(); open(null); }}><Icon name="ph-house" size={15} /> {t("docHome")}</Link>
          {data?.breadcrumbs.map((c, i) => (
            <span key={c.id} className="erp-inline-icon">
              <Icon name="ph-caret-right" size={13} />
              {i === data.breadcrumbs.length - 1 ? <strong>{c.name}</strong> : <a href={`/erp/files?folder=${c.id}`} onClick={(e) => { e.preventDefault(); open(c.id); }}>{c.name}</a>}
            </span>
          ))}
          {manage && data?.folder && (
            <button className="btn btn-secondary btn-sm" style={{ marginLeft: "auto" }} onClick={() => editFolder(data.folder)}><Icon name="ph-gear" size={15} /> {t("docFolderSettings")}</button>
          )}
        </nav>
      )}

      {view === "files" && can("documents.upload") && <DropZone onFiles={upload} busy={busy} />}

      {error ? <ErrorState message={error} onRetry={load} /> : !docs ? <LoadingBlock /> : (
        <>
          {view === "files" && data && data.folders.length > 0 && (
            <div className="doc-folders">
              {data.folders.map((f) => (
                <a key={f.id} className="doc-folder" href={`/erp/files?folder=${f.id}`} onClick={(e) => { e.preventDefault(); open(f.id); }}>
                  <Icon name={f.access_scope === "company" ? "ph-folder" : "ph-folder-lock"} size={24} />
                  <span className="erp-list-main">
                    <span className="doc-folder-name">{f.name}</span>
                    <span className="erp-list-sub tnum">{f.documents_count ?? 0} · {t("docDocuments").toLowerCase()}</span>
                  </span>
                </a>
              ))}
            </div>
          )}

          {docs.data.length === 0 ? (
            (view === "deleted" || !data?.folders.length) && <EmptyState icon={view === "deleted" ? "ph-trash" : "ph-folder-open"} title={t(view === "deleted" ? "docNoDeleted" : "docEmptyFolder")} />
          ) : (
            <>
              <div className="vf-table-wrap">
                <table className="table vf-table">
                  <thead><tr><th>{t("docTitleField")}</th><th>{t("docType")}</th><th className="num">{t("docSize")}</th><th>{t("docExpires")}</th><th>{t("docUploaded")}</th>{view === "deleted" && <th />}</tr></thead>
                  <tbody>
                    {docs.data.map((d) => (
                      <tr key={d.id} className={view === "files" ? "is-clickable" : undefined} onClick={view === "files" ? () => router.push(`/erp/files/${d.id}`) : undefined}>
                        <td>
                          <span className="erp-inline-icon">
                            <Icon name={fileIcon(d.latest_version?.original_name)} size={20} />
                            <span className="erp-cell-link">
                              {view === "files" ? <Link href={`/erp/files/${d.id}`} className="erp-cell-title" onClick={(e) => e.stopPropagation()}>{d.title}</Link> : <span className="erp-cell-title">{d.title}</span>}
                              <span className="erp-cell-sub">{d.latest_version?.original_name}{d.current_version > 1 ? ` · v${d.current_version}` : ""}{d.folder && view === "deleted" ? ` · ${d.folder.name}` : ""}</span>
                            </span>
                          </span>
                        </td>
                        <td>{t(DOC_TYPE_LABEL[d.document_type] ?? "docTypeOther")}</td>
                        <td className="num">{d.latest_version ? fileSize(d.latest_version.size_bytes) : "-"}</td>
                        <td className="tnum">{d.expires_on ? formatDate(d.expires_on, locale) : "-"}</td>
                        <td>{formatDate(d.created_at, locale)}<span className="erp-cell-sub">{d.owner?.name}</span></td>
                        {view === "deleted" && <td><button className="btn btn-secondary btn-sm" onClick={() => restore(d)}><Icon name="ph-arrow-counter-clockwise" size={15} /> {t("docRestore")}</button></td>}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <Pagination page={docs.current_page} lastPage={docs.last_page} total={docs.total} onChange={setPage} />
            </>
          )}
        </>
      )}

      {folderForm && (
        <Dialog open wide title={folderForm.editing ? folderForm.editing.name : t("docNewFolder")} onClose={() => setFolderForm(null)} busy={busy}
          actions={<>
            {folderForm.editing && <button className="btn btn-danger" style={{ marginRight: "auto" }} disabled={busy} onClick={() => folderForm.editing && deleteFolder(folderForm.editing)}>{t("docDeleteFolder")}</button>}
            <button className="btn btn-secondary" onClick={() => setFolderForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={saveFolder} disabled={busy || !folderForm.form.name.trim()}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("docFolderName")} htmlFor="fd-name" required error={formError?.field("name")}>
              <input id="fd-name" className="input" value={folderForm.form.name} onChange={(e) => setFolderForm({ ...folderForm, form: { ...folderForm.form, name: e.target.value } })} />
            </Field>
            <Field label={t("docFolderRetention")} htmlFor="fd-ret" error={formError?.field("retention_years")}>
              <input id="fd-ret" className="input" type="number" min={1} max={100} value={folderForm.form.retention_years} onChange={(e) => setFolderForm({ ...folderForm, form: { ...folderForm.form, retention_years: e.target.value } })} />
            </Field>
          </div>
          <Field label={t("docDescription")} htmlFor="fd-desc" error={formError?.field("description")}>
            <input id="fd-desc" className="input" value={folderForm.form.description} onChange={(e) => setFolderForm({ ...folderForm, form: { ...folderForm.form, description: e.target.value } })} />
          </Field>
          <AccessEditor label={t("docFolderAccess")} value={folderForm.form} onChange={(v) => setFolderForm({ ...folderForm, form: { ...folderForm.form, ...v } })} />
          {formError?.field("access_users.0") && <div className="field-error">{formError.field("access_users.0")}</div>}
        </Dialog>
      )}
    </div>
  );
}
