"use client";

import { useEffect, useState } from "react";
import { api } from "./api";

/*
 * The shapes the /api/erp/procurement endpoints return. Money and quantities
 * arrive as decimal strings, as Laravel casts them; read them with Number().
 */

export type LineType = "stock" | "service";

export interface Person { id: number; name: string; role?: string }
export interface SupplierRef { id: number; code?: string; name: string; payment_terms_days?: number }
export interface AccountRef { id: number; code: string; name: string }

export interface Approval {
  id: number; level: number; decision: "approved" | "rejected"; comment: string | null; created_at: string; user?: Person;
}

export type RequisitionStatus = "draft" | "submitted" | "approved" | "rejected" | "ordered" | "cancelled";

export interface RequisitionLine {
  id: number; line_type: LineType; product_id: number | null; description: string; quantity: string;
  estimated_unit_price: string; amount: string; expense_account_id: number | null;
  product?: { id: number; sku: string; name: string; unit?: { code: string } } | null;
  expense_account?: AccountRef | null;
}

export interface Requisition {
  id: number; number: string; status: RequisitionStatus; justification: string; needed_by: string | null;
  total: string; approvals_required: number; department_id: number | null; requested_by: number;
  created_at: string; submitted_at: string | null; approved_at: string | null;
  department?: { id: number; name: string } | null; requester?: Person;
  lines?: RequisitionLine[]; lines_count?: number; approvals?: Approval[];
  orders?: { id: number; number: string; status: OrderStatus }[];
}

export type RfqStatus = "draft" | "sent" | "awarded" | "cancelled";

export interface RfqLine { id: number; line_type: LineType; product_id: number | null; description: string; quantity: string; expense_account_id: number | null }

export interface Quotation {
  id: number; supplier_id: number; reference: string | null; quotation_date: string; valid_until: string | null;
  lead_time_days: number | null; payment_terms: string | null; delivery_terms: string | null;
  subtotal: string; vat_amount: string; total: string; status: "received" | "selected" | "not_selected";
  supplier?: SupplierRef; lines?: { id: number; purchase_rfq_line_id: number; unit_price: string; vat_rate: string; amount: string }[];
}

export interface Rfq {
  id: number; number: string; title: string; status: RfqStatus; issue_date: string; closing_date: string | null;
  notes: string | null; selection_reason: string | null; selected_quotation_id: number | null; awarded_at: string | null;
  purchase_requisition_id: number | null;
  requisition?: { id: number; number: string; status: RequisitionStatus } | null;
  lines?: RfqLine[]; suppliers?: SupplierRef[]; quotations?: Quotation[]; creator?: Person; awarder?: Person | null;
  lines_count?: number; suppliers_count?: number; quotations_count?: number;
  selected_quotation?: { id: number; total: string; supplier?: SupplierRef } | null;
}

export interface Comparison {
  quotations: {
    id: number; supplier: SupplierRef; reference: string | null; lead_time_days: number | null; payment_terms: string | null;
    delivery_terms: string | null; valid_until: string | null; subtotal: number; vat_amount: number; total: number;
    status: Quotation["status"]; lowest: boolean;
  }[];
  lines: { id: number; description: string; line_type: LineType; quantity: number; prices: { quotation_id: number; unit_price: number | null; amount: number | null; lowest: boolean }[] }[];
  invited: SupplierRef[];
}

export type OrderStatus = "draft" | "submitted" | "approved" | "sent" | "partially_received" | "received" | "closed" | "cancelled";

export interface OrderLine {
  id: number; line_type: LineType; product_id: number | null; description: string; quantity: string; unit_price: string;
  vat_rate: string; amount: string; vat_amount: string; received_quantity: string; invoiced_quantity: string;
  expense_account_id: number | null; purchase_requisition_line_id: number | null;
  product?: { id: number; sku: string; name: string; track_batches: boolean; track_expiry: boolean; track_serials: boolean; unit?: { code: string } } | null;
  expense_account?: AccountRef | null;
}

export interface Receipt {
  id: number; kind: "goods" | "service"; number: string; received_date: string; delivery_note: string | null; value: string;
  stock_document_id: number | null; stock_document?: { id: number; number: string; status: string } | null;
  receiver?: Person; lines?: { id: number; purchase_order_line_id: number; quantity: string; unit_cost: string; value: string }[];
}

