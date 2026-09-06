"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";
import { useApp } from "@/lib/app-context";

/* ────────────────────────────────────────────────────────── icon ────────── */

/** Phosphor duotone, loaded from the stylesheet in the root layout. */
export function Icon({ name, size = 18, color, style }: { name: string; size?: number; color?: string; style?: React.CSSProperties }) {
  return <i className={`ph-duotone ${name}`} aria-hidden="true" style={{ fontSize: size, color, lineHeight: 1, ...style }} />;
}

/* ───────────────────────────────────────────────────────── layout ───────── */

export function PageHeader({
  kicker, title, sub, actions,
}: { kicker?: string; title: ReactNode; sub?: ReactNode; actions?: ReactNode }) {
  return (
    <div style={{ display: "flex", alignItems: "flex-end", gap: "var(--space-4)", flexWrap: "wrap", marginBottom: "var(--space-6)" }}>
      <div style={{ minWidth: 0, flex: "1 1 320px" }}>
        {kicker && (
          <div style={{ fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
            {kicker}
          </div>
        )}
        <h1 style={{ fontSize: "clamp(26px, 3.4vw, 38px)", letterSpacing: "-.018em", margin: "8px 0 0" }}>{title}</h1>
        {sub && <p style={{ color: "var(--color-neutral-700)", fontSize: 16, margin: "6px 0 0", maxWidth: "68ch" }}>{sub}</p>}
      </div>
      {actions && <div style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap" }}>{actions}</div>}
    </div>
  );
}

export function SectionTitle({ children, actions }: { children: ReactNode; actions?: ReactNode }) {
  return (
    <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-3)", flexWrap: "wrap", margin: "0 0 var(--space-3)" }}>
      <h2 style={{ fontSize: 22, margin: 0 }}>{children}</h2>
      <div style={{ flex: 1 }} />
      {actions}
    </div>
  );
}

/** The design's rule-topped statistic block. */
export function StatBlock({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div style={{ borderTop: "2px solid var(--color-text)", paddingTop: 10 }}>
      <div style={{ fontSize: 12, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>{label}</div>
      <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 27, fontVariantNumeric: "tabular-nums", margin: "4px 0 2px", overflowWrap: "anywhere" }}>
        {value}
      </div>
      {sub && <div style={{ fontSize: 13, color: "var(--color-neutral-600)" }}>{sub}</div>}
    </div>
  );
}

export function StatGrid({ children }: { children: ReactNode }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))", gap: "var(--space-6)" }}>
      {children}
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
        {required && <span style={{ color: "var(--color-accent-2-700)" }} aria-hidden="true"> *</span>}
      </label>
      {children}
      {hint && !error && <div style={{ fontSize: 12, color: "var(--color-neutral-600)", marginTop: 4 }}>{hint}</div>}
      {error && <div className="field-error" role="alert">{error}</div>}
    </div>
  );
}

export function Tag({ kind = "tag-neutral", children }: { kind?: string; children: ReactNode }) {
  return <span className={`tag ${kind}`}>{children}</span>;
}

export function Spinner({ label }: { label?: string }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
      <span className="spinner" aria-hidden="true" />
      {label && <span>{label}</span>}
    </span>
  );
}

export function LoadingBlock({ rows = 4 }: { rows?: number }) {
  return (
    <div style={{ display: "grid", gap: 10 }} aria-busy="true" aria-live="polite">
      <span className="sr-only">Loading</span>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="skeleton" style={{ height: i === 0 ? 30 : 54 }} />
      ))}
    </div>
  );
}

export function EmptyState({
  icon = "ph-tray", title, body, action,
}: { icon?: string; title: string; body?: string; action?: ReactNode }) {
  return (
    <div style={{
      border: "1px dashed var(--color-neutral-400)", borderRadius: "var(--radius-md)",
      padding: "var(--space-8) var(--space-4)", textAlign: "center",
    }}>
      <Icon name={icon} size={30} color="var(--color-neutral-500)" />
      <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 19, marginTop: 10 }}>{title}</div>
      {body && <p style={{ color: "var(--color-neutral-700)", maxWidth: "46ch", margin: "6px auto 0", fontSize: 15 }}>{body}</p>}
      {action && <div style={{ marginTop: "var(--space-4)" }}>{action}</div>}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  const { t } = useApp();
  return (
    <div role="alert" style={{
      border: "1px solid var(--color-accent-2-400)", background: "var(--color-accent-2-100)",
      color: "var(--color-accent-2-800)", borderRadius: "var(--radius-md)", padding: "var(--space-3) var(--space-4)",
      display: "flex", alignItems: "center", gap: "var(--space-3)", flexWrap: "wrap",
    }}>
      <Icon name="ph-warning-circle" size={20} />
      <span style={{ flex: 1, minWidth: 200 }}>{message}</span>
      {onRetry && <button className="btn btn-secondary btn-sm" onClick={onRetry}>{t("retry")}</button>}
    </div>
  );
}

