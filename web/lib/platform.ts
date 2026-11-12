import type { MessageKey } from "./i18n";
import type { Locale } from "./api";
import type { Tone } from "@/components/ui";

/*
 * Shapes and small helpers for the platform administration screens, shared
 * by the overview, companies, plans, subscriptions, users and settings pages.
 */

export interface MonthPoint { month: string; value: number }

export interface CompanyRow {
  id: number; name: string; email: string; plan: string | null; status: string; users_count: number; created_at: string | null;
}

export interface PlatformAnalytics {
  currency: string;
  months: string[];
  kpis: {
    mrr: number; arr: number; revenue_this_month: number; revenue_last_month: number; revenue_12m: number;
    companies: number; paying_companies: number; trial_companies: number; pending_approvals: number;
    users: number; active_users: number; active_users_30d: number;
    vouchers: number; vouchers_value: number; vouchers_this_month: number;
  };
  revenue_by_month: MonthPoint[];
  mrr_by_month: MonthPoint[];
  signups_by_month: MonthPoint[];
  vouchers_by_month: { month: string; created: number; created_value: number; paid: number; paid_value: number }[];
  companies_by_status: Record<string, number>;
  companies_by_plan: { plan_id: number | null; name: string; count: number }[];
  users_by_role: Record<string, number>;
  module_adoption: { key: string; label: string; live: boolean; count: number; percent: number }[];
  churn: { period_days: number; count: number; rate: number; suspended: number; expired: number; cancelled: number };
  expiring: {
    id: number; company_id: number; company: string | null; plan: string | null; status: string; amount: number;
    currency: string; cancel_at_period_end: boolean; ends_at: string | null; days_left: number;
  }[];
  pending: CompanyRow[];
  recent_signups: CompanyRow[];
  top_companies: { id: number; name: string; plan: string | null; currency: string; vouchers: number; value: number }[];
}

/** A company's lifecycle state: its label and the tone of its badge. */
export const COMPANY_STATUS: Record<string, { label: MessageKey; tone: Tone }> = {
  pending: { label: "pendingApproval", tone: "warn" },
  trial: { label: "pfStatusTrial", tone: "info" },
  active: { label: "pfStatusActive", tone: "ok" },
  past_due: { label: "pfStatusPastDue", tone: "warn" },
  suspended: { label: "pfStatusSuspended", tone: "bad" },
  expired: { label: "pfStatusExpired", tone: "bad" },
  cancelled: { label: "pfStatusCancelled", tone: "neutral" },
};

export const SUBSCRIPTION_STATUS: Record<string, { label: MessageKey; tone: Tone }> = {
  trialing: { label: "pfStatusTrial", tone: "info" },
  active: { label: "pfStatusActive", tone: "ok" },
  past_due: { label: "pfStatusPastDue", tone: "warn" },
  cancelled: { label: "pfStatusCancelled", tone: "neutral" },
  expired: { label: "pfStatusExpired", tone: "bad" },
};

export const USER_STATUS: Record<string, { label: MessageKey; tone: Tone }> = {
  active: { label: "pfStatusActive", tone: "ok" },
  invited: { label: "invited", tone: "info" },
  suspended: { label: "pfStatusSuspended", tone: "bad" },
};

/** Phosphor icon and Swahili-aware label key per ERP module. */
export const MODULE_LOOK: Record<string, { icon: string; label: MessageKey }> = {
  vouchflow: { icon: "ph-receipt", label: "pfModVouchflow" },
  inventory: { icon: "ph-package", label: "pfModInventory" },
  sales: { icon: "ph-storefront", label: "pfModSales" },
  procurement: { icon: "ph-shopping-cart", label: "pfModProcurement" },
  accounting: { icon: "ph-calculator", label: "pfModAccounting" },
  production: { icon: "ph-factory", label: "pfModProduction" },
  dispatch: { icon: "ph-truck", label: "pfModDispatch" },
  fleet: { icon: "ph-steering-wheel", label: "pfModFleet" },
  hr: { icon: "ph-identification-card", label: "pfModHr" },
  crm: { icon: "ph-handshake", label: "pfModCrm" },
  assets: { icon: "ph-buildings", label: "pfModAssets" },
  documents: { icon: "ph-folder-open", label: "pfModDocuments" },
};

/** "2026-11" as "Nov" (or "Nov 26" when `year`), in the reader's language. */
export function monthLabel(month: string, locale: Locale, year = false): string {
  const d = new Date(`${month}-01T00:00:00`);
  return d.toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", year ? { month: "short", year: "2-digit" } : { month: "short" });
}

/** Whole days from now until a date; negative once it has passed. */
export function daysUntil(value: string | null | undefined): number | null {
  if (!value) return null;
  const d = new Date(value).getTime();
  if (Number.isNaN(d)) return null;
  return Math.ceil((d - Date.now()) / 86_400_000);
}

/** Initials for a company mark. */
export function initialsOf(name: string): string {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
}

/** Percentage change, rounded, or null when there is nothing to compare with. */
export function change(now: number, before: number): number | null {
  if (!before) return null;
  return Math.round(((now - before) / before) * 100);
}

/** Replaces {name} placeholders in a translated sentence. */
export function fill(text: string, params: Record<string, string | number>): string {
  return text.replace(/\{(\w+)\}/g, (_, k: string) => String(params[k] ?? `{${k}}`));
}
