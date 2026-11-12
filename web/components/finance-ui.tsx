"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { amount, useErp } from "@/lib/erp";
import type { AssetStatus, BankType, JournalLineRow } from "@/lib/finance-api";
import { Badge, Icon } from "@/components/ui";

/*
 * Pieces the finance and asset screens share: the section tabs that link the
 * finance pages together, and small labelled figures.
 */

const FINANCE_TABS: { href: string; label: MessageKey; icon: string; permission: string }[] = [
  { href: "/erp/finance", label: "finTabOverview", icon: "ph-gauge", permission: "finance.view" },
  { href: "/erp/finance/banks", label: "finTabBanks", icon: "ph-bank", permission: "finance.view" },
  { href: "/erp/finance/transfers", label: "finTabTransfers", icon: "ph-arrows-left-right", permission: "finance.view" },
  { href: "/erp/finance/cashbook", label: "finTabCashbook", icon: "ph-book-open-text", permission: "finance.view" },
  { href: "/erp/finance/reconciliations", label: "finTabReconcile", icon: "ph-checks", permission: "finance.view" },
  { href: "/erp/finance/statements", label: "finTabStatements", icon: "ph-chart-line-up", permission: "finance.statements" },
  { href: "/erp/finance/budgets", label: "finTabBudgets", icon: "ph-target", permission: "finance.view" },
  { href: "/erp/finance/periods", label: "finTabPeriods", icon: "ph-lock-key", permission: "finance.view" },
];

const ASSET_TABS: { href: string; label: MessageKey; icon: string; permission: string }[] = [
  { href: "/erp/assets", label: "finTabAssetsOverview", icon: "ph-gauge", permission: "assets.view" },
  { href: "/erp/assets/register", label: "finTabRegister", icon: "ph-list-bullets", permission: "assets.view" },
  { href: "/erp/assets/depreciation", label: "finTabDepreciation", icon: "ph-trend-down", permission: "assets.view" },
  { href: "/erp/assets/disposals", label: "finTabDisposals", icon: "ph-recycle", permission: "assets.view" },
  { href: "/erp/assets/classes", label: "finTabClasses", icon: "ph-squares-four", permission: "assets.view" },
];

function SectionTabs({ tabs, label }: { tabs: typeof FINANCE_TABS; label: string }) {
  const { t } = useApp();
  const { can } = useErp();
  const path = usePathname();
  const active = tabs.filter((tab) => path === tab.href || path.startsWith(`${tab.href}/`)).sort((a, b) => b.href.length - a.href.length)[0];

  return (
    <nav className="app-tabs fin-tabs" aria-label={label}>
      {tabs.filter((tab) => can(tab.permission)).map((tab) => (
        <Link key={tab.href} href={tab.href} aria-current={active?.href === tab.href ? "page" : undefined}>
          <Icon name={tab.icon} size={15} /> {t(tab.label)}
        </Link>
      ))}
    </nav>
  );
}

export function FinanceTabs() {
  const { t } = useApp();
  return <SectionTabs tabs={FINANCE_TABS} label={t("finNavFinance")} />;
}

export function AssetTabs() {
  const { t } = useApp();
  return <SectionTabs tabs={ASSET_TABS} label={t("finNavAssets")} />;
}

export const BANK_TYPE_LABEL: Record<BankType, MessageKey> = { bank: "finTypeBank", mobile_money: "finTypeMobile", cash: "finTypeCash" };
export const BANK_TYPE_ICON: Record<BankType, string> = { bank: "ph-bank", mobile_money: "ph-device-mobile", cash: "ph-money" };

const ASSET_STATUS: Record<AssetStatus, { label: MessageKey; tone: "info" | "ok" | "neutral" }> = {
  draft: { label: "finAssetDraft", tone: "info" }, active: { label: "finAssetActive", tone: "ok" }, disposed: { label: "finAssetDisposed", tone: "neutral" },
};

export function AssetStatusBadge({ status }: { status: AssetStatus }) {
  const { t } = useApp();
  return <Badge tone={ASSET_STATUS[status].tone} dot>{t(ASSET_STATUS[status].label)}</Badge>;
}

/** A money figure; negatives in brackets, the way statements print them. */
export function Amount({ value, strong }: { value: number | string | null | undefined; strong?: boolean }) {
  const n = Number(value ?? 0);
  const text = n < 0 ? `(${amount(Math.abs(n))})` : amount(n);
  return strong ? <strong className="tnum">{text}</strong> : <span className="tnum">{text}</span>;
}

/** Signed in/out money: green for money in, red for money out. */
export function Flow({ value }: { value: number }) {
  return (
    <span className="tnum" style={{ color: value < 0 ? "var(--st-bad-fg)" : value > 0 ? "var(--st-ok-fg)" : undefined, fontWeight: 600 }}>
      {value > 0 ? "+" : value < 0 ? "−" : ""}{amount(Math.abs(value))}
    </span>
  );
}

/** The ledger lines a document posted. */
export function JournalLines({ lines, number }: { lines: JournalLineRow[]; number: string }) {
  const { t } = useApp();
  return (
    <div className="vf-table-wrap">
      <table className="table vf-table erp-journal-lines">
        <caption className="erp-muted tnum" style={{ textAlign: "left" }}>{t("finJournal")} {number}</caption>
        <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("erpDebit")}</th><th className="num">{t("erpCredit2")}</th></tr></thead>
        <tbody>
          {lines.map((l) => (
            <tr key={l.id}>
              <td><span className="tnum erp-muted">{l.account?.code}</span> {l.account?.name}</td>
              <td className="num">{Number(l.debit) ? amount(l.debit) : ""}</td>
              <td className="num">{Number(l.credit) ? amount(l.credit) : ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Label and value pairs for a detail card. */
export function DetailRows({ rows }: { rows: { label: string; value: ReactNode }[] }) {
  return (
    <table className="table vf-table">
      <tbody>
        {rows.map((r) => <tr key={r.label}><th scope="row" style={{ fontWeight: 500 }}>{r.label}</th><td>{r.value}</td></tr>)}
      </tbody>
    </table>
  );
}
