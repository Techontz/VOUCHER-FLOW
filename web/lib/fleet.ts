"use client";

import { useEffect, useState } from "react";
import { api } from "./api";
import type { MessageKey } from "./i18n";
import type { JournalEntry } from "./erp";

/*
 * Fleet & transport: the shapes /api/erp/fleet returns, and the labels the
 * screens show for its states. The API decides; these only describe.
 */

export type VehicleStatus = "available" | "on_trip" | "maintenance" | "out_of_service";
export type TripStatus = "planned" | "dispatched" | "completed" | "closed" | "cancelled";
export type CostOption = "customer_vehicle" | "charged" | "included" | "hired";
export type EntryStatus = "pending" | "approved" | "rejected";
export type ExpenseType = "allowance" | "toll" | "parking" | "loading" | "other";

export interface Named { id: number; name: string }

export interface Vehicle {
  id: number; registration_number: string; make: string | null; model: string | null; type: string; year: number | null;
  capacity: string | null; capacity_unit: string; ownership: "owned" | "hired";
  supplier_id: number | null; supplier?: Named | null;
  hire_rate_basis: "per_trip" | "per_km" | "per_day" | null; hire_rate: string | null; hire_includes_fuel: boolean;
  odometer: string; status: VehicleStatus;
  insurance_policy_number: string | null; insurer: string | null; insurance_expiry: string | null;
  road_licence_number: string | null; road_licence_expiry: string | null;
  monthly_insurance: string; monthly_licence: string; monthly_depreciation: string; monthly_other_fixed: string;
  allocation_basis: "days" | "km"; expected_monthly_km: string | null;
  notes: string | null; is_active: boolean;
  driver?: Driver | null;
  monthly_fixed_cost?: number;
}

export interface Driver {
  id: number; user_id: number; user?: { id: number; name: string; email?: string; phone?: string | null } | null;
  licence_number: string; licence_class: string | null; licence_expiry: string | null; phone: string | null;
  vehicle_id: number | null; vehicle?: { id: number; registration_number: string } | null;
  daily_allowance: string; is_active: boolean; open_trips_count?: number;
}

export interface FuelStandard {
  id: number; vehicle_id: number | null; vehicle?: { id: number; registration_number: string } | null;
  origin: string | null; destination: string | null; basis: "per_100km" | "per_trip";
  litres: string; tolerance_percent: string; notes: string | null; is_active: boolean;
}

interface Entry {
  id: number; trip_id: number; status: EntryStatus; amount: string; receipt_number: string | null;
  account_id: number | null; supplier_id: number | null;
  account?: { id: number; code: string; name: string } | null; supplier?: Named | null;
  recorder?: Named | null; approver?: Named | null; approved_at: string | null; rejection_reason: string | null;
  trip?: { id: number; number: string; origin?: string; destination?: string; fuel_over_standard?: boolean } | null;
}

export interface FuelIssue extends Entry {
  vehicle_id: number | null; vehicle?: { id: number; registration_number: string } | null;
  issue_date: string; litres: string; price_per_litre: string; station: string | null; odometer: string | null;
}

export interface TripExpense extends Entry {
  type: ExpenseType; description: string | null; expense_date: string; quantity: string; rate: string;
}

export interface TripCosts {
  revenue: number; fuel: number; expenses: number; hire: number; fixed: number;
  total_cost: number; profit: number; pending: number; distance_km: number; days: number;
}

export interface Trip {
  id: number; number: string; cost_option: CostOption; status: TripStatus;
  vehicle_id: number | null; vehicle?: (Partial<Vehicle> & { id: number; registration_number: string }) | null;
  driver_id: number | null; driver?: Driver | null;
  external_vehicle: string | null; customer_id: number | null; customer?: { id: number; code?: string; name: string } | null;
  origin: string; destination: string; distance_km: string;
  planned_start: string; planned_end: string | null; actual_start: string | null; actual_end: string | null;
  odometer_out: string | null; odometer_in: string | null;
  source_type: string | null; source_id: number | null; source_reference: string | null; cargo_description: string | null;
  transport_charge: string; hire_cost: string;
  standard_litres: string | null; actual_litres: string | null; fuel_variance_percent: string | null;
  fuel_tolerance_percent: string | null; fuel_over_standard: boolean;
  variance_approved_by: number | null; variance_approved_at: string | null; variance_note: string | null;
  variance_approver?: Named | null;
  notes: string | null; cancel_reason: string | null; created_at: string; closed_at: string | null;
  creator?: Named | null; closer?: Named | null;
  fuel_issues?: FuelIssue[]; expenses?: TripExpense[];
  allocations?: { id: number; period: string; basis: string; share: string; period_units: string; monthly_fixed_cost: string; amount: string }[];
  costs?: TripCosts;
  standard?: { id: number; basis: string; litres: string; tolerance_percent: string; origin: string | null; destination: string | null; vehicle_id: number | null } | null;
  journals?: JournalEntry[];
  timeline?: { id: number; action: string; description: string; actor_name: string; created_at: string }[];
}

export interface Schedule {
  id: number; vehicle_id: number; vehicle?: { id: number; registration_number: string; odometer?: string } | null;
  title: string; interval_km: number | null; interval_days: number | null;
  last_done_odometer: string | null; last_done_date: string | null; next_due_odometer: string | null; next_due_date: string | null;
  is_active: boolean; state?: "ok" | "due" | "overdue";
}

export interface ServiceRecord {
  id: number; number: string; vehicle_id: number; vehicle?: { id: number; registration_number: string } | null;
  schedule_id: number | null; schedule?: { id: number; title: string } | null;
  service_date: string; odometer: string | null; work_done: string; cost: string;
  supplier_id: number | null; supplier?: Named | null; account_id: number | null; invoice_number: string | null;
  status: "draft" | "posted" | "cancelled"; creator?: Named | null; posted_at: string | null;
}

