"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { NAV_GROUP_LABEL, mobileNavFor, navFor, splitHref, type NavGroup, type NavItem } from "@/lib/nav";
import { Icon, Spinner } from "@/components/ui";
import { VouchFlowMark } from "@/components/login-brand";
import { Breadcrumb, Dropdown, MenuItem, MenuLabel, MenuSeparator, ThemeSwitch } from "@/components/app-ui";
import type { Voucher } from "@/lib/types";

/**
 * The workspace every signed-in screen sits in.
 *
 * Sidebar: whose workspace this is, where you can go (grouped by purpose),
 * and who you are — with the appearance switch always in reach. The top bar
 * carries only what applies on every page: where you are, search, language,
 * alerts and the one action most people come here for.
 */

const COLLAPSE_KEY = "vouchflow.sidebar";
const COLLAPSE_EVENT = "vouchflow:sidebar";

/*
 * Whether the desktop sidebar is folded to icons: a per-device preference in
 * localStorage, read as an external store so the server render (always open)
 * and the first client render agree, and every change re-renders at once.
 */
function readCollapsed(): boolean {
  try { return window.localStorage.getItem(COLLAPSE_KEY) === "1"; } catch { return false; }
}

function writeCollapsed(value: boolean) {
  try { window.localStorage.setItem(COLLAPSE_KEY, value ? "1" : "0"); } catch { /* the choice lasts this visit */ }
  window.dispatchEvent(new Event(COLLAPSE_EVENT));
}

function subscribeCollapsed(onChange: () => void) {
  window.addEventListener(COLLAPSE_EVENT, onChange);
  window.addEventListener("storage", onChange);
  return () => { window.removeEventListener(COLLAPSE_EVENT, onChange); window.removeEventListener("storage", onChange); };
}

/* The #section of the address, for the hash-addressed Settings page. */
function subscribeHash(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}
const readHash = () => window.location.hash.replace("#", "");

