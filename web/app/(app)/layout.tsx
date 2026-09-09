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

  const active = (href: string) =>
    href === "/dashboard" ? pathname === href : pathname === href || pathname.startsWith(href + "/");

  const tenantLine = user.role === "super_admin"
    ? "Platform"
    : company?.plan ? `${company.plan.name} · ${company.status}` : company?.status ?? "";

  return (
    <div className="vf-shell">
      {drawer && <button className="vf-scrim" aria-label="Close menu" onClick={() => setDrawer(false)} />}

      <aside className="vf-sidebar" data-open={drawer}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "0 var(--space-2) var(--space-3)" }}>
          {/* The square mark, not the lockup: a wordmark crushed into 34px is
              unreadable, which is exactly why brands ship both. */}
          <div className="vf-mark" style={{
            width: 34, height: 34, fontSize: 16,
            background: company?.logo_mark_url ? "transparent" : undefined,
          }}>
            {company?.logo_mark_url
              ? <img src={company.logo_mark_url} alt="" style={{ width: "100%", height: "100%", objectFit: "contain" }} />
              : (user.role === "super_admin" ? "V" : (company?.name ?? "V").trim().charAt(0).toUpperCase())}
          </div>
          <div style={{ minWidth: 0 }}>
            <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 15.5, lineHeight: 1.15, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              {user.role === "super_admin" ? "VouchFlow Platform" : company?.name ?? "VouchFlow"}
            </div>
            <div style={{ fontSize: 12, color: "var(--color-neutral-600)", textTransform: "capitalize" }}>{tenantLine}</div>
          </div>
        </div>

        <nav style={{ display: "flex", flexDirection: "column", gap: 1 }}>
          {items.map((item) => {
            const badge = badgeFor(item);
            return (
              <Link key={item.href} href={item.href} className="vf-navitem" aria-current={active(item.href) ? "page" : undefined}>
                <Icon name={item.icon} />
                <span style={{ flex: 1 }}>{t(item.label)}</span>
                {badge ? <span className="vf-navbadge">{badge}</span> : null}
              </Link>
            );
          })}
        </nav>

        <div style={{ flex: 1 }} />

        <div style={{ borderTop: "1px solid var(--vf-line)", paddingTop: "var(--space-3)", display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{
            width: 32, height: 32, borderRadius: "50%",
            background: "color-mix(in srgb, var(--color-accent-500) 18%, transparent)",
            border: "1px solid var(--vf-line)", color: "var(--color-accent-600)",
            display: "grid", placeItems: "center", fontSize: 13, fontWeight: 600, flex: "none",
          }}>{user.initials}</div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 14, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{user.name}</div>
            <div style={{ fontSize: 12, color: "var(--color-neutral-600)" }}>{user.role_label}</div>
          </div>
          <button className="btn btn-icon" onClick={signOut} title={t("signOut")} aria-label={t("signOut")}>
            <Icon name="ph-sign-out" />
          </button>
        </div>
      </aside>

      <main className="vf-main">
        <div className="vf-topbar no-print">
          <button className="btn btn-icon vf-menu-btn" onClick={() => setDrawer(true)} aria-label="Open menu">
            <Icon name="ph-list" />
          </button>

          <div style={{ position: "relative", flex: "1 1 200px", maxWidth: 360, minWidth: 0 }}>
            <Icon name="ph-magnifying-glass" size={16} style={{ position: "absolute", left: 9, top: 10, color: "var(--color-neutral-600)" }} />
            <input
              className="input" placeholder={t("searchPh")} value={query} aria-label={t("search")}
              onChange={(e) => setQuery(e.target.value)}
              onBlur={() => window.setTimeout(() => setResults([]), 180)}
              style={{ paddingLeft: 32, height: 36 }}
            />
            {results.length > 0 && (
              <div style={{
                position: "absolute", top: 40, left: 0, right: 0, background: "var(--color-neutral-100)",
                border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)",
                boxShadow: "var(--shadow-lg)", zIndex: 30, overflow: "hidden",
              }}>
                {results.map((row) => (
                  <button key={row.id} onMouseDown={() => router.push(`/vouchers/${row.id}`)}
                    style={{
                      display: "block", width: "100%", textAlign: "left", border: 0, background: "transparent",
                      fontFamily: "var(--font-body)", padding: "9px var(--space-3)", cursor: "pointer",
                      borderBottom: "1px solid var(--color-divider)", color: "var(--color-text)",
                    }}>
                    <div style={{ fontSize: 13, color: "var(--color-neutral-600)", fontVariantNumeric: "tabular-nums" }}>{row.number}</div>
                    <div style={{ fontSize: 14.5 }}>{row.purpose} — {row.amount_text}</div>
                  </button>
                ))}
              </div>
            )}
          </div>

          <div style={{ flex: 1 }} />
          <div className="vf-topbar-extras"><LanguageToggle /></div>
          <ThemeToggle />
          <Link className="btn btn-icon" href="/notifications" style={{ position: "relative" }} aria-label={t("notifications")}>
            <Icon name="ph-bell" />
            {unread > 0 && <span style={{ position: "absolute", top: 3, right: 3, width: 7, height: 7, borderRadius: "50%", background: "var(--color-accent-2-500)" }} />}
          </Link>
          {user.role !== "super_admin" && user.role !== "cashier" && (
            <Link className="btn btn-primary vf-topbar-extras" href="/vouchers/new" style={{ whiteSpace: "nowrap" }}>
              <Icon name="ph-plus" size={15} /> {t("newVoucher")}
            </Link>
          )}
        </div>

        <div className="vf-content">{children}</div>
      </main>

      <nav className="vf-tabbar no-print" aria-label="Primary">
        {tabs.map((item) => (
          <Link key={item.href} href={item.href} aria-current={active(item.href) ? "page" : undefined}>
            <span style={{ position: "relative" }}>
              <Icon name={item.icon} size={20} />
              {badgeFor(item) ? (
                <span style={{ position: "absolute", top: -3, right: -8, background: "var(--color-badge-bg)", color: "var(--color-badge-fg)", borderRadius: 8, fontSize: 9.5, fontWeight: 600, padding: "0 4px" }}>
                  {badgeFor(item)}
                </span>
              ) : null}
            </span>
            {t(item.short ?? item.label)}
          </Link>
        ))}
      </nav>
    </div>
  );
}
