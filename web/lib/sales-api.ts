"use client";

import { useEffect, useState } from "react";
import { api } from "./api";
import type { MessageKey } from "./i18n";
import type { Paginated, Party, Unit } from "./erp";

/*
 * Sales and dispatch: the shapes /api/erp/sales and /api/erp/dispatch return,
 * status labels and tones, and the lookups every sales form starts from.
 */

export type SalesStatus =
  | "draft" | "sent" | "converted" | "rejected" | "cancelled"
  | "submitted" | "awaiting_payment" | "ready" | "loading" | "dispatched" | "delivered"
  | "posted" | "recorded" | "verified" | "open" | "loaded" | "returned" | "written_off";

export const STATUS_LABEL: Record<SalesStatus, MessageKey> = {
  draft: "salStDraft", sent: "salStSent", converted: "salStConverted", rejected: "salStRejected", cancelled: "salStCancelled",
  submitted: "salStSubmitted", awaiting_payment: "salStAwaitingPayment", ready: "salStReady", loading: "salStLoading",
  dispatched: "salStDispatched", delivered: "salStDelivered", posted: "salStPosted", recorded: "salStRecorded",
  verified: "salStVerified", open: "salStOpen", loaded: "salStLoaded", returned: "salStReturned", written_off: "salStWrittenOff",
};

export function statusTone(status: SalesStatus): "neutral" | "info" | "ok" | "warn" | "bad" {
  switch (status) {
    case "delivered": case "posted": case "verified": case "converted": case "returned": return "ok";
    case "submitted": case "awaiting_payment": case "recorded": case "open": case "written_off": return "warn";
    case "rejected": return "bad";
    case "cancelled": return "neutral";
    default: return "info";
  }
}

export interface LookupCustomer {
  id: number; code: string; name: string; city: string | null; address: string | null;
  credit_limit: string; payment_terms_days: number; requires_prepayment: boolean; price_list: string | null;
}

export interface LookupProduct {
  id: number; sku: string; name: string; type: string; sale_price: string; track_batches: boolean; track_expiry: boolean;
  unit?: Pick<Unit, "id" | "code" | "allows_decimals">;
}

export interface Lookups {
  customers: LookupCustomer[];
  products: LookupProduct[];
  warehouses: { id: number; code: string; name: string }[];
  price_lists: { id: number; code: string; name: string; is_default: boolean }[];
  cash_accounts: { id: number; code: string; name: string }[];
  tax_rate: number;
}

type Person = { id: number; name: string } | null;
type ProductRef = { id: number; sku: string; name: string; unit?: { code: string } };

export interface Amounts {
  unit_price: string; discount_percent: string; tax_rate: string;
  line_subtotal: string; line_discount: string; line_tax: string; line_total: string;
}

export interface Totals { subtotal: string; discount_total: string; tax_total: string; total: string }

export interface QuotationLine extends Amounts { id: number; product_id: number; description: string | null; quantity: string; product?: ProductRef }

export interface Quotation extends Totals {
  id: number; number: string; customer_id: number; quote_date: string; valid_until: string | null; status: SalesStatus;
  notes: string | null; sales_order_id: number | null; created_at: string;
  customer?: Party; creator?: Person; order?: { id: number; number: string; status?: SalesStatus } | null;
  lines?: QuotationLine[]; lines_count?: number;
}

export interface OrderLine extends Amounts {
  id: number; product_id: number; description: string | null;
  quantity_ordered: string; quantity_approved: string | null; quantity_loaded: string; quantity_received: string; quantity_invoiced: string;
  product?: ProductRef & { track_batches?: boolean };
}

export interface PolicyCheck {
  mode: "prepayment" | "credit"; passed: boolean; credit_limit: number; outstanding: number; uninvoiced_orders: number;
  this_order: number; exposure: number; overdue_invoices: number; oldest_overdue_days: number; reasons: string[]; checked_at: string;
}

export interface Availability { [productId: string]: { [warehouseId: string]: { on_hand: number; reserved: number; available: number } } }

