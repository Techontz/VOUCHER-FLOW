"use client";

import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { useApp } from "@/lib/app-context";

/*
 * VouchFlow's shared primitives.
 *
 * Every export here keeps the props it had before the redesign, so the screens
 * that use them move onto the new design system without being touched. New,
 * optional props (tone, icon, summary, href …) are additive.
 *
 * Visual treatment lives in styles/vouchflow.css, not in inline styles. A
 * component that needs a colour asks for a tone, and the tone decides.
 */

export type Tone = "neutral" | "info" | "warn" | "ok" | "bad";

/* ────────────────────────────────────────────────────────── icon ────────── */

/**
 * Phosphor, regular weight by default. Duotone read as decorative against a
 * finance screen; a single stroke weight is calmer and scans faster. `fill` is
 * for the few places that want emphasis — a completed step, a success toast.
 */
export function Icon({
  name, size = 18, color, style, weight = "regular",
}: { name: string; size?: number; color?: string; style?: React.CSSProperties; weight?: "regular" | "fill" }) {
  const base = weight === "fill" ? "ph-fill" : "ph";
  return <i className={`${base} ${name}`} aria-hidden="true" style={{ fontSize: size, color, lineHeight: 1, ...style }} />;
}

/* ───────────────────────────────────────────────────────── layout ───────── */

export function PageHeader({
  kicker, title, sub, actions, back,
}: { kicker?: string; title: ReactNode; sub?: ReactNode; actions?: ReactNode; back?: ReactNode }) {
  return (
    <header className="vf-pagehead">
      <div className="vf-pagehead-main">
        {back}
        {kicker && <div className="vf-eyebrow">{kicker}</div>}
        <h1 className="vf-pagehead-title">{title}</h1>
        {sub && <p className="vf-pagehead-sub">{sub}</p>}
      </div>
      {actions && <div className="vf-pagehead-actions">{actions}</div>}
    </header>
  );
}

export function SectionTitle({ children, actions, count }: { children: ReactNode; actions?: ReactNode; count?: number | null }) {
  return (
    <div className="vf-sectiontitle">
      <h2>
        {children}
        {count != null && <span className="vf-count">{count}</span>}
      </h2>
      {actions && <div className="vf-sectiontitle-actions">{actions}</div>}
    </div>
  );
}

export interface Kpi {
  label: string;
  value: string;
  sub?: string | null;
  icon?: string;
  trend?: string | null;
  up?: boolean | null;
  /** Colours the icon chip. Leave neutral unless the number is a call to act. */
  tone?: Tone;
  /** Makes the whole card a link to the list behind the number. */
  href?: string;
}

export function StatBlock({ label, value, sub, icon = "ph-chart-bar", trend, up, tone = "neutral", href }: Kpi) {
  const body = (
    <>
      <div className="vf-kpi-top">
        <span className="vf-kpi-label">{label}</span>
        <span className={`vf-kpi-icon tone-${tone}`}><Icon name={icon} /></span>
      </div>
      <div className="vf-kpi-value">{value}</div>
      {(trend || sub) && (
        <div className="vf-kpi-foot">
          {trend && (
            <span className={`vf-trend ${up ? "vf-trend-up" : "vf-trend-down"}`}>
              <Icon name={up ? "ph-trend-up" : "ph-trend-down"} size={13} /> {trend}
            </span>
          )}
          {sub && <span className="vf-kpi-sub">{sub}</span>}
        </div>
      )}
    </>
  );

  return href
    ? <a className="vf-kpi" href={href}>{body}</a>
    : <div className="vf-kpi">{body}</div>;
}

export function StatGrid({ children }: { children: ReactNode }) {
  return <div className="vf-kpis">{children}</div>;
}

/** Renders a dashboard's stat array straight from the API payload. */
export function KpiRow({ stats }: { stats: Kpi[] }) {
  return (
    <div className="vf-kpis">
      {stats.map((stat) => <StatBlock key={stat.label} {...stat} />)}
    </div>
  );
}

