"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime } from "@/lib/format";
import {
  DOC_ACCEPT, DOC_TYPE_LABEL, DOC_TYPES, type DocumentDetail, fileIcon, fileSize, type FolderRow, LINK_LABEL, LINK_TYPES, linkHref,
} from "@/lib/crm-types";
import { Badge, Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { fetchDocument, useFileCheck } from "@/components/crm-attachments";
import { AccessEditor, type AccessValue } from "@/components/crm-doc-access";

export default function FilePage() {
  return <ErpGate module="documents" permission="documents.view"><FileDetail /></ErpGate>;
}

const ACTION_LABEL = { view: "docActionView", download: "docActionDownload", preview: "docActionPreview" } as const;

function FileDetail() {
  const { t, locale, toast, user } = useApp();
  const router = useRouter();
  const check = useFileCheck();
  const { id } = useParams<{ id: string }>();
  const versionInput = useRef<HTMLInputElement>(null);
  const [doc, setDoc] = useState<DocumentDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [folders, setFolders] = useState<FolderRow[]>([]);
  const [meta, setMeta] = useState<Record<string, string> | null>(null);
  const [access, setAccess] = useState<AccessValue | null>(null);
  const [retention, setRetention] = useState("");
  const [link, setLink] = useState({ type: "customer", id: "" });
  const [versionFile, setVersionFile] = useState<File | null>(null);
  const [versionNote, setVersionNote] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback((refresh = true) => {
    api.get<{ data: DocumentDetail }>(`/erp/files/documents/${id}`, { refresh: refresh ? 1 : undefined }).then((r) => {
      const d = r.data;
      setDoc(d);
      setMeta({
        title: d.title, document_type: d.document_type, tags: (d.tags ?? []).join(", "), reference: d.reference ?? "",
        issued_on: d.issued_on?.slice(0, 10) ?? "", expires_on: d.expires_on?.slice(0, 10) ?? "", description: d.description ?? "",
        folder_id: d.folder_id ? String(d.folder_id) : "",
      });
      setAccess({ access_scope: d.access_scope, access_roles: d.access_roles ?? [], access_users: d.access_users ?? [] });
      setRetention(d.retention_years ? String(d.retention_years) : "");
    }).catch((e) => setError(e.message));
  }, [id]);
  useEffect(() => load(false), [load]);
  useEffect(() => { api.get<{ data: FolderRow[] }>("/erp/files/folders").then((r) => setFolders(r.data)).catch(() => undefined); }, []);

  async function run(key: string, fn: () => Promise<unknown>, message?: string) {
    setBusy(key); setFormError(null);
    try { await fn(); if (message) toast(message, doc?.title, "ok"); load(); return true; }
    catch (e) { const err = e instanceof ApiError ? e : new ApiError(0, String(e)); setFormError(err); toast(err.message, undefined, "bad"); return false; }
    finally { setBusy(null); }
  }

  async function get(version?: number, open?: boolean) {
    if (!doc) return;
    const name = doc.versions?.find((v) => v.version === (version ?? doc.current_version))?.original_name ?? doc.title;
    try { await fetchDocument(doc.id, name, { version, open }); load(); } catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); }
  }

  if (error) return <ErrorState message={error} />;
  if (!doc || !meta || !access) return <LoadingBlock rows={6} />;

  const editor = doc.can.manage || (doc.can.upload && doc.created_by === user?.id);
  const current = doc.versions?.[0];
  const setM = (k: string, v: string) => setMeta({ ...meta, [k]: v });
  const daysLeft = doc.expires_on ? Math.round((new Date(doc.expires_on).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0)) / 86_400_000) : null;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href={doc.folder_id ? `/erp/files?folder=${doc.folder_id}` : "/erp/files"} className="erp-back"><Icon name="ph-arrow-left" size={16} /> {doc.breadcrumbs.map((b) => b.name).join(" / ") || t("docHome")}</Link>}
        kicker={t(DOC_TYPE_LABEL[doc.document_type] ?? "docTypeOther")}
        title={<span className="erp-inline-icon"><Icon name={fileIcon(current?.original_name)} size={32} /> {doc.title}</span>}
        subtitle={[current?.original_name, current ? fileSize(current.size_bytes) : null, fill(t("docVersion"), { n: doc.current_version })].filter(Boolean).join(" · ")}
        actions={<>
          {daysLeft !== null && daysLeft <= 30 && <Badge tone={daysLeft < 0 ? "bad" : "warn"} dot>{daysLeft < 0 ? t("docExpired") : fill(t("docDaysLeft"), { n: daysLeft })}</Badge>}
          {doc.retained && <Badge tone="info" dot>{t("docRetained")}</Badge>}
          <button className="btn btn-secondary" onClick={() => get(undefined, true)}><Icon name="ph-eye" size={17} /> {t("docOpen")}</button>
          <button className="btn btn-primary" onClick={() => get()}><Icon name="ph-download-simple" size={17} /> {t("docDownload")}</button>
          {doc.can.delete && <button className="btn btn-danger" onClick={() => setConfirmDelete(true)}><Icon name="ph-trash" size={17} /> {t("docDelete")}</button>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("docMeta")}>
          {formError && !Object.keys(formError.errors).length && busy === null && <div className="field-error" role="alert">{formError.message}</div>}
          <fieldset disabled={!editor} style={{ border: 0, padding: 0, margin: 0 }}>
            <div className="erp-form-grid">
              <Field label={t("docTitleField")} htmlFor="dm-title" error={formError?.field("title")}>
                <input id="dm-title" className="input" value={meta.title} onChange={(e) => setM("title", e.target.value)} />
              </Field>
              <Field label={t("docType")} htmlFor="dm-type" error={formError?.field("document_type")}>
                <select id="dm-type" className="input" value={meta.document_type} onChange={(e) => setM("document_type", e.target.value)}>
                  {DOC_TYPES.map((d) => <option key={d} value={d}>{t(DOC_TYPE_LABEL[d])}</option>)}
                </select>
              </Field>
              <Field label={t("docFolder")} htmlFor="dm-folder" error={formError?.field("folder_id")}>
                <select id="dm-folder" className="input" value={meta.folder_id} onChange={(e) => setM("folder_id", e.target.value)}>
                  <option value="">{t("docNoFolder")}</option>
                  {folders.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
                </select>
              </Field>
              <Field label={t("docReference")} htmlFor="dm-ref" error={formError?.field("reference")}>
                <input id="dm-ref" className="input" value={meta.reference} onChange={(e) => setM("reference", e.target.value)} />
              </Field>
              <Field label={t("docIssued")} htmlFor="dm-issued" error={formError?.field("issued_on")}>
                <input id="dm-issued" className="input" type="date" value={meta.issued_on} onChange={(e) => setM("issued_on", e.target.value)} />
              </Field>
              <Field label={t("docExpires")} htmlFor="dm-expires" error={formError?.field("expires_on")}>
                <input id="dm-expires" className="input" type="date" value={meta.expires_on} onChange={(e) => setM("expires_on", e.target.value)} />
              </Field>
            </div>
            <Field label={t("docTags")} htmlFor="dm-tags" hint={t("docTagsHint")} error={formError?.field("tags")}>
              <input id="dm-tags" className="input" value={meta.tags} onChange={(e) => setM("tags", e.target.value)} />
            </Field>
            <Field label={t("docDescription")} htmlFor="dm-desc" error={formError?.field("description")}>
              <textarea id="dm-desc" className="input" rows={3} value={meta.description} onChange={(e) => setM("description", e.target.value)} />
            </Field>
          </fieldset>
          {editor && (
            <button className="btn btn-primary" disabled={busy !== null || !meta.title.trim()} onClick={() => run("meta", () => api.put(`/erp/files/documents/${doc.id}`, {
              title: meta.title, document_type: meta.document_type, reference: meta.reference || null, description: meta.description || null,
              issued_on: meta.issued_on || null, expires_on: meta.expires_on || null, folder_id: meta.folder_id ? Number(meta.folder_id) : null,
              tags: meta.tags.split(",").map((s) => s.trim()).filter(Boolean),
            }), t("erpSaved"))}>{t("docSaveDetails")}</button>
          )}
        </GlassCard>

        <GlassCard title={t("docRetention")}>
          <dl className="erp-review">
            <dt>{t("docRetainUntil")}</dt><dd>{doc.retain_until ? formatDate(doc.retain_until, locale) : t("docNoRetention")}</dd>
            <dt>{t("docUploadedBy")}</dt><dd>{doc.creator?.name ?? "-"} · {formatDateTime(doc.created_at, locale)}</dd>
          </dl>
          {doc.can.manage && (
            <>
              <Field label={t("docRetentionYears")} htmlFor="dm-ret" hint={t("docRetentionHint")} error={formError?.field("retention_years")}>
                <input id="dm-ret" className="input" type="number" min={1} max={100} value={retention} onChange={(e) => setRetention(e.target.value)} />
              </Field>
              <button className="btn btn-secondary" disabled={busy !== null} onClick={() => run("ret", () => api.post(`/erp/files/documents/${doc.id}/retention`, { retention_years: retention ? Number(retention) : null }), t("erpSaved"))}>{t("erpSave")}</button>
            </>
          )}
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("docVersions")} pad={false}
          action={editor && <button className="btn btn-secondary btn-sm" onClick={() => versionInput.current?.click()}><Icon name="ph-upload-simple" size={15} /> {t("docNewVersion")}</button>}>
          <input ref={versionInput} type="file" accept={DOC_ACCEPT} hidden onChange={(e) => {
            const f = e.target.files?.[0]; e.target.value = "";
            if (!f) return;
            const { ok, rejected } = check([f]);
            rejected.forEach((r) => toast(r, undefined, "bad"));
            if (ok[0]) { setVersionFile(ok[0]); setVersionNote(""); }
          }} />
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("crmType")}</th><th>{t("docTitleField")}</th><th className="num">{t("docSize")}</th><th>{t("docUploaded")}</th><th /></tr></thead>
              <tbody>
                {doc.versions?.map((v) => (
                  <tr key={v.id}>
                    <td className="tnum">v{v.version}{v.version === doc.current_version && <> <Badge tone="ok">{t("docCurrent")}</Badge></>}</td>
                    <td>{v.original_name}{v.note && <span className="erp-cell-sub">{v.note}</span>}</td>
                    <td className="num">{fileSize(v.size_bytes)}</td>
                    <td>{formatDateTime(v.created_at, locale)}<span className="erp-cell-sub">{v.uploader?.name}</span></td>
                    <td><button className="btn btn-secondary btn-sm" onClick={() => get(v.version)} aria-label={t("docDownload")}><Icon name="ph-download-simple" size={15} /></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("docAccess")}>
          {doc.can.manage ? (
            <>
              <AccessEditor allowInherit label={t("docAccess")} value={access} onChange={setAccess} />
              <button className="btn btn-secondary" disabled={busy !== null} onClick={() => run("access", () => api.put(`/erp/files/documents/${doc.id}`, access), t("erpSaved"))}>{t("erpSave")}</button>
            </>
          ) : (
            <p className="erp-muted">{t(({ inherit: "docAccessInherit", company: "docAccessCompany", roles: "docAccessRoles", users: "docAccessUsers" } as const)[doc.access_scope])}</p>
          )}
        </GlassCard>

        <GlassCard title={t("docLinks")} pad={false}>
          {(doc.links ?? []).length === 0 ? <p className="erp-muted crm-empty">{t("docNoLinks")}</p> : (
            <ul className="erp-list">
              {doc.links?.map((l) => {
                const href = linkHref(l.attachable_type, l.attachable_id);
                const label = `${LINK_LABEL[l.attachable_type] ? t(LINK_LABEL[l.attachable_type]) : l.attachable_type} #${l.attachable_id}`;
                return (
                  <li key={l.id} className="crm-activity">
                    <span className="erp-list-icon"><Icon name="ph-link" size={16} /></span>
                    <span className="erp-list-main">{href ? <Link href={href}>{label}</Link> : <span>{label}</span>}</span>
                    {doc.can.upload && <button className="btn btn-secondary btn-sm" aria-label={t("docDelete")} onClick={() => run("unlink", () => api.delete(`/erp/files/documents/${doc.id}/links/${l.id}`))}><Icon name="ph-x" size={14} /></button>}
                  </li>
                );
              })}
            </ul>
          )}
          {doc.can.upload && (
            <div style={{ padding: "0 16px 16px" }}>
              <div className="erp-form-grid">
                <Field label={t("docLinkType")} htmlFor="ln-type">
                  <select id="ln-type" className="input" value={link.type} onChange={(e) => setLink({ ...link, type: e.target.value })}>
                    {LINK_TYPES.map((l) => <option key={l} value={l}>{t(LINK_LABEL[l])}</option>)}
                  </select>
                </Field>
                <Field label={t("docLinkId")} htmlFor="ln-id" error={formError?.field("id")}>
                  <input id="ln-id" className="input" type="number" min={1} value={link.id} onChange={(e) => setLink({ ...link, id: e.target.value })} />
                </Field>
              </div>
              <button className="btn btn-secondary" disabled={busy !== null || !link.id} onClick={async () => {
                if (await run("link", () => api.post(`/erp/files/documents/${doc.id}/links`, { type: link.type, id: Number(link.id) }), t("erpSaved"))) setLink({ ...link, id: "" });
              }}><Icon name="ph-link" size={15} /> {t("docAddLink")}</button>
            </div>
          )}
        </GlassCard>

        {doc.can.manage && (
          <GlassCard title={t("docAccessLog")} pad={false}>
            {doc.access_log.length === 0 ? <p className="erp-muted crm-empty">{t("docNoAccessLog")}</p> : (
              <ul className="erp-list">
                {doc.access_log.map((a) => (
                  <li key={a.id} className="crm-activity">
                    <span className="erp-list-main">
                      <span className="erp-list-title">{a.user?.name ?? "-"}</span>
                      <span className="erp-list-sub">{t(ACTION_LABEL[a.action as keyof typeof ACTION_LABEL] ?? "docActionView")}{a.version ? ` · v${a.version}` : ""} · {formatDateTime(a.created_at, locale)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </GlassCard>
        )}
      </div>

      <Dialog open={versionFile !== null} title={t("docNewVersion")} sub={versionFile?.name} onClose={() => setVersionFile(null)} busy={busy === "version"}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setVersionFile(null)} disabled={busy === "version"}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy !== null} onClick={async () => {
            if (!versionFile) return;
            const form = new FormData();
            form.append("file", versionFile, versionFile.name);
            if (versionNote) form.append("note", versionNote);
            if (await run("version", () => api.upload(`/erp/files/documents/${doc.id}/versions`, form), t("erpSaved"))) setVersionFile(null);
          }}>{t("docUpload")}</button>
        </>}>
        <Field label={t("docVersionNote")} htmlFor="vn-note">
          <input id="vn-note" className="input" value={versionNote} onChange={(e) => setVersionNote(e.target.value)} />
        </Field>
      </Dialog>

      <Dialog open={confirmDelete} icon="ph-trash" tone="warn" title={fill(t("docDeleteQ"), { title: doc.title })} sub={t("docDeleteSub")} onClose={() => setConfirmDelete(false)} busy={busy === "delete"}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirmDelete(false)} disabled={busy === "delete"}>{t("erpCancel")}</button>
          <button className="btn btn-danger" disabled={busy !== null} onClick={async () => {
            setBusy("delete");
            try { await api.delete(`/erp/files/documents/${doc.id}`); router.push(doc.folder_id ? `/erp/files?folder=${doc.folder_id}` : "/erp/files"); }
            catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); setBusy(null); setConfirmDelete(false); }
          }}>{t("docDelete")}</button>
        </>} />
    </div>
  );
}
