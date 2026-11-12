"use client";

import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { api, getToken } from "./api";

/*
 * The ERP client layer: the shapes the /api/erp endpoints return, and the
 * one hook every ERP screen opens with.
 *
 * The screens never decide what a person may do. They read the permission
 * list the API resolved for the caller (`can`) and hide what it withholds;
 * the API refuses the same things again on every call.
 */

export type Permission =
  | "erp.configure" | "roles.manage"
  | "inventory.view" | "inventory.manage" | "inventory.receive" | "inventory.issue"
  | "inventory.transfer" | "inventory.adjust" | "inventory.post" | "inventory.reverse"
  | "customers.view" | "customers.manage" | "suppliers.view" | "suppliers.manage"
  | "accounting.view" | "accounting.manage" | "accounting.post" | "accounting.reverse"
  // Later modules declare their own permissions (lib/modules/*.ts).
  | (string & {});

export type ModuleKey =
  | "vouchflow" | "inventory" | "sales" | "procurement" | "accounting"
  | "production" | "dispatch" | "fleet" | "hr" | "crm" | "assets" | "documents";

export interface ProductField { key: string; label: string; type: "text" | "number" | "date" | "boolean" }

export interface ErpSettings {
  allow_negative_stock: boolean;
  costing_method: string;
  base_currency: string;
  default_tax_rate: number;
  fiscal_year_start: string;
  expiry_alert_days: number;
  product_fields: ProductField[];
  product_defaults: { track_batches: boolean; track_expiry: boolean; track_serials: boolean };
}

export interface ErpConfig {
  business_type: string;
  business_label: string | null;
  is_set_up: boolean;
  setup_completed_at: string | null;
  modules: ModuleKey[];
  /** The apps the subscription allows; `modules` is always a subset of these. */
  licensed_modules?: ModuleKey[];
  live_modules: ModuleKey[];
  settings: ErpSettings;
  permissions: Permission[];
}

export interface BusinessTemplate {
  key: string; label: string; label_sw: string; description: string; icon: string;
  modules: ModuleKey[];
  units: { code: string; name: string; allows_decimals: boolean }[];
  categories: string[];
  product_fields: ProductField[];
}

export interface ModuleInfo { key: ModuleKey; label: string; phase: number; live: boolean }

export interface Unit { id: number; code: string; name: string; allows_decimals: boolean }
export interface Category { id: number; name: string; parent_id: number | null; products_count?: number }

export interface Warehouse {
  id: number; code: string; name: string; type: string; branch: string | null; location: string | null;
  manager_user_id: number | null; manager?: { id: number; name: string } | null; is_active: boolean;
  stock_value?: number; products_held?: number;
}

export type ProductType = "stock" | "service" | "raw_material" | "finished_good" | "packaging";

export interface Product {
  id: number; sku: string; barcode: string | null; name: string; brand: string | null; type: ProductType;
  category_id: number | null; category?: { id: number; name: string } | null;
  unit_id: number; unit?: Unit;
  cost_price: string; sale_price: string; reorder_level: string;
  track_batches: boolean; track_expiry: boolean; track_serials: boolean;
  custom_fields: Record<string, string | number | boolean> | null;
  is_active: boolean;
  on_hand?: string | number | null;
}

export interface StockBalance {
  id: number; product_id: number; warehouse_id: number; batch_number: string; expiry_date: string | null;
  quantity: string; average_cost: string; value?: number;
  product?: Pick<Product, "id" | "sku" | "name" | "reorder_level"> & { unit?: Pick<Unit, "code"> };
  warehouse?: Pick<Warehouse, "id" | "code" | "name">;
  expired?: boolean;
}

export interface StockMovement {
  id: number; product_id: number; warehouse_id: number; batch_number: string; type: string;
  quantity: string; unit_cost: string; value: string; balance_after: string;
  reference: string; reason: string | null; movement_date: string; created_at: string;
  stock_document_id: number | null;
  product?: Pick<Product, "id" | "sku" | "name">; warehouse?: Pick<Warehouse, "id" | "code" | "name">;
  creator?: { id: number; name: string } | null;
}

export type DocumentType = "opening" | "grn" | "issue" | "transfer" | "adjustment" | "count";
export type DocumentStatus = "draft" | "posted" | "cancelled" | "reversed";

export interface StockDocumentLine {
  id: number; product_id: number; quantity: string; unit_cost: string | null;
  batch_number: string | null; expiry_date: string | null; serial_number: string | null;
  system_quantity: string | null; note: string | null;
  product?: Pick<Product, "id" | "sku" | "name" | "track_batches" | "track_expiry" | "track_serials"> & { unit?: Pick<Unit, "code" | "name"> };
}

export interface StockDocument {
  id: number; type: DocumentType; number: string; document_date: string; status: DocumentStatus;
  warehouse_id: number; to_warehouse_id: number | null; supplier_id: number | null;
  reference: string | null; reason: string | null; notes: string | null;
  reversal_of_id: number | null; reversal_of?: { id: number; number: string } | null;
  created_at: string; posted_at: string | null;
  warehouse?: Pick<Warehouse, "id" | "code" | "name">; to_warehouse?: Pick<Warehouse, "id" | "code" | "name"> | null;
  supplier?: { id: number; code?: string; name: string } | null;
  creator?: { id: number; name: string } | null; poster?: { id: number; name: string } | null;
  lines?: StockDocumentLine[]; lines_count?: number; movements?: StockMovement[];
}