export function Banner({
  tone = "accent", icon, title, children, action,
}: { tone?: "accent" | "warn" | "danger"; icon?: string; title?: string; children?: ReactNode; action?: ReactNode }) {
  const palette = {
    accent: { border: "var(--color-accent-400)", bg: "var(--color-accent-100)", fg: "var(--color-accent-800)" },
    warn: { border: "var(--color-process-yellow)", bg: "color-mix(in srgb, var(--color-process-yellow) 16%, transparent)", fg: "var(--color-text)" },
    danger: { border: "var(--color-accent-2-400)", bg: "var(--color-accent-2-100)", fg: "var(--color-accent-2-800)" },
  }[tone];

  return (
    <div style={{
      border: `1px solid ${palette.border}`, background: palette.bg, color: palette.fg,
      borderRadius: "var(--radius-md)", padding: "var(--space-3) var(--space-4)",
      display: "flex", gap: "var(--space-3)", alignItems: "flex-start", flexWrap: "wrap",
      marginBottom: "var(--space-4)",
    }}>
      {icon && <Icon name={icon} size={20} />}
      <div style={{ flex: 1, minWidth: 220 }}>
        {title && <div style={{ fontWeight: 600 }}>{title}</div>}
        {children && <div style={{ fontSize: 14.5 }}>{children}</div>}
      </div>
      {action}
    </div>
  );
}

/* ───────────────────────────────────────────────────────── dialog ───────── */

export function Dialog({
  open, title, onClose, children, actions, wide,
}: { open: boolean; title: string; onClose: () => void; children: ReactNode; actions?: ReactNode; wide?: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    // Move focus into the dialog so keyboard users are not left behind it.
    const timer = window.setTimeout(() => {
      ref.current?.querySelector<HTMLElement>(
        "input, textarea, select, button:not([disabled]), canvas, [tabindex]",
      )?.focus();
    }, 30);
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      window.clearTimeout(timer);
      document.body.style.overflow = overflow;
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div ref={ref} className={`dialog${wide ? " dialog-wide" : ""}`} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--space-2)" }}>
          <div id={titleId} className="dialog-title" style={{ flex: 1 }}>{title}</div>
          <button className="btn btn-icon" onClick={onClose} aria-label="Close dialog">
            <Icon name="ph-x" />
          </button>
        </div>
        <div className="dialog-body" style={{ opacity: 1 }}>{children}</div>
        {actions && <div className="dialog-actions">{actions}</div>}
      </div>
    </div>
  );
}

/* ──────────────────────────────────────────────────────── toasts ────────── */

export function Toasts() {
  const { toasts, dismissToast } = useApp();

  return (
    <div
      aria-live="polite"
      style={{
        position: "fixed", right: "var(--space-4)", bottom: "var(--space-4)", zIndex: 200,
        display: "flex", flexDirection: "column", gap: "var(--space-2)", maxWidth: "min(380px, calc(100vw - 40px))",
      }}
    >
      {toasts.map((item) => {
        const colour = item.kind === "ok" ? "var(--color-accent-500)"
          : item.kind === "warn" ? "var(--color-process-yellow)" : "var(--color-accent-2-500)";
        const icon = item.kind === "ok" ? "ph-check-circle" : item.kind === "warn" ? "ph-clock" : "ph-x-circle";

        return (
          <div key={item.id} style={{
            display: "flex", gap: "var(--space-2)", alignItems: "flex-start",
            background: "var(--color-neutral-100)", border: "1px solid var(--color-divider)",
            borderLeft: `3px solid ${colour}`, borderRadius: "var(--radius-md)",
            boxShadow: "var(--shadow-lg)", padding: "var(--space-3)",
            animation: "vf-toast .18s ease-out",
          }}>
            <Icon name={icon} size={20} color={colour} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 600, fontSize: 14.5 }}>{item.title}</div>
              {item.body && <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)" }}>{item.body}</div>}
            </div>
            <button className="btn btn-icon" style={{ width: 24, height: 24 }} onClick={() => dismissToast(item.id)} aria-label="Dismiss">
              <Icon name="ph-x" size={13} />
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
    <div className="seg" role="group" aria-label="Language" style={{ flex: "none" }}>
      {(["en", "sw"] as const).map((code) => (
        <button
          key={code}
          onClick={() => setLocale(code)}
          aria-pressed={locale === code}
          style={{
            border: 0, cursor: "pointer", fontFamily: "var(--font-body)", fontSize: 12.5, fontWeight: 500,
            padding: "6px 11px", minWidth: 40,
            background: locale === code ? "var(--color-accent-500)" : "transparent",
            color: locale === code ? "#08222c" : "inherit",
          }}
        >
          {code.toUpperCase()}
        </button>
      ))}
    </div>
  );
}

export function ThemeToggle() {
  const { theme, toggleTheme } = useApp();
  return (
    <button className="btn btn-icon" onClick={toggleTheme} aria-label={theme === "light" ? "Switch to dark theme" : "Switch to light theme"} title="Theme">
      <Icon name={theme === "light" ? "ph-moon" : "ph-sun"} />
    </button>
  );
}

export function Pagination({
  page, lastPage, total, onChange,
}: { page: number; lastPage: number; total: number; onChange: (page: number) => void }) {
  const { t } = useApp();
  if (lastPage <= 1) return null;

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", marginTop: "var(--space-4)", flexWrap: "wrap" }}>
      <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)" }}>
        {t("showing")} {total} · {t("page")} {page} {t("of")} {lastPage}
      </div>
      <div style={{ flex: 1 }} />
      <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => onChange(page - 1)}>
        <Icon name="ph-caret-left" size={14} /> {t("back")}
      </button>
      <button className="btn btn-secondary btn-sm" disabled={page >= lastPage} onClick={() => onChange(page + 1)}>
        {t("next")} <Icon name="ph-caret-right" size={14} />
      </button>
    </div>
  );
}
