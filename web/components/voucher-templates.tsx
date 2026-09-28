"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { api, API_MODE } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Icon, Spinner } from "@/components/ui";
import type { VoucherTemplate } from "@/lib/types";

/**
 * Voucher designs on screen.
 *
 * Every document here is HTML rendered by the server from the same Blade
 * template DomPDF prints, so what is previewed, what is shown on a voucher and
 * what prints are one artefact. The browser only frames it: an A4 sheet in an
 * isolated iframe, scaled to whatever width the page gives it.
 */

/** A4 at 96 dpi — the width the server lays the sheet out for. */
const PAGE_W = 794;
const PAGE_H = 1123;

const COPY = {
  preview: ["Preview", "Hakiki"],
  select: ["Select", "Chagua"],
  selected: ["Selected", "Imechaguliwa"],
  current: ["Current", "Inayotumika"],
  useThis: ["Use this template", "Tumia kiolezo hiki"],
  close: ["Close", "Funga"],
  previous: ["Previous template", "Kiolezo kilichotangulia"],
  next: ["Next template", "Kiolezo kinachofuata"],
  loading: ["Preparing previews…", "Tunaandaa mwonekano…"],
  unavailable: ["Previews are unavailable right now.", "Mwonekano haupatikani kwa sasa."],
  of: ["of", "kati ya"],
} as const;

type Copy = keyof typeof COPY;

function useCopy() {
  const { locale } = useApp();
  return (key: Copy) => COPY[key][locale === "sw" ? 1 : 0];
}

export function templateName(template: Pick<VoucherTemplate, "name" | "name_sw"> | undefined, locale: string) {
  if (!template) return "—";
  return locale === "sw" ? template.name_sw : template.name;
}

/* ────────────────────────────────────────────────────────── the frame ── */

/**
 * The server's HTML document on an A4 sheet, scaled to fit its container.
 *
 * `fit="page"` shows exactly page one (thumbnails); `fit="content"` grows to
 * the whole document. The frame is sandboxed without scripts: it may be
 * measured and printed from here, and nothing inside it can run.
 */
export function DocumentFrame({
  html, fit = "content", title, onFrame, maxScale = 1,
}: {
  html: string;
  fit?: "page" | "content";
  title: string;
  onFrame?: (frame: HTMLIFrameElement | null) => void;
  maxScale?: number;
}) {
  const wrap = useRef<HTMLDivElement>(null);
  const frame = useRef<HTMLIFrameElement>(null);
  const [width, setWidth] = useState(0);
  const [contentHeight, setContentHeight] = useState(PAGE_H);

  useLayoutEffect(() => {
    const node = wrap.current;
    if (!node) return;
    const measure = () => setWidth(node.clientWidth);
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    onFrame?.(frame.current);
    return () => onFrame?.(null);
  }, [onFrame]);

  const measureContent = useCallback(() => {
    const doc = frame.current?.contentDocument;
    if (!doc) return;
    setContentHeight(Math.max(PAGE_H, doc.documentElement.scrollHeight));
  }, []);

  const scale = width ? Math.min(maxScale, width / PAGE_W) : 0;
  const height = fit === "page" ? PAGE_H : contentHeight;

  return (
    <div ref={wrap} className="vt-frame" style={{ height: scale ? height * scale : undefined, aspectRatio: scale ? undefined : `${PAGE_W} / ${PAGE_H}` }}>
      {scale > 0 && (
        <div className="vt-frame-page" style={{ width: PAGE_W * scale, height: height * scale }}>
          <iframe
            ref={frame}
            title={title}
            srcDoc={html}
            sandbox="allow-same-origin allow-modals"
            onLoad={measureContent}
            tabIndex={-1}
            style={{ width: PAGE_W, height, transform: `scale(${scale})` }}
          />
        </div>
      )}
    </div>
  );
}