export interface Party {
  id: number; code: string; name: string; contact_person: string | null; phone: string | null; email: string | null;
  tin: string | null; address: string | null; city: string | null; payment_terms_days: number; is_active: boolean;
  // customers
  customer_group?: string | null; credit_limit?: string; requires_prepayment?: boolean; price_list?: string | null;
  // suppliers
  category?: string | null; bank_name?: string | null; bank_account_name?: string | null; bank_account_number?: string | null;
}

export type AccountType = "asset" | "liability" | "equity" | "income" | "expense";

export interface Account {
  id: number; code: string; name: string; type: AccountType; parent_id: number | null;
  system_key: string | null; is_active: boolean; balance?: number;
}

export interface JournalLine { id: number; account_id: number; debit: string; credit: string; description: string | null; account?: Pick<Account, "id" | "code" | "name"> }

export interface JournalEntry {
  id: number; number: string; entry_date: string; memo: string; source_type: string | null; source_id: number | null;
  purpose: string; status: "posted" | "reversed"; total: string; reversal_of_id: number | null;
  posted_at: string; lines?: JournalLine[]; creator?: { id: number; name: string } | null;
}

export interface TrialBalance {
  rows: { account_id: number; code: string; name: string; type: AccountType; debit: number; credit: number; balance: number }[];
  total_debit: number; total_credit: number; balanced: boolean;
}

export interface RoleRow {
  key: string; name: string; description: string | null; built_in: boolean; customised: boolean;
  locked: boolean; permissions: Permission[]; users: number;
}

export interface PermissionInfo { key: Permission; label: string; group: string }

export interface Paginated<T> { data: T[]; current_page: number; last_page: number; total: number; per_page: number }

/* ─────────────────────────────────────────────────────────── the hook ── */

let cached: ErpConfig | null = null;
// The session the cache was read for: a different sign-in in the same tab
// must never be shown the previous person's permissions.
let cachedFor: string | null = null;
const listeners = new Set<(c: ErpConfig | null) => void>();

/** Re-reads the configuration everywhere it is shown, after setup, or a role change. */
export async function refreshErpConfig(): Promise<ErpConfig | null> {
  try {
    cachedFor = getToken();
    cached = (await api.get<{ data: ErpConfig }>("/erp/config")).data;
  } catch {
    cached = null;
  }
  listeners.forEach((l) => l(cached));
  return cached;
}

/**
 * The company's ERP configuration and the caller's permissions. Read once and
 * shared by every screen; `refresh` re-reads it.
 */
export function useErp() {
  if (cachedFor !== null && cachedFor !== getToken()) forgetErpConfig();
  const [config, setConfig] = useState<ErpConfig | null>(cached);
  const [loading, setLoading] = useState(cached === null);

  useEffect(() => {
    const listener = (c: ErpConfig | null) => { setConfig(c); setLoading(false); };
    listeners.add(listener);
    if (cached === null) void refreshErpConfig();
    return () => { listeners.delete(listener); };
  }, []);

  const can = useCallback((permission: Permission) => !!config?.permissions.includes(permission), [config]);
  const has = useCallback((module: ModuleKey) => !!config?.modules.includes(module), [config]);

  return { config, loading, can, has, refresh: refreshErpConfig };
}

/** Clears the shared configuration, e.g. on sign-out. */
export function forgetErpConfig() {
  cached = null;
  cachedFor = null;
}

/* ───────────────────────────────────────────────────────── formatting ── */

/** Quantities keep up to four decimals and drop trailing zeros: 12, 12.5, 0.125. */
export function qty(value: string | number | null | undefined): string {
  const n = Number(value ?? 0);
  return n.toLocaleString("en-US", { maximumFractionDigits: 4 });
}

/** Money without a currency symbol, two decimals only when there are cents. */
export function amount(value: string | number | null | undefined): string {
  const n = Number(value ?? 0);
  return n.toLocaleString("en-US", { minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 });
}

export const DOCUMENT_TYPES: DocumentType[] = ["grn", "issue", "transfer", "adjustment", "count", "opening"];

/** The permission that prepares each type, as the API checks it. */
export const PREPARE_PERMISSION: Record<DocumentType, Permission> = {
  opening: "inventory.receive", grn: "inventory.receive", issue: "inventory.issue",
  transfer: "inventory.transfer", adjustment: "inventory.adjust", count: "inventory.adjust",
};

export const DOCUMENT_ICON: Record<DocumentType, string> = {
  grn: "ph-tray-arrow-down", issue: "ph-tray-arrow-up", transfer: "ph-arrows-left-right",
  adjustment: "ph-sliders-horizontal", count: "ph-list-numbers", opening: "ph-flag-banner",
};

export function statusTone(status: DocumentStatus): "neutral" | "info" | "ok" | "warn" | "bad" {
  return status === "posted" ? "ok" : status === "draft" ? "info" : status === "reversed" ? "warn" : "neutral";
}

/**
 * One query-string value, read from the location as an external store. Used
 * instead of useSearchParams so a static ERP route needs no Suspense boundary
 * for a deep link like ?type=grn. `undefined` during the server render.
 */
export function useQueryValue(name: string): string | null | undefined {
  return useSyncExternalStore(
    noSubscription,
    () => new URLSearchParams(window.location.search).get(name),
    () => undefined,
  );
}

const noSubscription = () => () => {};
