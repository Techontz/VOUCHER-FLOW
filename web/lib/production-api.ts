"use client";

import { useEffect, useState } from "react";
import { api } from "./api";
import type { Unit } from "./erp";

/*
 * Shapes the /api/erp/production endpoints return, and the pick lists every
 * production form shares.
 */

export type OrderStatus = "planned" | "released" | "in_progress" | "completed" | "closed" | "cancelled";
export type ReceiptStatus = "pending_qc" | "released" | "rejected";

export const ORDER_STATUSES: OrderStatus[] = ["planned", "released", "in_progress", "completed", "closed", "cancelled"];

export interface ProductOption {
  id: number; sku: string; name: string; type: string; unit_id: number; cost_price: string;
  track_batches: boolean; track_expiry: boolean; unit?: Pick<Unit, "id" | "code" | "name" | "allows_decimals">;
}

export interface WorkCentre {
  id: number; code: string; name: string; description: string | null;
  capacity_per_hour: string | null; hourly_cost: string; is_active: boolean; boms_count?: number;
}

export interface ProductionOptions {
  finished: ProductOption[];
  materials: ProductOption[];
  warehouses: { id: number; code: string; name: string; type: string }[];
  work_centres: Pick<WorkCentre, "id" | "code" | "name" | "hourly_cost">[];
}

export interface BomLine {
  id: number; product_id: number; quantity: string; scrap_percent: string; note: string | null;
  product?: ProductOption;
}

export interface StandardCost {
  materials: number; conversion: number; unit_cost: number;
  lines: { product_id: number; per_unit: number; unit_cost: number; cost_per_unit: number }[];
}

export interface Bom {
  id: number; product_id: number; version: number; name: string; output_quantity: string;
  work_centre_id: number | null; labour_cost: string; overhead_cost: string; is_active: boolean;
  notes: string | null; created_at: string; activated_at: string | null;
  product?: ProductOption; work_centre?: Pick<WorkCentre, "id" | "code" | "name"> | null;
  lines?: BomLine[]; lines_count?: number; orders_count?: number; standard_cost?: number;
  standard?: StandardCost; creator?: { id: number; name: string } | null;
  versions?: { id: number; version: number; name: string; is_active: boolean; created_at: string }[];
}

export interface Requirement {
  product_id: number;
  product: { id: number; sku: string; name: string; track_batches: boolean; track_expiry: boolean; unit: string | null; allows_decimals: boolean };
  per_unit: number; scrap_percent: number;
  standard_quantity: number; allowance_quantity: number; required_quantity: number;
  issued_quantity: number; issued_value: number; remaining_quantity: number;
  available_quantity: number; shortfall_quantity: number; sufficient: boolean;
  allowed_for_output: number; excess_quantity: number; excess_value: number;
  batches: { batch_number: string; expiry_date: string | null; quantity: number }[];
}

export interface QcParameter { name: string; target: string | null; value: string | null; passed: boolean }

export interface QcCheck {
  id: number; production_receipt_id: number; decision: "release" | "reject"; parameters: QcParameter[];
  notes: string | null; checked_at: string; inspector?: { id: number; name: string } | null;
}

export interface Receipt {
  id: number; production_order_id: number; number: string; receipt_date: string;
  produced_quantity: string; good_quantity: string; rejected_quantity: string; wastage_quantity: string;
  released_quantity: string; batch_number: string | null; expiry_date: string | null; is_final: boolean;
  status: ReceiptStatus; conversion_cost: string; unit_cost: string | null; value: string | null;
  stock_document_id: number | null; notes: string | null; created_at: string;
  qc?: QcCheck | null; recorder?: { id: number; name: string } | null;
  stock_document?: { id: number; number: string; status: string } | null;
  order?: { id: number; number: string; product?: { id: number; sku: string; name: string }; output_warehouse?: { id: number; name: string } };
}

