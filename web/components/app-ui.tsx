"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useId, useRef, useState, type ReactNode } from "react";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { Icon } from "@/components/ui";

/*
 * Primitives used only inside the signed-in application.
 *
 * They live apart from components/ui.tsx on purpose: that file is shared with
 * the public site, sign-in and registration, whose markup must not move. Every
 * visual decision here resolves to the semantic tokens in styles/app.css.
 */

/* ─────────────────────────────────────────────────────────── theme ── */

/**
 * The explicit appearance control: two labelled choices, not a mystery icon.
 * It drives the same preference as everywhere else — stored on the device
 * before first paint, and saved to the profile so it follows the person.
 */
export function ThemeSwitch({ compact }: { compact?: boolean }) {
  const { theme, toggleTheme, locale } = useApp();
  const sw = locale === "sw";
  const choose = (next: "light" | "dark") => { if (theme !== next) toggleTheme(); };

  return (
    <div className={`app-theme${compact ? " app-theme-compact" : ""}`} role="radiogroup" aria-label={sw ? "Mwonekano" : "Appearance"}>
      <button type="button" role="radio" aria-checked={theme === "light"} onClick={() => choose("light")} title={sw ? "Mwanga" : "Light"}>
        <Icon name="ph-sun" size={15} /> {!compact && <span>{sw ? "Mwanga" : "Light"}</span>}
      </button>
      <button type="button" role="radio" aria-checked={theme === "dark"} onClick={() => choose("dark")} title={sw ? "Giza" : "Dark"}>
        <Icon name="ph-moon" size={15} /> {!compact && <span>{sw ? "Giza" : "Dark"}</span>}
      </button>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────── menus ── */

/** Closes on outside click and Escape, and returns focus to its trigger. */
function useDismiss(open: boolean, close: () => void, root: React.RefObject<HTMLElement | null>) {
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (root.current && !root.current.contains(e.target as Node)) close(); };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") close(); };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => { document.removeEventListener("mousedown", onDown); document.removeEventListener("keydown", onKey); };
  }, [open, close, root]);
}