export interface Order {
  id: number; number: string; status: OrderStatus; supplier_id: number; warehouse_id: number | null;
  order_date: string; expected_date: string | null; payment_terms: string | null; currency: string;
  subtotal: string; vat_amount: string; total: string; approvals_required: number; notes: string | null;
  cancel_reason: string | null; created_by: number; created_at: string;
  purchase_requisition_id: number | null; supplier_quotation_id: number | null;
  supplier?: SupplierRef; warehouse?: { id: number; code: string; name: string } | null; creator?: Person;
  requisition?: { id: number; number: string } | null; quotation?: { id: number; purchase_rfq_id: number; reference: string | null } | null;
  lines?: OrderLine[]; lines_count?: number; approvals?: Approval[]; receipts?: Receipt[];
  invoices?: { id: number; number: string; supplier_invoice_number: string; status: InvoiceStatus; total: string; match_status: string }[];
  ordered_quantity?: string | null; received_quantity?: string | null;
}

export type InvoiceStatus = "draft" | "awaiting_approval" | "approved" | "posted" | "cancelled";

export interface InvoiceLine {
  id: number; purchase_order_line_id: number; line_type: LineType; description: string; quantity: string; unit_price: string;
  vat_rate: string; amount: string; vat_amount: string; order_unit_price: string; matchable_quantity: string;
  price_variance: string; quantity_variance: string; flagged: boolean; expense_account_id: number | null;
  order_line?: { id: number; quantity: string; unit_price: string; received_quantity: string; invoiced_quantity: string } | null;
  expense_account?: AccountRef | null;
}

export interface Invoice {
  id: number; number: string; supplier_invoice_number: string; status: InvoiceStatus; match_status: "matched" | "variance";
  supplier_id: number; purchase_order_id: number; invoice_date: string; due_date: string;
  subtotal: string; vat_amount: string; total: string; amount_paid: string; outstanding: number;
  payment_status: "paid" | "partially_paid" | "unpaid" | null; notes: string | null; created_by: number;
  created_at: string; posted_at: string | null; variance_approved_at: string | null;
  supplier?: SupplierRef; order?: { id: number; number: string; status: OrderStatus }; lines?: InvoiceLine[];
  approvals?: Approval[]; creator?: Person; poster?: Person | null; variance_approver?: Person | null;
  journal?: { id: number; number: string; status: string } | null;
  allocations?: { id: number; amount: string; payment?: { id: number; number: string; payment_date: string; status: PaymentStatus } }[];
}

export type PaymentStatus = "draft" | "posted" | "cancelled";

export interface Payment {
  id: number; number: string; status: PaymentStatus; supplier_id: number; account_id: number; payment_date: string;
  method: string; reference: string | null; amount: string; notes: string | null; created_at: string; posted_at: string | null;
  supplier?: SupplierRef; account?: AccountRef; creator?: Person; poster?: Person | null;
  journal?: { id: number; number: string; status: string } | null; allocations_count?: number;
  allocations?: { id: number; amount: string; invoice?: { id: number; number: string; supplier_invoice_number: string; invoice_date: string; due_date: string; total: string } }[];
}

export interface ProcurementSettings {
  approval_threshold: string; senior_roles: string[] | null; receipt_tolerance_percent: string;
  price_tolerance_percent: string; quantity_tolerance_percent: string; default_vat_rate: string;
}

export interface Lookups {
  departments: { id: number; name: string }[];
  suppliers: SupplierRef[];
  warehouses: { id: number; code: string; name: string }[];
  products: { id: number; sku: string; name: string; cost_price: string; unit?: { code: string }; track_batches: boolean; track_expiry: boolean; track_serials: boolean }[];
  expense_accounts: (AccountRef & { system_key: string | null })[];
  payment_accounts: AccountRef[];
  settings: ProcurementSettings;
}

let lookupCache: Lookups | null = null;

/** The pick-lists every procurement form needs, read once per session. */
export function useLookups(): { lookups: Lookups | null; error: string | null } {
  const [lookups, setLookups] = useState<Lookups | null>(lookupCache);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (lookupCache) return;
    api.get<{ data: Lookups }>("/erp/procurement/lookups")
      .then((r) => { lookupCache = r.data; setLookups(r.data); })
      .catch((e) => setError(e.message));
  }, []);

  return { lookups, error };
}

/** Forgets the cached pick-lists, e.g. after settings change. */
export function forgetLookups() {
  lookupCache = null;
}

export const PAYMENT_METHODS = ["bank_transfer", "cheque", "cash", "mobile_money"] as const;