export function Panel({
  title, sub, actions, children, pad = true, style,
}: { title?: ReactNode; sub?: ReactNode; actions?: ReactNode; children: ReactNode; pad?: boolean; style?: React.CSSProperties }) {
  return (
    <section className="vf-panel" style={style}>
      {(title || actions) && (
        <div className="vf-panel-head">
          <div className="vf-panel-head-main">
            {title && <h2>{title}</h2>}
            {sub && <div className="vf-panel-sub">{sub}</div>}
          </div>
          {actions && <div className="vf-panel-actions">{actions}</div>}
        </div>
      )}
      <div className={pad ? "vf-panel-pad" : undefined}>{children}</div>
    </section>
  );
}

/** A quiet callout for scope, isolation and workflow notes. */
export function Note({ children, tone }: { children: ReactNode; tone?: "warn" }) {
  return (
    <div className={`vf-note${tone === "warn" ? " vf-note-warn" : ""}`}>
      <Icon name={tone === "warn" ? "ph-warning" : "ph-info"} size={17} style={{ marginTop: 1, flex: "none" }} />
      <div>{children}</div>
    </div>
  );
}

/** A large selectable option card — voucher format, plan, payment method. */
export function Choice({
  selected, onSelect, icon, label, sub,
}: { selected: boolean; onSelect: () => void; icon: string; label: string; sub?: string }) {
  return (
    <button type="button" className="vf-choice" aria-pressed={selected} onClick={onSelect}>
      <span className="vf-choice-icon"><Icon name={icon} size={20} /></span>
      <span className="vf-choice-text">
        <span className="vf-choice-label">{label}</span>
        {sub && <span className="vf-choice-sub">{sub}</span>}
      </span>
      <span className="vf-choice-check" aria-hidden="true">
        <Icon name={selected ? "ph-check-circle" : "ph-circle"} size={20} weight={selected ? "fill" : "regular"} />
      </span>
    </button>
  );
}

/** Usage meter for plan limits. */
export function Meter({ percent, exceeded }: { percent: number | null; exceeded?: boolean }) {
  return (
    <div className="vf-meter" data-exceeded={exceeded ? "true" : undefined}
      role="progressbar" aria-valuenow={percent ?? 0} aria-valuemin={0} aria-valuemax={100}>
      <span style={{ width: `${Math.min(100, Math.max(2, percent ?? 0))}%` }} />
    </div>
  );
}

export function Field({
  label, htmlFor, error, hint, children, required,
}: { label: string; htmlFor?: string; error?: string; hint?: string; children: ReactNode; required?: boolean }) {
  return (
    <div className="field">
      <label htmlFor={htmlFor}>
        {label}
        {required && <span className="vf-required" aria-hidden="true"> *</span>}
      </label>
      {children}
      {hint && !error && <div className="field-hint">{hint}</div>}
      {error && (
        <div className="field-error" role="alert">
          <Icon name="ph-warning-circle" size={15} /> {error}
        </div>
      )}
    </div>
  );
}

export function Tag({ kind = "tag-neutral", children }: { kind?: string; children: ReactNode }) {
  return <span className={`badge ${kind}`}>{children}</span>;
}

export function Spinner({ label }: { label?: string }) {
  return (
    <span className="vf-spinner-row">
      <span className="spinner" aria-hidden="true" />
      {label && <span>{label}</span>}
    </span>
  );
}

/** Placeholder rows shaped like the content they stand in for. */
export function LoadingBlock({ rows = 4 }: { rows?: number }) {
  return (
    <div className="vf-loading" aria-busy="true" aria-live="polite">
      <span className="sr-only">Loading</span>
      <div className="skeleton" style={{ height: 26, width: "38%" }} />
      {Array.from({ length: Math.max(1, rows - 1) }).map((_, i) => (
        <div key={i} className="skeleton" style={{ height: 58 }} />
      ))}
    </div>
  );
}

