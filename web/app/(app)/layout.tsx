"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { navFor, type NavItem } from "@/lib/nav";
import { areaByKey, areaOf, CREATE_ACTIONS, type AreaKey } from "@/lib/areas";
import { useErp } from "@/lib/erp";
import { fill } from "@/components/erp-ui";
import { SETTINGS_CHILDREN, useAreas } from "@/lib/use-areas";
import { Icon, LanguageToggle, Loader } from "@/components/ui";
import { VouchFlowMark } from "@/components/login-brand";
import { AppIcon } from "@/components/app-icon";
import { UserAvatar } from "@/components/user-avatar";
import { PendingGate } from "@/components/pending-gate";
import { Breadcrumb, Dropdown, MenuItem, MenuSeparator, ThemeSwitch } from "@/components/app-ui";
import type { Voucher } from "@/lib/types";

/**
 * The workspace every signed-in screen sits in.
 *
 * Sidebar: whose workspace this is, where you can go (grouped by purpose),
 * and who you are, with the appearance switch always in reach. The top bar
 * carries only what applies on every page: where you are, search, alerts and
 * the one action most people come here for.
 */

/** The launcher, and the tab that returns to it on a phone. */
const APPS_ITEM: NavItem = { href: "/home", label: "navApps", icon: "ph-squares-four" };

/**
 * The entry another entry is drawn beneath: /vouchers/new sits under
 * /vouchers. Purely visual, the same entries, links and permissions.
 */
function parentOf(item: NavItem, siblings: NavItem[]): NavItem | undefined {
  // The ERP overview heads a whole group; its siblings are not its children.
  return siblings.find((p) => p !== item && p.href !== "/erp" && item.href.startsWith(p.href + "/"));
}


const COLLAPSE_KEY = "vouchflow.sidebar";
const COLLAPSE_EVENT = "vouchflow:sidebar";

/*
 * Whether the desktop sidebar is folded to icons: a per-device preference in
 * localStorage, read as an external store so the server render (always open)
 * and the first client render agree, and every change re-renders at once.
 *
 * The state itself lives on <html data-sidebar>, which the root layout's
 * bootstrap script sets before first paint, so a sidebar the user left
 * collapsed is already a rail when the page appears, rather than animating
 * into one after hydration.
 */
function readCollapsed(): boolean {
  // Until the user picks, the bootstrap starts laptop-width screens (under
  // 1280px) on the rail so the content keeps its room; a choice then sticks.
  return document.documentElement.dataset.sidebar === "collapsed";
}

function writeCollapsed(value: boolean) {
  if (value) document.documentElement.dataset.sidebar = "collapsed";
  else delete document.documentElement.dataset.sidebar;
  try { window.localStorage.setItem(COLLAPSE_KEY, value ? "1" : "0"); } catch { /* the choice lasts this visit */ }
  window.dispatchEvent(new Event(COLLAPSE_EVENT));
}