export interface SalesOrder extends Totals {
  id: number; number: string; customer_id: number; quotation_id: number | null; warehouse_id: number | null;
  order_date: string; required_date: string | null; status: SalesStatus; payment_mode: "prepayment" | "credit" | null;
  delivery_address: string | null; notes: string | null; policy_check: PolicyCheck | null;
  override_reason: string | null; rejection_reason: string | null;
  submitted_at: string | null; approved_at: string | null; payment_verified_at: string | null; created_at: string;
  customer?: Party; warehouse?: { id: number; name: string } | null; quotation?: { id: number; number: string } | null;
  creator?: Person; approver?: Person; overrider?: Person;
  lines?: OrderLine[]; lines_count?: number;
  invoices?: Invoice[]; loading_orders?: LoadingOrder[];
  verified_payments?: number; remaining_to_load?: Record<string, number>; policy_preview?: PolicyCheck | null;
  availability?: Availability; warehouses?: { id: number; code: string; name: string }[];
}

export interface InvoiceLine extends Amounts { id: number; product_id: number; description: string | null; quantity: string; quantity_credited: string; product?: ProductRef }

export interface Invoice extends Totals {
  id: number; number: string; customer_id: number; sales_order_id: number | null; loading_order_id: number | null;
  invoice_date: string; due_date: string; status: SalesStatus; amount_paid: string; amount_credited: string; balance: number;
  notes: string | null; posted_at: string | null; created_at: string;
  customer?: Party; order?: { id: number; number: string; delivery_address?: string | null } | null;
  loading_order?: { id: number; number: string; delivery_note_number: string | null } | null;
  creator?: Person; poster?: Person; lines?: InvoiceLine[];
  allocations?: { id: number; amount: string; receipt?: { id: number; number: string; receipt_date: string; status: SalesStatus; method: string } }[];
  credit_notes?: { id: number; number: string; credit_date: string; status: SalesStatus; total: string }[];
  seller?: { name: string; email: string; phone: string | null; address: string | null; city: string | null; tin: string | null; currency: string; logo_path: string | null };
}

export interface Receipt {
  id: number; number: string; customer_id: number; account_id: number; receipt_date: string; amount: string;
  method: "cash" | "bank_transfer" | "mobile_money" | "cheque"; reference: string | null; status: SalesStatus;
  notes: string | null; verified_at: string | null; rejection_reason: string | null; created_by: number; created_at: string;
  customer?: Party; account?: { id: number; code: string; name: string }; creator?: Person; verifier?: Person;
  allocations?: { id: number; sales_invoice_id: number; amount: string; invoice?: { id: number; number: string; sales_order_id: number | null; total?: string } }[];
}

export interface CreditNoteLine extends Amounts { id: number; product_id: number; quantity: string; batch_number: string | null; expiry_date: string | null; product?: ProductRef }

export interface CreditNote extends Totals {
  id: number; number: string; customer_id: number; sales_invoice_id: number; credit_date: string; reason: string;
  status: SalesStatus; return_to_stock: boolean; warehouse_id: number | null; posted_at: string | null; created_at: string;
  customer?: Party; invoice?: { id: number; number: string; total?: string }; warehouse?: { id: number; name: string } | null;
  stock_document?: { id: number; number: string; status: string } | null; creator?: Person; poster?: Person;
  lines?: CreditNoteLine[]; lines_count?: number;
}

export interface LoadingLine {
  id: number; sales_order_line_id: number; product_id: number;
  quantity_ordered: string; quantity_approved: string; quantity_loaded: string | null; quantity_received: string | null;
  product?: ProductRef;
}

export interface LoadingOrder {
  id: number; number: string; sales_order_id: number; customer_id: number; warehouse_id: number; status: SalesStatus;
  planned_date: string | null; vehicle_number: string | null; driver_name: string | null; destination: string | null; notes: string | null;
  stock_document_id: number | null; loaded_at: string | null;
  driver_confirmed_name: string | null; driver_confirmed_at: string | null;
  security_confirmed_name: string | null; security_confirmed_at: string | null;
  delivery_note_number: string | null; delivery_note_issued_at: string | null;
  gate_pass_number: string | null; gate_pass_issued_at: string | null;
  received_by_name: string | null; received_date: string | null; delivery_remark: string | null; pod_recorded_at: string | null;
  discrepancy_status: "open" | "returned" | "written_off" | null; discrepancy_note: string | null; discrepancy_resolved_at: string | null;
  return_document_id: number | null; created_at: string;
  order?: { id: number; number: string; status?: SalesStatus; payment_mode?: string | null; total?: string; delivery_address?: string | null };
  customer?: Party; warehouse?: { id: number; code?: string; name: string; branch?: string | null };
  stock_document?: { id: number; number: string; status: string } | null; return_document?: { id: number; number: string } | null;
  creator?: Person; loader?: Person; driver_confirmer?: Person; security_confirmer?: Person; gate_pass_issuer?: Person;
  pod_recorder?: Person; resolver?: Person;
  lines?: LoadingLine[]; lines_count?: number; availability?: Availability;
  seller?: { name: string; address: string | null; phone: string | null };
}