export function EmptyState({
  icon = "ph-tray", title, body, action, tone,
}: { icon?: string; title: string; body?: string; action?: ReactNode; tone?: "ok" | "bad" }) {
  return (
    <div className="vf-empty">
      <div className={`vf-empty-icon${tone ? ` tone-${tone}` : ""}`}><Icon name={icon} size={24} /></div>
      <div className="vf-empty-title">{title}</div>
      {body && <p className="vf-empty-body">{body}</p>}
      {action && <div className="vf-empty-actions">{action}</div>}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  const { t } = useApp();
  return (
    <div role="alert" className="vf-alert tone-bad">
      <Icon name="ph-warning-circle" size={20} style={{ flex: "none" }} />
      <span className="vf-alert-text">{message}</span>
      {onRetry && <button className="btn btn-secondary btn-sm" onClick={onRetry}>{t("retry")}</button>}
    </div>
  );
}

export function Banner({
  tone = "accent", icon, title, children, action,
}: { tone?: "accent" | "warn" | "danger"; icon?: string; title?: string; children?: ReactNode; action?: ReactNode }) {
  const mapped = tone === "warn" ? "warn" : tone === "danger" ? "bad" : "info";
  return (
    <div className={`vf-alert tone-${mapped}`} style={{ marginBottom: "var(--space-4)" }}>
      {icon && <Icon name={icon} size={20} style={{ flex: "none", marginTop: 1 }} />}
      <div className="vf-alert-text">
        {title && <div className="vf-alert-title">{title}</div>}
        {children && <div>{children}</div>}
      </div>
      {action}
    </div>
  );
}

/* ───────────────────────────────────────────────────────── dialog ───────── */

export interface SummaryRow {
  label: string;
  value: ReactNode;
}

/**
 * A modal dialog, and the confirmation pattern for consequential actions.
 *
 * Give it an `icon` and a `tone` and it opens with a mark that says what kind
 * of act this is; give it a `summary` and it restates exactly what is being
 * acted on — voucher, amount, method — so nobody approves the wrong thing.
 */
export function Dialog({
  open, title, onClose, children, actions, wide, sub, icon, tone = "info", summary, busy,
}: {
  open: boolean;
  title: string;
  onClose: () => void;
  children?: ReactNode;
  actions?: ReactNode;
  wide?: boolean;
  sub?: ReactNode;
  icon?: string;
  tone?: Tone;
  summary?: SummaryRow[];
  /** While an action is in flight, closing would orphan it. */
  busy?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const safeClose = busy ? () => undefined : onClose;

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onClose();
    };
    document.addEventListener("keydown", onKey);
    // Focus the first real control, not the close button — keyboard users land
    // where the decision is.
    const timer = window.setTimeout(() => {
      const root = ref.current;
      const target = root?.querySelector<HTMLElement>(".dialog-body input, .dialog-body textarea, .dialog-body select, .dialog-body canvas")
        ?? root?.querySelector<HTMLElement>(".dialog-actions .btn-secondary, .dialog-actions button:not([disabled])");
      target?.focus();
    }, 40);
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      window.clearTimeout(timer);
      document.body.style.overflow = overflow;
    };
  }, [open, onClose, busy]);

  if (!open) return null;

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) safeClose();
      }}
    >
      <div ref={ref} className={`dialog${wide ? " dialog-wide" : ""}`} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <div className="dialog-head">
          <div className="dialog-head-row">
            <div style={{ minWidth: 0, flex: 1 }}>
              {icon && <div className={`dialog-icon tone-${tone}`}><Icon name={icon} size={22} /></div>}
              <div id={titleId} className="dialog-title">{title}</div>
              {sub && <div className="dialog-sub">{sub}</div>}
            </div>
            <button className="btn btn-icon btn-sm dialog-close" onClick={safeClose} aria-label="Close dialog" disabled={busy}>
              <Icon name="ph-x" size={16} />
            </button>
          </div>
          {summary && summary.length > 0 && (
            <dl className="dialog-summary">
              {summary.map((row) => (
                <div key={row.label} className="dialog-summary-row">
                  <dt>{row.label}</dt>
                  <dd>{row.value}</dd>
                </div>
              ))}
            </dl>
          )}
        </div>
        {children ? <div className="dialog-body">{children}</div> : <div style={{ height: 20 }} />}
        {actions && <div className="dialog-actions">{actions}</div>}
      </div>
    </div>
  );
}

