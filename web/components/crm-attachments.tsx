"use client";

import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError, download, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { checkFile, DOC_ACCEPT, type DocumentRow, fileIcon, fileSize } from "@/lib/crm-types";
import { GlassCard, Icon } from "@/components/ui";
import { fill } from "@/components/erp-ui";

/*
 * Document management pieces other screens reuse: the authorised download,
 * the upload call, a drag-and-drop zone, and <RecordFiles>, the files panel
 * any module can put on a record page:
 *
 *   <RecordFiles type="customer" id={customer.id} />
 */

/** Fetches a version through the authorised endpoint and saves or opens it. */
export async function fetchDocument(id: number, name: string, opts: { version?: number; open?: boolean } = {}) {
  const blob = await download(`/erp/files/documents/${id}/download`, { version: opts.version, inline: opts.open ? 1 : undefined });
  if (opts.open) {
    const url = URL.createObjectURL(blob);
    window.open(url, "_blank", "noopener");
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } else {
    saveBlob(blob, name);
  }
}

/**
 * Uploads each file as its own document. Files the server would refuse are
 * reported by name before anything is sent.
 */
export async function uploadDocuments(files: File[], extra: Record<string, string | number | null | undefined>, links: { type: string; id: number }[] = []) {
  const done: DocumentRow[] = [];
  const failed: string[] = [];
  for (const file of files) {
    const form = new FormData();
    form.append("file", file, file.name);
    for (const [k, v] of Object.entries(extra)) if (v !== null && v !== undefined && v !== "") form.append(k, String(v));
    links.forEach((l, i) => { form.append(`links[${i}][type]`, l.type); form.append(`links[${i}][id]`, String(l.id)); });
    try {
      done.push((await api.upload<{ data: DocumentRow }>("/erp/files/documents", form)).data);
    } catch (e) {
      failed.push(`${file.name}: ${e instanceof ApiError ? (Object.values(e.errors)[0]?.[0] ?? e.message) : String(e)}`);
    }
  }
  return { done, failed };
}

/** Splits picked files into those the server accepts and translated reasons for the rest. */
export function useFileCheck() {
  const { t } = useApp();
  return (files: File[]) => {
    const ok: File[] = [];
    const rejected: string[] = [];
    for (const f of files) {
      const why = checkFile(f);
      if (why === "type") rejected.push(fill(t("docRejectedType"), { name: f.name }));
      else if (why === "size") rejected.push(fill(t("docRejectedSize"), { name: f.name }));
      else ok.push(f);
    }
    return { ok, rejected };
  };
}

/** A drop target with a "choose files" button; hands over a plain array of files. */
export function DropZone({ onFiles, busy, children }: { onFiles: (files: File[]) => void; busy?: boolean; children?: ReactNode }) {
  const { t } = useApp();
  const input = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);

  return (
    <div className="doc-drop" data-over={over ? "" : undefined}
      onDragOver={(e) => { e.preventDefault(); setOver(true); }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => { e.preventDefault(); setOver(false); const files = Array.from(e.dataTransfer.files); if (files.length) onFiles(files); }}>
      <Icon name={busy ? "ph-spinner" : "ph-cloud-arrow-up"} size={26} />
      <span>{busy ? t("docUploading") : t("docDropHere")}</span>
      <span className="erp-muted" style={{ fontSize: 13 }}>{t("docDropHint")}</span>
      <input ref={input} type="file" multiple accept={DOC_ACCEPT} hidden
        onChange={(e) => { const files = Array.from(e.target.files ?? []); e.target.value = ""; if (files.length) onFiles(files); }} />
      <button type="button" className="btn btn-secondary btn-sm" disabled={busy} onClick={() => input.current?.click()}>
        <Icon name="ph-upload-simple" size={15} /> {t("docUpload")}
      </button>
      {children}
    </div>
  );
}

/**
 * The documents linked to one record, with upload for those allowed to. The
 * list is limited server side to what the viewer may open.
 */
export function RecordFiles({ type, id, title }: { type: string; id: number; title?: string }) {
  const { t, locale, toast } = useApp();
  const { can, has } = useErp();
  const check = useFileCheck();
  const [rows, setRows] = useState<DocumentRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    api.get<{ data: DocumentRow[] }>("/erp/files/linked", { type, id }).then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, [type, id]);
  const enabled = has("documents") && can("documents.view");
  useEffect(() => { if (enabled) load(); }, [enabled, load]);

  if (!enabled) return null;

  async function upload(files: File[]) {
    const { ok, rejected } = check(files);
    rejected.forEach((r) => toast(r, undefined, "bad"));
    if (!ok.length) return;
    setBusy(true);
    const { done, failed } = await uploadDocuments(ok, {}, [{ type, id }]);
    failed.forEach((f) => toast(f, undefined, "bad"));
    if (done.length) toast(fill(t("docUploadedN"), { n: done.length }), undefined, "ok");
    setBusy(false);
    load();
  }

  async function get(doc: DocumentRow) {
    try { await fetchDocument(doc.id, doc.latest_version?.original_name ?? doc.title); }
    catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); }
  }

  return (
    <GlassCard title={title ?? t("docRecordFiles")} pad={false}>
      {can("documents.upload") && <div style={{ padding: "12px 12px 0" }}><DropZone onFiles={upload} busy={busy} /></div>}
      {error ? <p className="field-error" role="alert" style={{ padding: 12 }}>{error}</p> : !rows ? null : rows.length === 0 ? (
        <p className="erp-muted crm-empty">{t("docNoRecordFiles")}</p>
      ) : (
        <ul className="erp-list">
          {rows.map((d) => (
            <li key={d.id} className="crm-activity">
              <span className="erp-list-icon"><Icon name={fileIcon(d.latest_version?.original_name)} size={17} /></span>
              <a className="erp-list-main" href={`/erp/files/${d.id}`} style={{ color: "inherit", textDecoration: "none" }}>
                <span className="erp-list-title">{d.title}</span>
                <span className="erp-list-sub">
                  {d.latest_version ? fileSize(d.latest_version.size_bytes) : ""} · {formatDate(d.created_at, locale)}
                  {d.expires_on ? ` · ${t("docExpires")} ${formatDate(d.expires_on, locale)}` : ""}
                </span>
              </a>
              <button className="btn btn-secondary btn-sm" onClick={() => get(d)} aria-label={t("docDownload")}><Icon name="ph-download-simple" size={15} /></button>
            </li>
          ))}
        </ul>
      )}
    </GlassCard>
  );
}
