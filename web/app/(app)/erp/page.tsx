"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, DOCUMENT_ICON, type DocumentStatus, type DocumentType, type ModuleInfo, useErp } from "@/lib/erp";
import { compactMoney, formatDate } from "@/lib/format";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills, type StatPill } from "@/components/ui";
import { DOC_LABEL, DocStatus, ErpGate, fill } from "@/components/erp-ui";

interface Overview {
  is_set_up: boolean;
  modules: string[];
  inventory?: {
    stock_value: number; products: number; warehouses: number; low_stock: number; drafts: number;
    movements_7d: { day: string; count: number }[];
    recent: { id: number; number: string; type: DocumentType; status: DocumentStatus; document_date: string; warehouse?: { name: string } }[];
  };
  customers?: number;
  suppliers?: number;
  accounting?: { journals_this_month: number };
}

/**
 * The ERP home: who you are and what is waiting, in the shape of the rest of
 * the workspace, a greeting, the figures that matter to this role, and the
 * cards behind them. Every figure is one the caller's permissions allow.
 */
export default function ErpHomePage() {
  return (
    <ErpGate>
      <Overview />
    </ErpGate>
  );
}

function Overview() {
  const { t, user, locale } = useApp();
  const { config, can } = useErp();
  const [data, setData] = useState<Overview | null>(null);
  const [modules, setModules] = useState<ModuleInfo[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Overview }>("/erp/overview").then((r) => setData(r.data)).catch((e) => setError(e.message));
    api.get<{ modules: ModuleInfo[] }>("/erp/templates").then((r) => setModules(r.modules)).catch(() => undefined);
  }, []);

  const hour = new Date().getHours();
  const greeting = t(hour < 12 ? "erpGreetingMorning" : hour < 17 ? "erpGreetingAfternoon" : "erpGreetingEvening");
  const first = user?.name.split(" ")[0] ?? "";
  const today = new Date().toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { weekday: "long", day: "numeric", month: "long" });

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock rows={6} />;

  const inv = data.inventory;
  const currency = config?.settings.base_currency ?? "TZS";
  const pills: StatPill[] = [];
  if (inv) {
    pills.push(
      { label: t("erpStockValue"), value: compactMoney(inv.stock_value, currency), hint: `${currency} ${amount(inv.stock_value)}`, icon: "ph-coins", href: "/erp/stock" },
      { label: t("erpLowStock"), value: inv.low_stock, icon: "ph-warning", tone: inv.low_stock ? "warn" : "ok", href: "/erp/stock?tab=alerts" },
      { label: t("erpDraftsWaiting"), value: inv.drafts, icon: "ph-file-dashed", tone: inv.drafts ? "info" : "neutral", href: "/erp/documents" },
      { label: t("erpActiveProducts"), value: inv.products, icon: "ph-package", href: "/erp/products" },
    );
  }
  if (data.customers !== undefined) pills.push({ label: t("erpCustomers"), value: data.customers, icon: "ph-users-three", href: "/erp/customers" });
  if (data.suppliers !== undefined) pills.push({ label: t("erpSuppliers"), value: data.suppliers, icon: "ph-truck", href: "/erp/suppliers" });

  const week = lastSevenDays(inv?.movements_7d ?? [], locale);
  const peak = Math.max(1, ...week.map((d) => d.count));

  const actions = [
    can("inventory.receive") && { href: "/erp/documents/new?type=grn", icon: DOCUMENT_ICON.grn, label: t("erpDocGrn") },
    can("inventory.issue") && { href: "/erp/documents/new?type=issue", icon: DOCUMENT_ICON.issue, label: t("erpDocIssue") },
    can("inventory.transfer") && { href: "/erp/documents/new?type=transfer", icon: DOCUMENT_ICON.transfer, label: t("erpDocTransfer") },
    can("inventory.adjust") && { href: "/erp/documents/new?type=count", icon: DOCUMENT_ICON.count, label: t("erpDocCount") },
    can("inventory.manage") && { href: "/erp/products?new=1", icon: "ph-package", label: t("erpNewProduct") },
  ].filter(Boolean) as { href: string; icon: string; label: string }[];

  return (
    <div className="erp-page">
      <PageHeader
        title={`${greeting}, ${first}`}
        subtitle={`${today} · ${config?.business_label ?? ""}`}
        actions={actions[0] && (
          <Link className="btn btn-primary" href={actions[0].href}><Icon name="ph-plus" size={18} /> {actions[0].label}</Link>
        )}
      />

      {pills.length > 0 && (
        // The dashboard's even-row grid: six figures sit as two rows of three.
        <div className="app-dash-figures" data-count={pills.length}><StatPills items={pills} label={t("erpHome")} /></div>
      )}

      <div className="erp-grid">
        {inv && (
          <GlassCard title={t("erpMovementsWeek")} subtitle={`${week.reduce((s, d) => s + d.count, 0)} · ${t("erpLedger")}`}
            action={<Link className="vf-card-link" href="/erp/stock?tab=ledger">{t("erpViewAll")}</Link>}>
            <div className="erp-bars" role="img" aria-label={week.map((d) => `${d.label}: ${d.count}`).join(", ")}>
              {week.map((d) => (
                <div key={d.key} className="erp-bar">
                  <div className="erp-bar-track">
                    <div className="erp-bar-fill" style={{ height: `${Math.max(d.count ? 6 : 0, (d.count / peak) * 100)}%` }} data-today={d.today ? "" : undefined} />
                  </div>
                  <span className="erp-bar-label">{d.label}</span>
                </div>
              ))}
            </div>
          </GlassCard>
        )}

        {actions.length > 0 && (
          <GlassCard title={t("erpQuickActions")}>
            <div className="erp-actions">
              {actions.map((a) => (
                <Link key={a.href} href={a.href} className="erp-action">
                  <span className="erp-action-icon"><Icon name={a.icon} size={20} /></span>
                  <span>{a.label}</span>
                  <Icon name="ph-caret-right" size={16} style={{ marginLeft: "auto", opacity: .5 }} />
                </Link>
              ))}
            </div>
          </GlassCard>
        )}

        {inv && (
          <GlassCard className="erp-span-2" title={t("erpRecentDocuments")} subtitle={t("erpRecentSub")} pad={false}
            action={<Link className="vf-card-link" href="/erp/documents">{t("erpViewAll")}</Link>}>
            {inv.recent.length === 0 ? (
              <EmptyState icon="ph-tray" title={t("erpNoDocuments")} />
            ) : (
              <ul className="erp-list">
                {inv.recent.map((d) => (
                  <li key={d.id}>
                    <Link href={`/erp/documents/${d.id}`} className="erp-list-row">
                      <span className="erp-list-icon"><Icon name={DOCUMENT_ICON[d.type]} size={18} /></span>
                      <span className="erp-list-main">
                        <span className="erp-list-title">{t(DOC_LABEL[d.type])}</span>
                        <span className="erp-list-sub tnum">{d.number} · {d.warehouse?.name} · {formatDate(d.document_date, locale)}</span>
                      </span>
                      <DocStatus status={d.status} />
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </GlassCard>
        )}

        <GlassCard title={t("erpModulesTitle")} subtitle={t("erpModulesSub")}
          action={can("erp.configure") ? <Link className="vf-card-link" href="/erp/setup">{t("erpSetup")}</Link> : undefined}>
          <ul className="erp-modules">
            {modules.filter((m) => m.key !== "vouchflow").map((m) => {
              const on = data.modules.includes(m.key);
              return (
                <li key={m.key} data-on={on ? "" : undefined}>
                  <span className="erp-module-dot" aria-hidden="true" />
                  <span className="erp-module-name">{m.label}</span>
                  <span className="erp-module-state">
                    {m.live ? (on ? t("erpLive") : t("erpInactive")) : fill(t("erpComingPhase"), { n: m.phase })}
                  </span>
                </li>
              );
            })}
          </ul>
        </GlassCard>
      </div>
    </div>
  );
}

/** Seven columns ending today, with zero for days that had no movements. */
function lastSevenDays(rows: { day: string; count: number }[], locale: string) {
  const counts = new Map(rows.map((r) => [r.day.slice(0, 10), Number(r.count)]));
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - (6 - i));
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    return {
      key,
      count: counts.get(key) ?? 0,
      label: d.toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { weekday: "short" }),
      today: i === 6,
    };
  });
}