/* Laptop and tablet widths (981–1279px) get the icon rail, whatever was stored. */
const RAIL_QUERY = "(min-width: 981px) and (max-width: 1279px)";
function subscribeRail(onChange: () => void) {
  const mq = window.matchMedia(RAIL_QUERY);
  mq.addEventListener("change", onChange);
  return () => mq.removeEventListener("change", onChange);
}
const readRail = () => window.matchMedia(RAIL_QUERY).matches;

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, company, ready, t, unread, signOut, locale, setLocale } = useApp();
  const router = useRouter();
  const pathname = usePathname();
  const hash = useSyncExternalStore(subscribeHash, readHash, () => "");
  const [drawer, setDrawer] = useState(false);
  const storedCollapsed = useSyncExternalStore(subscribeCollapsed, readCollapsed, () => false);
  const railWidth = useSyncExternalStore(subscribeRail, readRail, () => false);
  const collapsed = storedCollapsed || railWidth;
  const [pendingCount, setPendingCount] = useState(0);
  const [payCount, setPayCount] = useState(0);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Voucher[]>([]);

  useEffect(() => {
    if (ready && !user) router.replace("/login");
  }, [ready, user, router]);

  useEffect(() => { setDrawer(false); }, [pathname]);

  const toggleCollapsed = () => writeCollapsed(!storedCollapsed);

  const items = useMemo(() => (user ? navFor(user.role) : []), [user]);
  const tabs = useMemo(() => (user ? mobileNavFor(user.role) : []), [user]);

  // A company administrator reaches notifications and profile from the user
  // menu; everyone else keeps them in the sidebar, as the design lays out.
  const sidebarItems = useMemo(
    () => items.filter((item) => !(user?.role === "company_admin" && item.group === "account")),
    [items, user],
  );

  /**
   * Exactly one entry is ever current, in each menu.
   *
   * "Create voucher" lives at /vouchers/new, which is a route *beneath*
   * /vouchers — so a plain prefix test lights both rows at once. The deepest
   * href that still covers the current path is the one the user is on; where
   * two entries share a route (Settings' sections), the #section decides.
   */
  const currentOf = (list: NavItem[]) => {
    const covering = list.filter((i) => {
      const { path } = splitHref(i.href);
      return pathname === path || pathname.startsWith(path + "/");
    });
    if (covering.length === 0) return null;
    const depth = Math.max(...covering.map((i) => splitHref(i.href).path.length));
    const deepest = covering.filter((i) => splitHref(i.href).path.length === depth);
    if (deepest.length === 1) return deepest[0].href;
    const section = hash || "workflow";
    return (deepest.find((i) => splitHref(i.href).hash === section)
      ?? deepest.find((i) => splitHref(i.href).hash === "workflow")
      ?? deepest[0]).href;
  };
  const currentHref = currentOf(sidebarItems);
  const currentTab = currentOf(tabs);

  useEffect(() => {
    if (!user) return;
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setPendingCount(r.data.length))
      .catch(() => setPendingCount(0));

    if (items.some((i) => i.badge === "payments")) {
      api.get<{ data: Voucher[] }>("/vouchers", { status: "approved", per_page: 100 })
        .then((r) => setPayCount(r.data.length))
        .catch(() => setPayCount(0));
    }
  }, [user, pathname, items]);

  // Debounced type-ahead across the vouchers this caller may actually see.
  useEffect(() => {
    if (query.trim().length < 2) { setResults([]); return; }
    const timer = window.setTimeout(() => {
      api.get<{ data: Voucher[] }>("/vouchers", { q: query, per_page: 5 })
        .then((r) => setResults(r.data))
        .catch(() => setResults([]));
    }, 220);
    return () => window.clearTimeout(timer);
  }, [query]);

  if (!ready || !user) {
    return (
      <div className="vf-shell app-booting">
        <Spinner label={t("loading")} />
      </div>
    );
  }

  const badgeFor = (item: { badge?: string }) =>
    item.badge === "pending" ? (pendingCount || null)
      : item.badge === "payments" ? (payCount || null)
      : item.badge === "notifications" ? (unread || null) : null;

  const isPlatform = user.role === "super_admin";
  const workspaceName = isPlatform ? "Platform console" : company?.name ?? "VouchFlow";
  const tenantLine = isPlatform
    ? (locale === "sw" ? "Kampuni zote" : "All tenants")
    : [company?.plan?.name, company?.status].filter(Boolean).join(" · ");

  const groups: { group: NavGroup; items: NavItem[] }[] = [];
  for (const item of sidebarItems) {
    const last = groups[groups.length - 1];
    if (last && last.group === item.group) last.items.push(item);
    else groups.push({ group: item.group, items: [item] });
  }

  // Where you are: the menu entry, plus one step deeper for a record or an edit.
  const current = items.find((i) => i.href === currentHref) ?? items.find((i) => i.href === currentOf(items));
  const crumbs: { label: string; href?: string }[] = [];
  if (current) {
    crumbs.push({ label: t(NAV_GROUP_LABEL[current.group]) });
    crumbs.push({ label: t(current.label), href: current.href });
    if (pathname !== splitHref(current.href).path) {
      crumbs.push({ label: pathname.endsWith("/edit") ? t("edit") : t("details") });
    }
  }

  const profileLabel = items.find((i) => i.href === "/profile")?.label ?? "profile";
  const canCreate = user.role !== "super_admin" && user.role !== "cashier";

  return (
    <div className="vf-shell" data-collapsed={collapsed ? "true" : undefined}>
      {drawer && <button className="vf-scrim" aria-label="Close menu" onClick={() => setDrawer(false)} />}

      <aside className="vf-sidebar" data-open={drawer} aria-label="Main navigation">
        <div className="app-side-head">
          <Link href="/dashboard" className="app-side-brand" aria-label="VouchFlow">
            <VouchFlowMark size={26} />
            <span>VouchFlow</span>
          </Link>
          <button type="button" className="app-side-collapse" onClick={toggleCollapsed} hidden={railWidth}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"} title={collapsed ? "Expand sidebar" : "Collapse sidebar"}>
            <Icon name="ph-sidebar-simple" size={17} />
          </button>
          <button type="button" className="app-side-close" onClick={() => setDrawer(false)} aria-label="Close menu">
            <Icon name="ph-x" size={18} />
          </button>
        </div>

        <div className="app-workspace" title={workspaceName}>
          <div className="app-workspace-mark" data-platform={isPlatform || undefined} data-has-logo={company?.logo_mark_url && !isPlatform ? "true" : undefined}>
            {company?.logo_mark_url && !isPlatform
              // eslint-disable-next-line @next/next/no-img-element
              ? <img src={company.logo_mark_url} alt="" />
              : (isPlatform ? <Icon name="ph-globe-hemisphere-east" size={16} /> : workspaceName.trim().charAt(0).toUpperCase())}
          </div>
          <div className="app-workspace-text">
            <div className="app-workspace-name">{workspaceName}</div>
            {tenantLine && <div className="app-workspace-sub">{tenantLine}</div>}
          </div>
        </div>

        <nav className="app-nav">
          {groups.map(({ group, items: groupItems }) => (
            <div key={group} className="app-nav-group">
              <div className="app-nav-label">{t(NAV_GROUP_LABEL[group])}</div>
              {groupItems.map((item) => {
                const badge = badgeFor(item);
                const active = item.href === currentHref;
                return (
                  <Link key={item.href} href={item.href} className="app-nav-item" aria-current={active ? "page" : undefined} data-tip={t(item.label)}>
                    <Icon name={item.icon} size={18} weight={active ? "fill" : "regular"} />
                    <span className="app-nav-text">{t(item.label)}</span>
                    {badge ? (
                      <span className="app-nav-badge tnum" data-quiet={item.badge !== "pending" || undefined}>{badge > 99 ? "99+" : badge}</span>
                    ) : null}
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>

        <div className="app-side-foot">
          <ThemeSwitch compact={collapsed} />
          <Dropdown
            placement="above" align="start" label={user.name}
            trigger={({ open, toggle, id }) => (
              <button type="button" className="app-user" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu">
                <span className="app-avatar" aria-hidden="true">{user.initials}</span>
                <span className="app-user-text">
                  <span className="app-user-name">{user.name}</span>
                  {/* The job title, which is what a colleague would call this person. */}
                  <span className="app-user-role">{user.job_title || user.role_label}</span>
                </span>
                <Icon name="ph-caret-up-down" size={15} />
              </button>
            )}
          >
            {(close) => (
              <>
                <MenuLabel>{user.email}</MenuLabel>
                <MenuItem icon="ph-user-circle" href="/profile" onSelect={close}>{t(profileLabel)}</MenuItem>
                <MenuItem icon="ph-bell" href="/notifications" onSelect={close}>
                  {t("notifications")}{unread > 0 ? ` (${unread})` : ""}
                </MenuItem>
                <MenuSeparator />
                <div className="app-menu-row">
                  <span>{locale === "sw" ? "Lugha" : "Language"}</span>
                  <div className="seg seg-sm" role="group" aria-label="Language">
                    {(["en", "sw"] as const).map((code) => (
                      <button key={code} type="button" onClick={() => setLocale(code)} aria-selected={locale === code}>{code.toUpperCase()}</button>
                    ))}
                  </div>
                </div>
                <div className="app-menu-row">
                  <span>{locale === "sw" ? "Mwonekano" : "Appearance"}</span>
                  <ThemeSwitch compact />
                </div>
                <MenuSeparator />
                <MenuItem icon="ph-sign-out" tone="danger" onSelect={() => { close(); void signOut(); }}>{t("signOut")}</MenuItem>
              </>
            )}
          </Dropdown>
        </div>
      </aside>

      <div className="vf-main">
        <header className="vf-topbar no-print">
          <button className="btn btn-icon vf-menu-btn" onClick={() => setDrawer(true)} aria-label="Open menu">
            <Icon name="ph-list" size={20} />
          </button>

          <div className="app-topbar-where">
            {crumbs.length > 0 && <Breadcrumb items={crumbs} />}
            <span className="app-topbar-company">{workspaceName}</span>
          </div>

          <div className="vf-search">
            <Icon name="ph-magnifying-glass" size={15} />
            <input
              className="input" placeholder={t("searchPh")} value={query} aria-label={t("search")}
              onChange={(e) => setQuery(e.target.value)}
              onBlur={() => window.setTimeout(() => setResults([]), 180)}
            />
            <kbd className="app-kbd" aria-hidden="true">⌘K</kbd>
            {results.length > 0 && (
              <div className="vf-search-results" role="listbox">
                {results.map((row) => (
                  <button key={row.id} role="option" aria-selected={false} className="vf-search-result"
                    onMouseDown={() => router.push(`/vouchers/${row.id}`)}>
                    <span className="vf-search-result-top">
                      <span className="tnum">{row.number}</span>
                      <span className="tnum">{row.amount_text}</span>
                    </span>
                    <span className="vf-search-result-title">{row.purpose}</span>
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="app-topbar-actions">
            <div className="app-lang" role="group" aria-label="Language">
              {(["en", "sw"] as const).map((code) => (
                <button key={code} type="button" onClick={() => setLocale(code)} aria-pressed={locale === code}>{code.toUpperCase()}</button>
              ))}
            </div>
            <ThemeToggleButton />
            <Link className="btn btn-icon vf-bell" href="/notifications" aria-label={unread > 0 ? `${t("notifications")} (${unread})` : t("notifications")}>
              <Icon name="ph-bell" size={18} />
              {unread > 0 && <span className="vf-bell-dot" aria-hidden="true" />}
            </Link>
            {canCreate && (
              <Link className="btn btn-primary btn-sm app-topbar-create" href="/vouchers/new">
                <Icon name="ph-plus" size={15} /> <span>{t("newVoucher")}</span>
              </Link>
            )}
          </div>
        </header>

        <main className="vf-content">{children}</main>
      </div>

      <nav className="vf-tabbar no-print" aria-label="Primary">
        {tabs.map((item) => {
          const badge = badgeFor(item);
          const active = item.href === currentTab;
          return (
            <Link key={item.href} href={item.href} aria-current={active ? "page" : undefined}>
              <span className="vf-tab-icon">
                <Icon name={item.icon} size={22} weight={active ? "fill" : "regular"} />
                {badge ? <span className="vf-tab-badge">{badge > 99 ? "99+" : badge}</span> : null}
              </span>
              <span className="vf-tab-label">{t(item.short ?? item.label)}</span>
            </Link>
          );
        })}
      </nav>
      {canCreate && (pathname === "/dashboard" || pathname === "/vouchers") && (
        <Link className="app-fab no-print" href="/vouchers/new">
          <Icon name="ph-plus" size={20} /> <span>{t("newVoucher")}</span>
        </Link>
      )}
    </div>
  );
}

/** A one-tap appearance switch for the top bar, labelled for what it will do. */
function ThemeToggleButton() {
  const { theme, toggleTheme, locale } = useApp();
  const sw = locale === "sw";
  const label = theme === "light" ? (sw ? "Badili kuwa giza" : "Switch to dark mode") : (sw ? "Badili kuwa mwanga" : "Switch to light mode");
  return (
    <button type="button" className="btn btn-icon" onClick={toggleTheme} aria-label={label} title={label}>
      <Icon name={theme === "light" ? "ph-moon" : "ph-sun"} size={18} />
    </button>
  );
}