/** Opens the browser's print dialog on a document frame's own contents. */
export function printFrame(frame: HTMLIFrameElement | null): boolean {
  const target = frame?.contentWindow;
  if (!target) return false;
  target.focus();
  target.print();
  return true;
}

/* ─────────────────────────────────────────────────────────── the data ── */

/** The designs on offer. Public, so registration can read it before sign-in. */
export function useTemplateCatalogue() {
  const [templates, setTemplates] = useState<VoucherTemplate[]>([]);
  const [defaultKey, setDefaultKey] = useState("classic");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    api.get<{ data: VoucherTemplate[]; default: string }>("/voucher-templates")
      .then((r) => {
        if (!live) return;
        if (Array.isArray(r?.data)) { setTemplates(r.data); setDefaultKey(r.default); } else setFailed(true);
      })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);

  return { templates, defaultKey, failed };
}

/**
 * Sample vouchers rendered by the server in each design.
 *
 * `body` is whatever brand the endpoint should render with; it is refetched
 * (debounced) when it changes. A logo the browser holds but the server does
 * not — a file chosen but not yet uploaded — travels as a placeholder the
 * server prints and this hook swaps for `logoSrc`.
 */
export function useTemplatePreviews(path: string | null, body: Record<string, unknown>, logoSrc: string | null = null) {
  const { locale } = useApp();
  const [raw, setRaw] = useState<{ previews: Record<string, string>; placeholder: string | null }>({ previews: {}, placeholder: null });
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const key = JSON.stringify({ path, body, locale, withLogo: !!logoSrc });

  useEffect(() => {
    if (!path) return;
    let live = true;
    const timer = window.setTimeout(() => {
      setLoading(true);
      api.post<{ data: { key: string; html: string }[]; logo_placeholder: string }>(path, { ...body, locale, with_logo: !!logoSrc })
        .then((r) => {
          if (!live) return;
          if (!Array.isArray(r?.data)) { setFailed(true); return; }
          setRaw({ previews: Object.fromEntries(r.data.map((p) => [p.key, p.html])), placeholder: r.logo_placeholder });
          setFailed(false);
        })
        .catch(() => { if (live) setFailed(true); })
        .finally(() => { if (live) setLoading(false); });
    }, 350);
    return () => { live = false; window.clearTimeout(timer); };
    // `key` carries every input; the objects themselves change identity each render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const previews = logoSrc && raw.placeholder
    ? Object.fromEntries(Object.entries(raw.previews).map(([k, html]) => [k, html.split(raw.placeholder!).join(logoSrc.replace(/"/g, "&quot;"))]))
    : raw.previews;

  return { previews, loading, failed };
}

/* ──────────────────────────────────────────────────────── the gallery ── */

/**
 * Every design as a real miniature voucher. Selecting is one click; the
 * larger preview is one more. On a phone the grid becomes a swipeable row.
 */
export function TemplateGallery({
  templates, previews, selected, current, onSelect, onPreview, loading, failed, disabled,
}: {
  templates: VoucherTemplate[];
  previews: Record<string, string>;
  selected: string | null;
  /** The design in use now, when it differs from the selection. */
  current?: string | null;
  onSelect?: (key: string) => void;
  onPreview: (key: string) => void;
  loading?: boolean;
  failed?: boolean;
  disabled?: boolean;
}) {
  const { locale } = useApp();
  const c = useCopy();

  if (failed && !Object.keys(previews).length) {
    return <div className="vt-empty"><Icon name="ph-warning-circle" size={18} /> {c("unavailable")}</div>;
  }

  return (
    <div className="vt-gallery" role="radiogroup" aria-busy={loading || undefined}>
      {templates.map((template) => {
        const isSelected = selected === template.key;
        const html = previews[template.key];
        const name = templateName(template, locale);
        return (
          <div key={template.key} className="vt-card" data-selected={isSelected || undefined}>
            <button type="button" className="vt-thumb" onClick={() => onPreview(template.key)} aria-label={`${c("preview")}: ${name}`}>
              {html
                ? <DocumentFrame html={html} fit="page" title={name} />
                : <span className="vt-thumb-skeleton" aria-hidden="true" />}
              {isSelected && <span className="vt-badge vt-badge-selected"><Icon name="ph-check" size={12} /> {c("selected")}</span>}
              {current === template.key && !isSelected && <span className="vt-badge">{c("current")}</span>}
              <span className="vt-thumb-zoom" aria-hidden="true"><Icon name="ph-magnifying-glass-plus" size={16} /></span>
            </button>
            <div className="vt-meta">
              <span className="vt-num tnum">{String(template.number).padStart(2, "0")}</span>
              <strong>{name}</strong>
              <p>{locale === "sw" ? template.description_sw : template.description}</p>
            </div>
            <div className="vt-actions">
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => onPreview(template.key)}>
                <Icon name="ph-eye" size={14} /> {c("preview")}
              </button>
              {onSelect && (
                <button type="button" role="radio" aria-checked={isSelected}
                  className={`btn btn-sm ${isSelected ? "btn-ghost vt-is-selected" : "btn-primary"}`}
                  onClick={() => onSelect(template.key)} disabled={disabled || isSelected}>
                  {isSelected ? <><Icon name="ph-check-circle" size={15} /> {c("selected")}</> : c("select")}
                </button>
              )}
            </div>
          </div>
        );
      })}
      {loading && !Object.keys(previews).length && (
        <div className="vt-loading"><Spinner label={c("loading")} /></div>
      )}
    </div>
  );
}

/* ───────────────────────────────────────────────────────── the dialog ── */

/**
 * One design at full size, with its neighbours a keystroke away.
 * `actionLabel` / `onUse` let a caller turn "Use this template" into
 * "Change to this template" or hide it entirely (a read-only look).
 */
export function TemplatePreviewDialog({
  open, templates, previews, active, onNavigate, onClose, onUse, selected, actionLabel, busy, footerNote,
}: {
  open: boolean;
  templates: VoucherTemplate[];
  previews: Record<string, string>;
  active: string | null;
  onNavigate: (key: string) => void;
  onClose: () => void;
  onUse?: (key: string) => void;
  selected?: string | null;
  actionLabel?: string;
  busy?: boolean;
  footerNote?: React.ReactNode;
}) {
  const { locale } = useApp();
  const c = useCopy();
  const index = templates.findIndex((t) => t.key === active);
  const template = index >= 0 ? templates[index] : undefined;

  const step = useCallback((delta: number) => {
    if (!templates.length || index < 0) return;
    onNavigate(templates[(index + delta + templates.length) % templates.length].key);
  }, [templates, index, onNavigate]);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onClose();
      if (event.key === "ArrowRight") step(1);
      if (event.key === "ArrowLeft") step(-1);
    };
    document.addEventListener("keydown", onKey);
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    return () => { document.removeEventListener("keydown", onKey); document.body.style.overflow = overflow; };
  }, [open, busy, onClose, step]);

  if (!open || !template) return null;

  const name = templateName(template, locale);
  const html = previews[template.key];
  const isSelected = selected === template.key;

  return (
    <div className="vt-modal" role="dialog" aria-modal="true" aria-label={name} onMouseDown={(e) => { if (e.target === e.currentTarget && !busy) onClose(); }}>
      <div className="vt-modal-card">
        <header className="vt-modal-head">
          <div className="vt-modal-title">
            <span className="vt-num tnum">{String(template.number).padStart(2, "0")} {c("of")} {String(templates.length).padStart(2, "0")}</span>
            <h2>{name}</h2>
            <p>{locale === "sw" ? template.description_sw : template.description}</p>
          </div>
          <button type="button" className="btn btn-ghost btn-sm vt-modal-close" onClick={onClose} disabled={busy} aria-label={c("close")}>
            <Icon name="ph-x" size={18} />
          </button>
        </header>

        <div className="vt-modal-body">
          <button type="button" className="vt-nav vt-nav-prev" onClick={() => step(-1)} aria-label={c("previous")}><Icon name="ph-caret-left" size={20} /></button>
          <div className="vt-modal-sheet">
            {html ? <DocumentFrame html={html} fit="content" title={name} /> : <div className="vt-loading"><Spinner label={c("loading")} /></div>}
          </div>
          <button type="button" className="vt-nav vt-nav-next" onClick={() => step(1)} aria-label={c("next")}><Icon name="ph-caret-right" size={20} /></button>
        </div>

        <footer className="vt-modal-foot">
          <div className="vt-modal-note">{footerNote}</div>
          <div className="vt-modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose} disabled={busy}>{c("close")}</button>
            {onUse && (
              <button type="button" className="btn btn-primary" onClick={() => onUse(template.key)} disabled={busy || isSelected}>
                {busy ? <Spinner /> : isSelected ? <><Icon name="ph-check-circle" size={16} /> {c("selected")}</> : <><Icon name="ph-check" size={16} /> {actionLabel ?? c("useThis")}</>}
              </button>
            )}
          </div>
        </footer>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────── a real voucher's document ── */

/**
 * Fetches a server-rendered document and keeps it current. GET for a saved
 * voucher; POST (debounced) for a draft still being typed.
 */
function useServerDocument(path: string, refreshKey: string, body?: Record<string, unknown>) {
  const [html, setHtml] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const bodyKey = body ? JSON.stringify(body) : "";

  useEffect(() => {
    let live = true;
    const timer = window.setTimeout(() => {
      const call = body
        ? api.post<{ html: string }>(path, body)
        : api.get<{ html: string }>(path);
      call
        .then((r) => {
          if (!live) return;
          if (typeof r?.html === "string") { setHtml(r.html); setFailed(false); } else setFailed(true);
        })
        .catch(() => { if (live) setFailed(true); });
    }, body ? 400 : 0);
    return () => { live = false; window.clearTimeout(timer); };
    // bodyKey and refreshKey carry every input.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, refreshKey, bodyKey]);

  return { html, failed };
}

/**
 * A saved voucher, in the design it was issued in — the same HTML the PDF
 * prints. `fallback` renders when the server cannot (the offline mock).
 */
export function VoucherDocumentView({ voucherId, refreshKey, fallback, onFrame }: {
  voucherId: number;
  /** Anything that changes when the document would: status, timestamps, files. */
  refreshKey: string;
  fallback: React.ReactNode;
  onFrame?: (frame: HTMLIFrameElement | null) => void;
}) {
  const { locale } = useApp();
  const { html, failed } = useServerDocument(`/vouchers/${voucherId}/document`, `${refreshKey}|${locale}`);

  if (API_MODE === "mock" || (failed && !html)) return <>{fallback}</>;
  if (!html) return <div className="vt-document"><span className="vt-thumb-skeleton" aria-hidden="true" /></div>;

  return (
    <div className="vt-document">
      <DocumentFrame html={html} fit="content" title={`Voucher ${voucherId}`} onFrame={onFrame} />
    </div>
  );
}

/** A voucher still being written, shown in the company's design as it will print. */
export function DraftDocumentView({ draft, fallback }: { draft: Record<string, unknown>; fallback: React.ReactNode }) {
  const { locale } = useApp();
  const { html, failed } = useServerDocument("/vouchers/document-preview", locale, draft);

  if (API_MODE === "mock" || (failed && !html)) return <>{fallback}</>;
  if (!html) return <div className="vt-document"><span className="vt-thumb-skeleton" aria-hidden="true" /></div>;

  return (
    <div className="vt-document">
      <DocumentFrame html={html} fit="content" title="Voucher preview" />
    </div>
  );
}
