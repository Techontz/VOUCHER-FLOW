"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { mobileNavFor, navFor } from "@/lib/nav";
import { Icon, LanguageToggle, Spinner, ThemeToggle } from "@/components/ui";
import type { Voucher } from "@/lib/types";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, company, ready, t, unread, signOut } = useApp();
  const router = useRouter();
  const pathname = usePathname();
  const [drawer, setDrawer] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);
  const [payCount, setPayCount] = useState(0);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Voucher[]>([]);

  useEffect(() => {
    if (ready && !user) router.replace("/login");
  }, [ready, user, router]);

  useEffect(() => { setDrawer(false); }, [pathname]);

  const items = useMemo(() => (user ? navFor(user.role) : []), [user]);
  const tabs = useMemo(() => (user ? mobileNavFor(user.role) : []), [user]);

  /**
   * Exactly one entry is ever current, in each menu.
   *
   * "Create voucher" lives at /vouchers/new, which is a route *beneath*
   * /vouchers — so a plain prefix test lights both rows at once. The deepest
   * href that still covers the current path is the one the user is on.
   *
   * The two menus resolve separately, because they hold different sets: the
   * tab bar has no /vouchers/new slot, so on the create screen it falls back
   * to /vouchers and still shows where you are rather than going blank.
   */
  const deepest = (hrefs: string[]) => hrefs
    .filter((h) => pathname === h || pathname.startsWith(h + "/"))
    .sort((a, b) => b.length - a.length)[0] ?? null;

  const currentHref = useMemo(() => deepest(items.map((i) => i.href)), [items, pathname]);
  const currentTab = useMemo(() => deepest(tabs.map((i) => i.href)), [tabs, pathname]);

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
      <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}>
        <Spinner label={t("loading")} />
      </div>
    );
  }

  const badgeFor = (item: { badge?: string }) =>
    item.badge === "pending" ? (pendingCount || null)
      : item.badge === "payments" ? (payCount || null)
      : item.badge === "notifications" ? (unread || null) : null;

  const active = (href: string) => href === currentHref;
  const activeTab = (href: string) => href === currentTab;

  const tenantLine = user.role === "super_admin"
    ? "Platform"
    : company?.plan ? `${company.plan.name} · ${company.status}` : company?.status ?? "";

  return (
    <div className="vf-shell">
      {drawer && <button className="vf-scrim" aria-label="Close menu" onClick={() => setDrawer(false)} />}

      <aside className="vf-sidebar" data-open={drawer} aria-label="Main navigation">
        <div className="vf-brand">
          {/* The square mark, not the lockup: a wordmark crushed into 36px is
              unreadable, which is exactly why brands ship both. */}
          <div className="vf-brand-mark" data-has-logo={company?.logo_mark_url ? "true" : undefined}>
            {company?.logo_mark_url
              ? <img src={company.logo_mark_url} alt="" />
              : (user.role === "super_admin" ? "V" : (company?.name ?? "V").trim().charAt(0).toUpperCase())}
          </div>
          <div className="vf-brand-text">
            {/* Two lines before an ellipsis: a tenant's own name is the last
                thing that should be cut off inside its own workspace. */}
            <div className="vf-brand-name">{user.role === "super_admin" ? "VouchFlow Platform" : company?.name ?? "VouchFlow"}</div>
            {tenantLine && <div className="vf-brand-sub">{tenantLine}</div>}
          </div>
        </div>

        <nav className="vf-nav">
          {items.map((item) => {
            const badge = badgeFor(item);
            return (
              <Link key={item.href} href={item.href} className="vf-navitem" aria-current={active(item.href) ? "page" : undefined}>
                <Icon name={item.icon} />
                <span className="vf-navitem-label">{t(item.label)}</span>
                {badge ? <span className="vf-navbadge">{badge}</span> : null}
              </Link>
            );
          })}
        </nav>

        <div className="vf-user">
          <div className="vf-avatar" aria-hidden="true">{user.initials}</div>
          <div className="vf-user-text">
            <div className="vf-user-name">{user.name}</div>
            {/* The job title, which is what a colleague would call this person —
                and never a machine label like "Ceo". */}
            <div className="vf-user-role">{user.job_title || user.role_label}</div>
          </div>
          <button className="btn btn-icon btn-sm" onClick={signOut} title={t("signOut")} aria-label={t("signOut")}>
            <Icon name="ph-sign-out" size={18} />
          </button>
        </div>
      </aside>

      <main className="vf-main">
        <div className="vf-topbar no-print">
          <button className="btn btn-icon vf-menu-btn" onClick={() => setDrawer(true)} aria-label="Open menu">
            <Icon name="ph-list" size={22} />
          </button>

          <div className="vf-search">
            <Icon name="ph-magnifying-glass" size={17} />
            <input
              className="input" placeholder={t("searchPh")} value={query} aria-label={t("search")}
              onChange={(e) => setQuery(e.target.value)}
              onBlur={() => window.setTimeout(() => setResults([]), 180)}
            />
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

          <div style={{ flex: 1 }} />
          <div className="vf-topbar-extras"><LanguageToggle /></div>
          <ThemeToggle />
          <Link className="btn btn-icon vf-bell" href="/notifications" aria-label={unread > 0 ? `${t("notifications")} (${unread})` : t("notifications")}>
            <Icon name="ph-bell" size={19} />
            {unread > 0 && <span className="vf-bell-dot" aria-hidden="true" />}
          </Link>
          {user.role !== "super_admin" && user.role !== "cashier" && (
            <Link className="btn btn-primary vf-topbar-extras" href="/vouchers/new">
              <Icon name="ph-plus" size={17} /> {t("newVoucher")}
            </Link>
          )}
        </div>

        <div className="vf-content">{children}</div>
      </main>

      <nav className="vf-tabbar no-print" aria-label="Primary">
        {tabs.map((item) => {
          const badge = badgeFor(item);
          return (
            <Link key={item.href} href={item.href} aria-current={activeTab(item.href) ? "page" : undefined}>
              <span className="vf-tab-icon">
                <Icon name={item.icon} size={22} weight={activeTab(item.href) ? "fill" : "regular"} />
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