export interface PriceListRow {
  id: number; code: string; name: string; is_default: boolean; is_active: boolean; notes: string | null;
  items_count?: number; customers_count?: number;
  items?: { id: number; product_id: number; unit_price: string; effective_from: string; effective_to: string | null; product?: ProductRef & { sale_price: string } }[];
  customers?: { id: number; code: string; name: string; city: string | null }[];
}

export interface AgedRow {
  customer_id: number; code: string; name: string;
  current: number; d1_30: number; d31_60: number; d61_90: number; d90_plus: number; total: number;
  invoices: { id: number; number: string; invoice_date: string; due_date: string; days_overdue: number; bucket: string; open: number }[];
}

export const AGED_BUCKETS = ["current", "d1_30", "d31_60", "d61_90", "d90_plus"] as const;
export type AgedBucket = (typeof AGED_BUCKETS)[number];
export const AGED_LABEL: Record<AgedBucket, MessageKey> = {
  current: "salAgedCurrent", d1_30: "salAged1", d31_60: "salAged31", d61_90: "salAged61", d90_plus: "salAged90",
};

export interface Aged { as_of: string; rows: AgedRow[]; totals: Record<AgedBucket | "total", number> }

export interface Statement {
  customer: Party & { credit_limit: string; payment_terms_days: number; requires_prepayment: boolean };
  from: string; to: string; opening_balance: number; closing_balance: number; total_debit: number; total_credit: number;
  lines: { date: string; type: "invoice" | "receipt" | "credit_note"; id: number; number: string; detail: string | null; debit: number; credit: number; balance: number }[];
  aged: Record<AgedBucket | "total", number>;
}

export interface Overview {
  sales_this_month: number; invoiced_this_month: number; received_this_month: number; receivables: number; overdue: number;
  open_quotations: number; awaiting_verification: number; awaiting_payment: number; open_discrepancies: number;
  pipeline: Partial<Record<SalesStatus, { count: number; value: number }>>;
  recent_orders: Pick<SalesOrder, "id" | "number" | "customer_id" | "order_date" | "status" | "total" | "payment_mode" | "customer">[];
}

export const RECEIPT_METHODS = ["bank_transfer", "mobile_money", "cash", "cheque"] as const;
export const METHOD_LABEL: Record<(typeof RECEIPT_METHODS)[number], MessageKey> = {
  bank_transfer: "salMethodBank", mobile_money: "salMethodMobile", cash: "salMethodCash", cheque: "salMethodCheque",
};

/** The pickers' data for sales forms, read once per screen. */
export function useSalesLookups() {
  const [lookups, setLookups] = useState<Lookups | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Lookups }>("/erp/sales/lookups").then((r) => setLookups(r.data)).catch((e) => setError(e.message));
  }, []);

  return { lookups, error };
}

/** Line amounts, mirrored from the API's SalesPricing so a form shows the total the server will store. */
export function lineAmounts(quantity: number, price: number, discountPercent: number, taxRate: number) {
  const round = (n: number) => Math.round(n * 100) / 100;
  const subtotal = round(quantity * price);
  const discount = round(subtotal * discountPercent / 100);
  const tax = round((subtotal - discount) * taxRate / 100);
  return { subtotal, discount, tax, total: round(subtotal - discount + tax) };
}

export function num(value: string | number | null | undefined): number {
  return Number(value ?? 0);
}

/**
 * A paginated list that re-reads when its filters change (search debounced).
 * `reload` re-reads the current page after an action.
 */
export function usePaged<T>(path: string, query: Record<string, string | number | undefined>, search = "") {
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<T> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const key = JSON.stringify(query);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<T>>(path, { ...JSON.parse(key), q: search || undefined, page })
        .then((r) => { setRows(r); setError(null); }).catch((e) => setError(e.message));
    }, search ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [path, key, search, page, tick]);

  // Back to the first page whenever the filters change.
  const [lastKey, setLastKey] = useState(key + search);
  if (lastKey !== key + search) { setLastKey(key + search); setPage(1); }

  return { rows, error, page, setPage, reload: () => setTick((n) => n + 1) };
}