export interface Tyre {
  id: number; vehicle_id: number; vehicle?: { id: number; registration_number: string; odometer?: string } | null;
  position: string; serial_number: string; brand: string | null; size: string | null; cost: string;
  fitted_date: string; fitted_odometer: string; removed_date: string | null; removed_odometer: string | null; removal_reason: string | null;
}

export interface Downtime {
  id: number; vehicle_id: number; vehicle?: { id: number; registration_number: string } | null;
  reason: "maintenance" | "breakdown" | "accident" | "other"; description: string | null;
  started_at: string; ended_at: string | null; hours?: number;
}

export interface Lookups {
  vehicles?: { id: number; registration_number: string; make: string | null; model: string | null; ownership: "owned" | "hired"; status: VehicleStatus; odometer: string; hire_includes_fuel: boolean; hire_rate_basis: string | null; hire_rate: string | null; supplier_id: number | null }[];
  drivers?: { id: number; name: string; vehicle_id: number | null; daily_allowance: string; licence_expiry: string | null }[];
  customers?: { id: number; code: string; name: string }[];
  suppliers: { id: number; code: string; name: string; category: string | null }[];
  accounts: { id: number; code: string; name: string }[];
}

export interface Overview {
  vehicles: { total: number; by_status: Record<VehicleStatus, number> };
  trips_today: Trip[];
  fuel_alerts: Trip[];
  expiring: { kind: "insurance" | "road_licence" | "driving_licence"; subject: string; vehicle_id: number | null; driver_id: number | null; date: string; expired: boolean }[];
  maintenance_due: Schedule[];
  pending_entries: number;
  month: { trips_closed: number; revenue: number; cost: number; profit: number; litres: number };
}

export const TRIP_STATUSES: TripStatus[] = ["planned", "dispatched", "completed", "closed", "cancelled"];
export const COST_OPTIONS: CostOption[] = ["charged", "included", "hired", "customer_vehicle"];
export const VEHICLE_STATUSES: VehicleStatus[] = ["available", "on_trip", "maintenance", "out_of_service"];
export const EXPENSE_TYPES: ExpenseType[] = ["allowance", "toll", "parking", "loading", "other"];
export const VEHICLE_TYPES = ["truck", "trailer", "tanker", "van", "pickup", "car", "motorcycle", "other"] as const;

export const TRIP_STATUS_LABEL: Record<TripStatus, MessageKey> = {
  planned: "fltStatusPlanned", dispatched: "fltStatusDispatched", completed: "fltStatusCompleted",
  closed: "fltStatusClosed", cancelled: "fltStatusCancelled",
};

export const TRIP_STATUS_TONE: Record<TripStatus, "neutral" | "info" | "ok" | "warn" | "bad"> = {
  planned: "neutral", dispatched: "info", completed: "warn", closed: "ok", cancelled: "neutral",
};

export const VEHICLE_STATUS_LABEL: Record<VehicleStatus, MessageKey> = {
  available: "fltVehicleAvailable", on_trip: "fltVehicleOnTrip", maintenance: "fltVehicleMaintenance", out_of_service: "fltVehicleOut",
};

export const VEHICLE_STATUS_TONE: Record<VehicleStatus, "neutral" | "info" | "ok" | "warn" | "bad"> = {
  available: "ok", on_trip: "info", maintenance: "warn", out_of_service: "bad",
};

export const COST_OPTION_LABEL: Record<CostOption, MessageKey> = {
  customer_vehicle: "fltOptCustomer", charged: "fltOptCharged", included: "fltOptIncluded", hired: "fltOptHired",
};

export const COST_OPTION_HINT: Record<CostOption, MessageKey> = {
  customer_vehicle: "fltOptCustomerHint", charged: "fltOptChargedHint", included: "fltOptIncludedHint", hired: "fltOptHiredHint",
};

export const EXPENSE_LABEL: Record<ExpenseType, MessageKey> = {
  allowance: "fltExpAllowance", toll: "fltExpToll", parking: "fltExpParking", loading: "fltExpLoading", other: "fltExpOther",
};

export const ENTRY_LABEL: Record<EntryStatus, MessageKey> = {
  pending: "fltEntryPending", approved: "fltEntryApproved", rejected: "fltEntryRejected",
};

export const ENTRY_TONE: Record<EntryStatus, "warn" | "ok" | "bad"> = { pending: "warn", approved: "ok", rejected: "bad" };

export const HIRE_BASIS_LABEL: Record<string, MessageKey> = { per_trip: "fltPerTrip", per_km: "fltPerKm", per_day: "fltPerDay" };

export const DOWNTIME_LABEL: Record<Downtime["reason"], MessageKey> = {
  maintenance: "fltDownMaintenance", breakdown: "fltDownBreakdown", accident: "fltDownAccident", other: "fltExpOther",
};

/** Kilometres and litres with at most one decimal, grouped. */
export function km(value: string | number | null | undefined): string {
  return Number(value ?? 0).toLocaleString("en-US", { maximumFractionDigits: 1 });
}

/** A `datetime-local` value for an ISO string, in the browser's time. */
export function localInput(value?: string | null): string {
  const d = value ? new Date(value) : new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** The pick-lists a fleet form needs; drivers read the smaller set for their own trips. */
export function useFleetLookups(mine = false) {
  const [lookups, setLookups] = useState<Lookups | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.get<{ data: Lookups }>(mine ? "/erp/fleet/my-trips/lookups" : "/erp/fleet/lookups")
      .then((r) => setLookups(r.data)).catch((e) => setError(e.message));
  }, [mine]);
  return { lookups, error };
}