export interface Costing {
  standard_unit_cost: number; standard_total_for_planned: number; standard_total_for_released: number;
  material_cost: number; conversion_cost: number; actual_total: number; actual_unit_cost: number | null;
  received_value: number; wip_balance: number; variance_value: number | null;
  variance_against_standard: number | null; yield_percent: number | null;
}

export interface IssueDoc {
  id: number; number: string; document_date: string; status: string; reason: string | null; posted_at: string | null;
  creator: { id: number; name: string } | null; value: number;
  lines: { product: { id: number; sku: string; name: string } | null; quantity: number; batch_number: string | null }[];
}

type Person = { id: number; name: string } | null;

export interface ProductionOrder {
  id: number; number: string; product_id: number; bom_id: number; planned_quantity: string;
  materials_warehouse_id: number; output_warehouse_id: number; planned_start: string; planned_end: string;
  status: OrderStatus; reference: string | null; notes: string | null; standard_unit_cost: string | null;
  produced_quantity: string; good_quantity: string; released_quantity: string; rejected_quantity: string;
  wastage_quantity: string; material_cost: string; conversion_cost: string; received_value: string;
  variance_value: string | null; created_at: string; released_at: string | null; started_at: string | null;
  completed_at: string | null; closed_at: string | null; cancelled_at: string | null; cancel_reason: string | null;
  product?: ProductOption; bom?: Pick<Bom, "id" | "version" | "name" | "output_quantity" | "labour_cost" | "overhead_cost" | "work_centre">;
  materials_warehouse?: { id: number; code: string; name: string }; output_warehouse?: { id: number; code: string; name: string };
  receipts?: Receipt[]; requirements?: Requirement[]; costing?: Costing; issues?: IssueDoc[];
  creator?: Person; releaser?: Person; completer?: Person; closer?: Person; canceller?: Person;
}

export interface Overview {
  days: number;
  by_status: Record<OrderStatus, number>;
  open_orders: number;
  today: { produced: number; released: number; receipts: number };
  qc_pending: number;
  period: {
    produced: number; released: number; rejected: number; wastage: number;
    yield_percent: number | null; wastage_percent: number | null;
    materials_issued_value: number; variance_closed: number;
  };
  trend: { date: string; produced: number; released: number; wastage: number }[];
  by_product: { product_id: number; name: string; sku: string; produced: number; released: number; wastage: number; yield_percent: number | null }[];
  recent_orders: Pick<ProductionOrder, "id" | "number" | "product_id" | "planned_quantity" | "released_quantity" | "status" | "planned_start" | "planned_end" | "product">[];
}

export interface GenealogyBatch {
  id: number; number: string; batch_number: string | null; expiry_date: string | null; receipt_date: string | null;
  status: ReceiptStatus; good_quantity: number; released_quantity: number;
}

export interface Genealogy {
  batch: string;
  as_finished: {
    receipt: GenealogyBatch; order: { id: number; number: string; status: OrderStatus };
    product: { id: number; sku: string; name: string } | null;
    materials: { product: { id: number; sku: string; name: string } | null; batch_number: string | null; quantity: number; value: number; references: string[] }[];
  }[];
  as_material: {
    order: { id: number; number: string; status: OrderStatus } | null;
    product: { id: number; sku: string; name: string } | null;
    material: { id: number; sku: string; name: string } | null;
    quantity: number; documents: string[]; finished_batches: GenealogyBatch[];
  }[];
}

let optionsCache: ProductionOptions | null = null;

/** Products, warehouses and work centres for production forms, read once per page load. */
export function useProductionOptions() {
  const [options, setOptions] = useState<ProductionOptions | null>(optionsCache);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (optionsCache) return;
    api.get<{ data: ProductionOptions }>("/erp/production/options")
      .then((r) => { optionsCache = r.data; setOptions(r.data); })
      .catch((e) => setError(e.message));
  }, []);

  return { options, error, refresh: () => { optionsCache = null; } };
}

/** Forgets the cached pick lists, e.g. after a work centre is added. */
export function forgetProductionOptions() {
  optionsCache = null;
}

export function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00`);
  d.setDate(d.getDate() + days);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