/* ──────────────────────────────────────────────────────── toasts ────────── */

export function Toasts() {
  const { toasts, dismissToast } = useApp();

  return (
    <div className="vf-toasts" aria-live="polite">
      {toasts.map((item) => {
        const tone = item.kind === "ok" ? "ok" : item.kind === "warn" ? "warn" : "bad";
        const icon = item.kind === "ok" ? "ph-check-circle" : item.kind === "warn" ? "ph-info" : "ph-warning-circle";

        return (
          <div key={item.id} className={`vf-toast tone-${tone}`} role={tone === "bad" ? "alert" : "status"}>
            <Icon name={icon} size={20} weight="fill" style={{ flex: "none" }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="vf-toast-title">{item.title}</div>
              {item.body && <div className="vf-toast-body">{item.body}</div>}
            </div>
            <button className="btn btn-icon btn-sm" onClick={() => dismissToast(item.id)} aria-label="Dismiss">
              <Icon name="ph-x" size={14} />
            </button>
          </div>
        );
      })}
    </div>
  );
}

/* ─────────────────────────────────────────────────────── controls ───────── */

export function LanguageToggle() {
  const { locale, setLocale } = useApp();

  return (
    <div className="seg seg-sm" role="group" aria-label="Language">
      {(["en", "sw"] as const).map((code) => (
        <button key={code} type="button" onClick={() => setLocale(code)} aria-selected={locale === code}>
          {code.toUpperCase()}
        </button>
      ))}
    </div>
  );
}

export function ThemeToggle() {
  const { theme, toggleTheme } = useApp();
  return (
    <button className="btn btn-icon" onClick={toggleTheme}
      aria-label={theme === "light" ? "Switch to dark theme" : "Switch to light theme"}
      title={theme === "light" ? "Dark theme" : "Light theme"}>
      <Icon name={theme === "light" ? "ph-moon" : "ph-sun"} size={19} />
    </button>
  );
}

export function Pagination({
  page, lastPage, total, onChange,
}: { page: number; lastPage: number; total: number; onChange: (page: number) => void }) {
  const { t } = useApp();
  if (lastPage <= 1) return null;

  return (
    <nav className="vf-pagination" aria-label="Pagination">
      <div className="vf-pagination-info">
        {t("showing")} {total} · {t("page")} {page} {t("of")} {lastPage}
      </div>
      <div className="vf-pagination-controls">
        <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => onChange(page - 1)}>
          <Icon name="ph-caret-left" size={14} /> {t("back")}
        </button>
        <button className="btn btn-secondary btn-sm" disabled={page >= lastPage} onClick={() => onChange(page + 1)}>
          {t("next")} <Icon name="ph-caret-right" size={14} />
        </button>
      </div>
    </nav>
  );
}

/**
 * A collapsible secondary section.
 *
 * Attachments, comments and the audit trail matter, but they are not the
 * decision. They sit here, one line each until asked for, and never print.
 */
export function Disclosure({
  title, count, icon, children, defaultOpen = false,
}: {
  title: string;
  count?: number | null;
  icon?: string;
  children: ReactNode;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const id = useId();

  return (
    <section className="vf-panel vf-disclosure no-print">
      <button type="button" className="vf-disclosure-head" onClick={() => setOpen((v) => !v)} aria-expanded={open} aria-controls={id}>
        {icon && <Icon name={icon} size={18} style={{ color: "var(--color-neutral-600)" }} />}
        <span className="vf-disclosure-title">{title}</span>
        {count != null && count > 0 && <span className="vf-count">{count}</span>}
        <Icon name="ph-caret-down" size={16} style={{ color: "var(--color-neutral-600)", transform: open ? "rotate(180deg)" : "none", transition: "transform var(--dur) var(--ease-out)" }} />
      </button>
      <div id={id} hidden={!open} className="vf-disclosure-body">
        {children}
      </div>
    </section>
  );
}