export function Dropdown({
  trigger, children, align = "end", placement = "below", label,
}: {
  trigger: (props: { open: boolean; toggle: () => void; id: string }) => ReactNode;
  children: (close: () => void) => ReactNode;
  align?: "start" | "end";
  placement?: "below" | "above";
  label?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const id = useId();
  const close = useCallback(() => setOpen(false), []);
  useDismiss(open, close, ref);

  return (
    <div className="app-dropdown" ref={ref}>
      {trigger({ open, toggle: () => setOpen((v) => !v), id })}
      {open && (
        <div id={id} className="app-menu" role="menu" aria-label={label} data-align={align} data-placement={placement}>
          {children(close)}
        </div>
      )}
    </div>
  );
}

export function MenuItem({ icon, children, onSelect, href, tone }: { icon?: string; children: ReactNode; onSelect?: () => void; href?: string; tone?: "danger" }) {
  const cls = `app-menu-item${tone === "danger" ? " is-danger" : ""}`;
  if (href) {
    return <Link role="menuitem" className={cls} href={href} onClick={onSelect}>{icon && <Icon name={icon} size={16} />}<span>{children}</span></Link>;
  }
  return <button type="button" role="menuitem" className={cls} onClick={onSelect}>{icon && <Icon name={icon} size={16} />}<span>{children}</span></button>;
}

export function MenuSeparator() {
  return <div className="app-menu-sep" role="separator" />;
}

export function MenuLabel({ children }: { children: ReactNode }) {
  return <div className="app-menu-label">{children}</div>;
}

/* ──────────────────────────────────────────────────── navigation parts ── */

export function Breadcrumb({ items }: { items: { label: string; href?: string }[] }) {
  return (
    <nav className="app-crumbs" aria-label="Breadcrumb">
      <ol>
        {items.map((item, index) => (
          <li key={`${item.label}-${index}`}>
            {item.href && index < items.length - 1 ? <Link href={item.href}>{item.label}</Link> : <span aria-current={index === items.length - 1 ? "page" : undefined}>{item.label}</span>}
          </li>
        ))}
      </ol>
    </nav>
  );
}

/** Underlined tabs for switching views of the same thing. */
export function Tabs<T extends string>({ value, onChange, items, label }: {
  value: T; onChange: (value: T) => void; label: string;
  items: { value: T; label: ReactNode; count?: number | null; icon?: string }[];
}) {
  return (
    <div className="app-tabs" role="tablist" aria-label={label}>
      {items.map((item) => (
        <button key={item.value} type="button" role="tab" aria-selected={value === item.value} onClick={() => onChange(item.value)}>
          {item.icon && <Icon name={item.icon} size={15} />}
          {item.label}
          {item.count != null && <span className="app-tabs-count">{item.count}</span>}
        </button>
      ))}
    </div>
  );
}

/** A bar of filters and actions that sits directly above a table. */
export function Toolbar({ children, end }: { children: ReactNode; end?: ReactNode }) {
  return (
    <div className="app-toolbar">
      <div className="app-toolbar-main">{children}</div>
      {end && <div className="app-toolbar-end">{end}</div>}
    </div>
  );
}

export function SearchInput({ value, onChange, placeholder, label }: { value: string; onChange: (v: string) => void; placeholder: string; label?: string }) {
  return (
    <label className="app-search">
      <Icon name="ph-magnifying-glass" size={15} />
      <input className="input" value={value} placeholder={placeholder} aria-label={label ?? placeholder} onChange={(e) => onChange(e.target.value)} />
      {value && <button type="button" className="app-search-clear" onClick={() => onChange("")} aria-label="Clear search"><Icon name="ph-x" size={13} /></button>}
    </label>
  );
}

/* ─────────────────────────────────────────────────────────── forms ── */

/** A titled group of fields: title and description on the left, fields on the right. */
export function FormSection({ title, description, children, aside }: { title: string; description?: ReactNode; children: ReactNode; aside?: ReactNode }) {
  return (
    <section className="app-form-section">
      <div className="app-form-section-head">
        <h3>{title}</h3>
        {description && <p>{description}</p>}
        {aside}
      </div>
      <div className="app-form-section-body">{children}</div>
    </section>
  );
}

/* ─────────────────────────────────────────────────────────── settings ── */

interface SettingsLink { href: string; label: MessageKey; icon: string; hash?: string }

const COMPANY_SETTINGS: { group: MessageKey; items: SettingsLink[] }[] = [
  { group: "companyProfile", items: [
    { href: "/settings", hash: "company", label: "companyProfile", icon: "ph-buildings" },
    { href: "/branding", label: "branding", icon: "ph-palette" },
    { href: "/subscription", label: "subscription", icon: "ph-crown-simple" },
  ] },
  { group: "approvalWorkflow", items: [
    { href: "/settings", hash: "workflow", label: "approvalWorkflow", icon: "ph-flow-arrow" },
    { href: "/settings", hash: "types", label: "voucherSettings", icon: "ph-receipt" },
  ] },
  { group: "employees", items: [
    { href: "/employees", label: "employees", icon: "ph-users-three" },
    { href: "/departments", label: "departments", icon: "ph-tree-structure" },
    { href: "/audit", label: "auditLogs", icon: "ph-scroll" },
  ] },
];

/**
 * Company administration as one area: a settings menu on the left, the chosen
 * page on the right. The pages keep their own routes and data; this only
 * gives them a common frame.
 */
export function SettingsLayout({ title, sub, children, actions }: { title: string; sub?: ReactNode; children: ReactNode; actions?: ReactNode }) {
  const { t, user } = useApp();
  const pathname = usePathname();
  const [hash, setHash] = useState("");

  useEffect(() => {
    const read = () => setHash(window.location.hash.replace("#", ""));
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, [pathname]);

  // Only a company administrator has the whole area; everyone else sees the page alone.
  if (user?.role !== "company_admin") {
    return (
      <div className="app-page">
        <header className="vf-pagehead">
          <div className="vf-pagehead-main">
            <h1 className="vf-pagehead-title">{title}</h1>
            {sub && <p className="vf-pagehead-sub">{sub}</p>}
          </div>
          {actions && <div className="vf-pagehead-actions">{actions}</div>}
        </header>
        {children}
      </div>
    );
  }

  const isActive = (item: SettingsLink) => {
    if (item.href !== pathname) return false;
    if (!item.hash) return true;
    return (hash || "workflow") === item.hash;
  };

  return (
    <div className="app-settings">
      <aside className="app-settings-nav" aria-label={t("settings")}>
        <div className="app-settings-nav-title">{t("settings")}</div>
        {COMPANY_SETTINGS.map((group) => (
          <div key={group.group} className="app-settings-group">
            {group.items.map((item) => (
              <Link key={`${item.href}#${item.hash ?? ""}`} href={item.hash ? `${item.href}#${item.hash}` : item.href}
                className="app-settings-link" aria-current={isActive(item) ? "page" : undefined}
                onClick={() => { if (item.hash) setHash(item.hash); }}>
                <Icon name={item.icon} size={16} />
                <span>{t(item.label)}</span>
              </Link>
            ))}
          </div>
        ))}
      </aside>
      <div className="app-settings-body">
        <header className="vf-pagehead">
          <div className="vf-pagehead-main">
            <h1 className="vf-pagehead-title">{title}</h1>
            {sub && <p className="vf-pagehead-sub">{sub}</p>}
          </div>
          {actions && <div className="vf-pagehead-actions">{actions}</div>}
        </header>
        {children}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────── money & figures ── */

/** A single labelled figure, used in summary strips and headers. */
export function Figure({ label, value, sub, tone }: { label: string; value: ReactNode; sub?: ReactNode; tone?: "ok" | "warn" | "bad" | "info" }) {
  return (
    <div className="app-figure" data-tone={tone}>
      <span className="app-figure-label">{label}</span>
      <span className="app-figure-value tnum">{value}</span>
      {sub && <span className="app-figure-sub">{sub}</span>}
    </div>
  );
}

export function FigureStrip({ children }: { children: ReactNode }) {
  return <div className="app-figures">{children}</div>;
}