function subscribeCollapsed(onChange: () => void) {
  // Another tab changed it: mirror the stored choice onto this page first.
  const onStorage = (e: StorageEvent) => {
    if (e.key !== COLLAPSE_KEY) return;
    if (e.newValue === "1") document.documentElement.dataset.sidebar = "collapsed";
    else delete document.documentElement.dataset.sidebar;
    onChange();
  };
  window.addEventListener(COLLAPSE_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => { window.removeEventListener(COLLAPSE_EVENT, onChange); window.removeEventListener("storage", onStorage); };
}

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, company, companyPending, ready, t, unread, signOut, locale } = useApp();
  const router = useRouter();
  const pathname = usePathname();
  // The drawer belongs to the page it was opened on: navigating closes it.
  const [drawerAt, setDrawerAt] = useState<string | null>(null);
  const drawer = drawerAt === pathname;
  const setDrawer = (open: boolean) => setDrawerAt(open ? pathname : null);
  const collapsed = useSyncExternalStore(subscribeCollapsed, readCollapsed, () => false);
  const [pendingCount, setPendingCount] = useState(0);
  const [payCount, setPayCount] = useState(0);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Voucher[]>([]);
  // Nested menu entries (Vouchers → Create voucher) are open unless folded.
  const [closedGroups, setClosedGroups] = useState<string[]>([]);
  const searchRef = useRef<HTMLInputElement>(null);

  // ⌘K / Ctrl+K puts the cursor in the top-bar search, as its hint says.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (ready && !user) router.replace("/login");
  }, [ready, user, router]);


  const toggleCollapsed = () => writeCollapsed(!collapsed);

  const items = useMemo(() => (user ? navFor(user.role) : []), [user]);
  const { items: reachable, byArea, open: apps } = useAreas();
  const { can } = useErp();
  const [searchOpen, setSearchOpen] = useState(false);

  /**
   * Exactly one entry is ever current, in each menu.
   *
   * "Create voucher" lives at /vouchers/new, which is a route *beneath*
   * /vouchers, so a plain prefix test lights both rows at once. The deepest
   * href that still covers the current path is the one the user is on.
   */
  const deepest = (hrefs: string[], path: string) => hrefs
    .filter((h) => path === h || path.startsWith(h + "/"))
    .sort((a, b) => b.length - a.length)[0] ?? null;

  // Settings children light up Settings in the menu.
  const menuPath = user?.role === "company_admin" && SETTINGS_CHILDREN.some((h) => pathname.startsWith(h)) ? "/settings" : pathname;
  const currentHref = useMemo(() => deepest(reachable.map((i) => i.href), menuPath), [reachable, menuPath]);

  /**
   * The app that is open: the one owning the page you are on. The sidebar
   * shows only its entries; on the launcher, the sidebar lists the apps.
   */
  const currentArea: AreaKey | null = useMemo(() => {
    if (pathname === "/home") return null;
    const owner = reachable.find((i) => i.href === currentHref);
    if (!owner) return null;
    return user?.role === "super_admin" ? "platform" : areaOf(owner);
  }, [pathname, reachable, currentHref, user]);
  const sidebarItems = useMemo(() => (currentArea ? byArea.get(currentArea) ?? [] : []), [currentArea, byArea]);

  /*
   * The sidebar's three tabs: the open app's menu, every app, and the
   * company's settings. It follows the page: settings pages open the
   * Settings tab, the launcher opens Apps; a click can look elsewhere.
   */
  type SideTab = "menu" | "apps" | "settings";
  const tabForPage: SideTab = currentArea === "settings" ? "settings" : currentArea ? "menu" : "apps";
  const [picked, setPicked] = useState<{ tab: SideTab; path: string } | null>(null);
  const sideTab: SideTab = picked && picked.path === pathname ? picked.tab : tabForPage;
  const setSideTab = (tab: SideTab) => setPicked({ tab, path: pathname });
  const settingsItems = byArea.get("settings") ?? [];

  // Phone tabs: the launcher, then the open app's first four entries.
  const tabs = useMemo(() => {
    const area = currentArea ?? apps[0]?.key;
    const own = (area ? byArea.get(area) ?? [] : []).filter((i) => i.href !== "/vouchers/new");
    return apps.length > 1 ? [APPS_ITEM, ...own.slice(0, 4)] : own.slice(0, 5);
  }, [currentArea, apps, byArea]);
  const currentTab = useMemo(() => deepest(tabs.map((i) => i.href), pathname), [tabs, pathname]);

  useEffect(() => {
    // A company awaiting approval may not read vouchers; the gate is all it sees.
    if (!user || companyPending) return;
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setPendingCount(r.data.length))
      .catch(() => setPendingCount(0));

    if (items.some((i) => i.badge === "payments")) {
      api.get<{ data: Voucher[] }>("/vouchers", { status: "approved", per_page: 100 })
        .then((r) => setPayCount(r.data.length))
        .catch(() => setPayCount(0));
    }
  }, [user, companyPending, pathname, items]);

  // Debounced type-ahead across the vouchers this caller may actually see.
  useEffect(() => {
    if (query.trim().length < 2) return;
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
        <Loader label={t("loading")} />
      </div>
    );
  }

  // Self-registered and not yet approved by the platform: no product, only
  // the awaiting-approval screen (plan, payment, status check, sign out).
  if (companyPending) return <PendingGate />;

  const badgeFor = (item: { badge?: string }) =>
    item.badge === "pending" ? (pendingCount || null)
      : item.badge === "payments" ? (payCount || null)
      : item.badge === "notifications" ? (unread || null) : null;

  const isPlatform = user.role === "super_admin";
  const workspaceName = isPlatform ? "VouchFlow Platform" : company?.name ?? "VouchFlow";

  const area = currentArea ? areaByKey(currentArea) : null;
  const areaHome = (key: AreaKey) => byArea.get(key)?.[0]?.href ?? "/home";

  // Where you are: the app, the menu entry, then one step deeper for a record or an edit.
  const current = sidebarItems.find((i) => i.href === currentHref) ?? items.find((i) => i.href === deepest(items.map((x) => x.href), pathname));
  const crumbs: { label: string; href?: string }[] = [];
  if (pathname === "/home") crumbs.push({ label: t("navApps") });
  if (current && area) {
    crumbs.push({ label: t(area.label), href: areaHome(area.key) });
    if (current.href !== areaHome(area.key)) crumbs.push({ label: t(current.label), href: current.href });
    if (pathname !== current.href && !SETTINGS_CHILDREN.includes(pathname)) {
      crumbs.push({ label: pathname.endsWith("/edit") ? t("edit") : t("details") });
    }
    if (SETTINGS_CHILDREN.includes(pathname) && user.role === "company_admin") {
      crumbs.push({ label: t(pathname === "/branding" ? "branding" : "subscription") });
    }
  }

  // The company's own mark: its logo, or its initial; the platform's for a super admin.
  const companyMark = isPlatform ? (
    <VouchFlowMark size={32} />
  ) : (
    <span className="app-company-mark" data-has-logo={company?.logo_mark_url ? "true" : undefined}>
      {company?.logo_mark_url
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={company.logo_mark_url} alt="" />
        : workspaceName.trim().charAt(0).toUpperCase()}
    </span>
  );

  const canCreate = user.role !== "super_admin" && user.role !== "cashier";

  // What + creates here: this app's everyday documents the caller may raise.
  const createActions = (area ? CREATE_ACTIONS[area.key] ?? [] : [])
    .filter((action) => (action.href === "/vouchers/new" ? canCreate : !action.permission || can(action.permission)));

  // Search reaches every app and page the caller can open, then vouchers.
  const needle = query.trim().toLowerCase();
  const appHits = needle ? apps.filter((a) => t(a.label).toLowerCase().includes(needle)).slice(0, 4) : [];
  const pageHits = needle ? reachable.filter((p) => t(p.label).toLowerCase().includes(needle)).slice(0, 6) : [];
  const firstHit = appHits[0] ? areaHome(appHits[0].key) : pageHits[0]?.href ?? (results[0] ? `/vouchers/${results[0].id}` : undefined);

  const sideLabel = locale === "sw"
    ? (collapsed ? "Panua menyu" : "Kunja menyu")
    : (collapsed ? "Expand sidebar" : "Collapse sidebar");
  const profileLabel = items.find((i) => i.href === "/profile")?.label ?? "profile";

  // The signed-in person's menu: one body, opened from the card at the foot
  // of the sidebar (desktop) or the avatar in the top bar (tablet and phone).
  const userMenu = (close: () => void) => (
    <>
      <div className="app-menu-head">
        <strong>{user.name}</strong>
        <span>{user.email}</span>
      </div>
      <MenuItem icon="ph-user-circle" href="/profile" onSelect={close}>{t(profileLabel)}</MenuItem>
      <MenuItem icon="ph-bell" href="/notifications" onSelect={close}>
        {t("notifications")}{unread > 0 ? ` (${unread})` : ""}
      </MenuItem>
      <MenuSeparator />
      <div className="app-menu-row">
        <span>{locale === "sw" ? "Lugha" : "Language"}</span>
        <LanguageToggle full />
      </div>
      <div className="app-menu-row">
        <span>{locale === "sw" ? "Mwonekano" : "Appearance"}</span>
        <ThemeSwitch compact />
      </div>
      <MenuSeparator />
      <MenuItem icon="ph-sign-out" tone="danger" onSelect={() => { close(); void signOut(); }}>{t("signOut")}</MenuItem>
    </>
  );

  return (
    <div className="vf-shell">
      {drawer && <button className="vf-scrim" aria-label="Close menu" onClick={() => setDrawer(false)} />}

      <aside className="vf-sidebar" data-open={drawer} aria-label="Main navigation">
        <div className="app-side-head">
          <Link href="/home" className="app-side-brand" title={workspaceName}>
            {companyMark}
            <span className="app-side-brand-text">
              <span>{workspaceName}</span>
              <small>{user.role_label}</small>
            </span>
          </Link>
          {/* Desktop: fold to the icon rail (the top-bar menu button does the same). */}
          <button type="button" className="app-side-collapse" onClick={toggleCollapsed} aria-label={sideLabel} title={sideLabel}>
            <Icon name="ph-caret-left" size={16} />
          </button>
          <button type="button" className="app-side-close" onClick={() => setDrawer(false)} aria-label="Close menu">
            <Icon name="ph-x" size={18} />
          </button>
        </div>

        {/* Menu, Apps, Settings: the open app's entries, every app, the company's settings. */}
        <div className="app-side-tabs" role="tablist" aria-label={t("launcherSwitch")}>
          {([
            ["menu", t("navMenu"), !!area && area.key !== "settings"],
            ["apps", t("navApps"), apps.length > 1],
            ["settings", t("areaSettings"), settingsItems.length > 0],
          ] as [SideTab, string, boolean][]).filter(([, , shown]) => shown).map(([key, label]) => (
            <button key={key} type="button" role="tab" aria-selected={sideTab === key} className="app-side-tab"
              onClick={() => setSideTab(key)}>{label}</button>
          ))}
        </div>

        <nav className="app-nav">
          {(sideTab === "apps" || (sideTab === "menu" && !area)) && (
            <div className="app-nav-group">
              <Link href="/home" className="app-nav-item" aria-current={pathname === "/home" ? "page" : undefined} data-tip={t("launcherAll")}>
                <Icon name="ph-squares-four" size={20} weight={pathname === "/home" ? "fill" : "regular"} />
                <span className="app-nav-text">{t("launcherAll")}</span>
              </Link>
              {apps.filter((a) => a.key !== "settings").map((a) => (
                <Link key={a.key} href={areaHome(a.key)} className="app-nav-item app-nav-app" aria-current={a.key === currentArea ? "page" : undefined} data-tip={t(a.label)}>
                  <AppIcon area={a} size={26} />
                  <span className="app-nav-text">{t(a.label)}</span>
                </Link>
              ))}
            </div>
          )}
          {(sideTab === "settings" ? [{ group: "settings", items: settingsItems }] : sideTab === "menu" && area ? [{ group: area.key, items: sidebarItems }] : []).map(({ group, items: groupItems }) => (
            <div key={group} className="app-nav-group">
              {groupItems.filter((item) => !parentOf(item, groupItems)).map((item) => {
                const children = groupItems.filter((c) => parentOf(c, groupItems) === item);
                const open = !closedGroups.includes(item.href);
                const row = (entry: NavItem, child = false) => {
                  const badge = badgeFor(entry);
                  const active = entry.href === currentHref;
                  return (
                    <Link key={entry.href} href={entry.href} className={child ? "app-nav-item app-nav-child" : "app-nav-item"}
                      aria-current={active ? "page" : undefined} data-tip={t(entry.label)}>
                      <Icon name={entry.icon} size={20} weight={active ? "fill" : "regular"} />
                      <span className="app-nav-text">{t(entry.label)}</span>
                      {badge ? <span className="app-nav-badge tnum">{badge > 99 ? "99+" : badge}</span> : null}
                      {badge ? <span className="app-nav-dot" aria-hidden="true" /> : null}
                    </Link>
                  );
                };
                if (!children.length) return row(item);
                return (
                  <div key={item.href} className="app-nav-parent" data-open={open ? "true" : "false"}>
                    <div className="app-nav-parent-row">
                      {row(item)}
                      <button type="button" className="app-nav-caret" aria-expanded={open}
                        aria-label={`${t(item.label)}: ${open ? (locale === "sw" ? "kunja" : "collapse") : (locale === "sw" ? "panua" : "expand")}`}
                        onClick={() => setClosedGroups((all) => (open ? [...all, item.href] : all.filter((h) => h !== item.href)))}>
                        <Icon name="ph-caret-up" size={15} />
                      </button>
                    </div>
                    {open && children.map((c) => row(c, true))}
                  </div>
                );
              })}
            </div>
          ))}
        </nav>

        {/* Who is signed in, pinned to the foot of the sidebar however many
            groups the menu above grows to. */}
        <div className="app-side-foot">
          <Dropdown
            floating align="start" placement="above" label={user.name}
            trigger={({ open, toggle, id }) => (
              <button type="button" className="app-side-user" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu"
                title={user.name} data-tip={user.name}>
                <UserAvatar src={user.avatar_url} initials={user.initials} />
                <span className="app-side-user-text">
                  <span className="app-side-user-name">{user.name}</span>
                  <span className="app-side-user-role">{user.job_title || user.role_label}</span>
                </span>
                <Icon name="ph-caret-up-down" size={16} />
              </button>
            )}
          >
            {userMenu}
          </Dropdown>
        </div>
      </aside>

      <div className="vf-main">
        <header className="vf-topbar no-print">
          {/* One identity in the corner: the company whose workspace this is
              (the platform's own for a super admin). Its administrator opens
              the company's pages from here. */}
          {user.role === "company_admin" ? (
            <Dropdown
              align="start" placement="below" label={workspaceName}
              trigger={({ open, toggle, id }) => (
                <button type="button" className="app-topbar-brand" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu" title={workspaceName}>
                  {companyMark}
                  <span className="app-topbar-brand-name">{workspaceName}</span>
                  <Icon name="ph-caret-down" size={14} />
                </button>
              )}
            >
              {(close) => (
                <>
                  <div className="app-menu-label">{workspaceName}</div>
                  <MenuItem icon="ph-squares-four" href="/home" onSelect={close}>{t("launcherAll")}</MenuItem>
                  <MenuSeparator />
                  <MenuItem icon="ph-buildings" href="/settings" onSelect={close}>{t("companyProfile")}</MenuItem>
                  <MenuItem icon="ph-palette" href="/branding" onSelect={close}>{t("branding")}</MenuItem>
                  <MenuItem icon="ph-crown-simple" href="/subscription" onSelect={close}>{t("subscription")}</MenuItem>
                </>
              )}
            </Dropdown>
          ) : (
            <Link href="/home" className="app-topbar-brand" title={workspaceName}>
              {companyMark}
              <span className="app-topbar-brand-name">{workspaceName}</span>
            </Link>
          )}
          {/* One control, as in the AGIZA header: on a desktop it folds the
              sidebar to its icon rail and back; below 981px it opens the drawer. */}
          <button type="button" className="btn btn-icon app-shell-toggle"
            onClick={() => (window.matchMedia("(max-width: 980px)").matches ? setDrawer(true) : toggleCollapsed())}
            aria-label={sideLabel} title={sideLabel} aria-expanded={!collapsed}>
            <Icon name="ph-list" size={22} />
          </button>

          <div className="app-topbar-where">
            {crumbs.length > 0 && <Breadcrumb items={crumbs} />}
            <span className="app-topbar-company">{workspaceName}</span>
          </div>

          <div className="app-topbar-pill">
            <div className="vf-search">
              <Icon name="ph-magnifying-glass" size={18} />
              <input
                ref={searchRef}
                className="input" placeholder={area ? fill(t("searchIn"), { app: t(area.label) }) : t("searchEverything")}
                value={query} aria-label={t("search")}
                aria-keyshortcuts="Meta+K Control+K"
                onChange={(e) => { setQuery(e.target.value); setSearchOpen(true); }}
                onFocus={() => setSearchOpen(true)}
                onBlur={() => window.setTimeout(() => setSearchOpen(false), 180)}
                onKeyDown={(e) => {
                  if (e.key === "Escape") { setQuery(""); (e.target as HTMLInputElement).blur(); }
                  if (e.key === "Enter" && firstHit) { router.push(firstHit); setQuery(""); setSearchOpen(false); }
                }}
              />
              <kbd className="app-kbd" aria-hidden="true">⌘K</kbd>
              {searchOpen && (appHits.length > 0 || pageHits.length > 0 || (query.trim().length >= 2 && results.length > 0)) && (
                <div className="vf-search-results" role="listbox">
                  {appHits.length > 0 && <div className="vf-search-group">{t("searchApps")}</div>}
                  {appHits.map((a) => (
                    <button key={a.key} role="option" aria-selected={false} className="vf-search-result vf-search-row"
                      onMouseDown={() => { router.push(areaHome(a.key)); setQuery(""); }}>
                      <AppIcon area={a} size={28} />
                      <span className="vf-search-result-title">{t(a.label)}</span>
                    </button>
                  ))}
                  {pageHits.length > 0 && <div className="vf-search-group">{t("searchPages")}</div>}
                  {pageHits.map((p) => (
                    <button key={p.href} role="option" aria-selected={false} className="vf-search-result vf-search-row"
                      onMouseDown={() => { router.push(p.href); setQuery(""); }}>
                      <span className="vf-search-icon"><Icon name={p.icon} size={16} /></span>
                      <span className="vf-search-result-title">{t(p.label)}</span>
                      <span className="vf-search-where">{t(areaByKey(areaOf(p)).label)}</span>
                    </button>
                  ))}
                  {query.trim().length >= 2 && results.length > 0 && <div className="vf-search-group">{t("searchVouchers")}</div>}
                  {query.trim().length >= 2 && results.map((row) => (
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
              {/* Create, in the app you are in: one action opens straight
                  away, several open a short menu. Nothing on the launcher. */}
              {createActions.length === 1 && (
                <Link className="btn btn-primary app-topbar-create" href={createActions[0].href} title={t(createActions[0].label)} aria-label={t(createActions[0].label)}>
                  <Icon name="ph-plus" size={18} weight="bold" />
                </Link>
              )}
              {createActions.length > 1 && area && (
                <Dropdown
                  align="end" placement="below" label={fill(t("createIn"), { app: t(area.label) })}
                  trigger={({ open, toggle, id }) => (
                    <button type="button" className="btn btn-primary app-topbar-create" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu"
                      title={fill(t("createIn"), { app: t(area.label) })} aria-label={fill(t("createIn"), { app: t(area.label) })}>
                      <Icon name="ph-plus" size={18} weight="bold" />
                    </button>
                  )}
                >
                  {(close) => (
                    <>
                      <div className="app-menu-label">{fill(t("createIn"), { app: t(area.label) })}</div>
                      {createActions.map((action) => (
                        <MenuItem key={action.href} icon={action.icon} href={action.href} onSelect={close}>{t(action.label)}</MenuItem>
                      ))}
                    </>
                  )}
                </Dropdown>
              )}
              <ThemeToggleButton />
              <Link className="btn btn-icon vf-bell" href="/notifications" aria-label={unread > 0 ? `${t("notifications")} (${unread})` : t("notifications")}>
                <Icon name="ph-bell" size={21} />
                {unread > 0 && <span className="vf-bell-dot" aria-hidden="true" />}
              </Link>
            </div>
          </div>

          {/* Tablet and phone: the sidebar is a drawer, so the person's menu
              stays reachable from the top bar. */}
          <div className="app-topbar-user">
            <Dropdown
              placement="below" align="end" label={user.name}
              trigger={({ open, toggle, id }) => (
                <button type="button" className="app-user" onClick={toggle} aria-expanded={open} aria-controls={id} aria-haspopup="menu" aria-label={user.name}>
                  <UserAvatar src={user.avatar_url} initials={user.initials} />
                </button>
              )}
            >
              {userMenu}
            </Dropdown>
          </div>
        </header>

        {/* Keyed by route, so each page arrives with a short settle while the
            sidebar and top bar stay put around it. */}
        <main className="vf-content"><div key={pathname} className="app-route">{children}</div></main>
      </div>

      <nav className="vf-tabbar no-print" aria-label="Primary">
        {tabs.map((item) => {
          const badge = badgeFor(item);
          const active = item.href === currentTab;
          return (
            <Link key={item.href} href={item.href} aria-current={active ? "page" : undefined}>
              <span className="vf-tab-icon">
                <Icon name={item.icon} size={21} weight={active ? "fill" : "regular"} />
                {badge ? <span className="vf-tab-badge">{badge > 99 ? "99+" : badge}</span> : null}
              </span>
              <span className="vf-tab-label">{t(item.short ?? item.label)}</span>
            </Link>
          );
        })}
      </nav>
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
      <Icon name={theme === "light" ? "ph-moon" : "ph-sun"} size={21} />
    </button>
  );
}
