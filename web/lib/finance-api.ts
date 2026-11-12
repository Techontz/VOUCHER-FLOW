"use client";

import { download, saveBlob } from "./api";

/*
 * Shapes the /api/erp/finance and /api/erp/assets endpoints return, and the
 * small helpers the finance screens share.
 */

export type FinStatus = "draft" | "posted" | "reversed" | "cancelled";
export type BankType = "bank" | "mobile_money" | "cash";

export interface Person { id: number; name: string }
export interface AccountRef { id: number; code: string; name: string; type?: string }

export interface BankAccount {
  id: number; account_id: number; name: string; type: BankType;
  bank_name: string | null; branch: string | null; account_name: string | null; account_number: string | null;
  currency: string; opening_balance: string; opening_date: string | null; opening_entry_id: number | null;
  is_active: boolean; notes: string | null; balance?: number; account?: AccountRef;
}

export interface LedgerRow {
  id: number; debit: string; credit: string; description: string | null; journal_entry_id: number;
  entry_date: string; number: string; memo: string; source_type: string | null; source_id: number | null;
  reconciled: boolean; balance: number;
}

export interface BankAccountDetail extends BankAccount {
  statement: { from: string; to: string; opening: number; closing: number; lines: LedgerRow[] };
  reconciliations: Reconciliation[];
  opening_entry?: { id: number; number: string } | null;
}

export interface JournalLineRow { id: number; account_id: number; debit: string; credit: string; description: string | null; account?: AccountRef }
export interface JournalRef { id: number; number: string; entry_date?: string; lines?: JournalLineRow[] }

export interface BankTransfer {
  id: number; number: string; transfer_date: string; from_bank_account_id: number; to_bank_account_id: number;
  amount: string; charges: string; reference: string | null; memo: string | null; status: FinStatus;
  from?: BankAccount; to?: BankAccount; creator?: Person | null; poster?: Person | null; reverser?: Person | null;
  posted_at: string | null; reversed_at: string | null; reversal_reason: string | null; journal?: JournalRef | null;
}

export type CashbookType = "receipt" | "payment";

export interface CashbookEntry {
  id: number; number: string; type: CashbookType; entry_date: string; bank_account_id: number; account_id: number;
  amount: string; counterparty: string | null; reference: string | null; description: string; status: FinStatus;
  bank_account?: BankAccount; account?: AccountRef; creator?: Person | null; poster?: Person | null; reverser?: Person | null;
  posted_at: string | null; reversed_at: string | null; reversal_reason: string | null; journal?: JournalRef | null; created_at: string;
}

export interface StatementLine {
  id: number; line_date: string; description: string; reference: string | null; amount: string;
  journal_line_id: number | null; matched_at: string | null;
  journal_line?: { id: number; entry?: { id: number; number: string; entry_date: string; memo: string } } | null;
  suggestions: { journal_line_id: number; entry_date: string; number: string; memo: string; amount: number; days: number }[];
}

export interface OutstandingItem { id: number; debit: string; credit: string; description: string | null; entry_date: string; number: string; memo: string; amount: number }

export interface ReconciliationSummary {
  book_balance: number; cleared_balance: number; statement_opening_balance: number; statement_closing_balance: number;
  statement_lines_total: number; statement_lines_difference: number; matched_count: number;
  unmatched_statement_count: number; unmatched_statement_total: number; deposits_in_transit: number;
  outstanding_payments: number; adjusted_bank_balance: number; adjusted_book_balance: number; difference: number;
}

export interface Reconciliation {
  id: number; number: string; bank_account_id: number; statement_date: string;
  statement_opening_balance: string; statement_closing_balance: string; status: "open" | "completed";
  notes: string | null; completed_at: string | null; lines_count?: number;
  bank_account?: BankAccount; creator?: Person | null; completer?: Person | null;
}

export interface ReconciliationDetail extends Reconciliation {
  lines: StatementLine[]; outstanding: OutstandingItem[]; summary: ReconciliationSummary;
}

export interface PlRow { account_id: number; code: string; name: string; type: string; section: string; amount: number; prior: number }
export interface PlTotals { income: number; cost_of_sales: number; gross_profit: number; operating_expenses: number; expenses: number; net_profit: number }
export interface ProfitAndLoss { from: string; to: string; prior_from: string; prior_to: string; rows: PlRow[]; totals: PlTotals; prior_totals: PlTotals }

export interface BsRow { account_id: number; code: string; name: string; type: string; section: string; amount: number }
export interface BalanceSheet {
  as_of: string; rows: BsRow[]; current_earnings: number; balanced: boolean;
  totals: { current_assets: number; non_current_assets: number; assets: number; current_liabilities: number; non_current_liabilities: number; liabilities: number; equity: number; liabilities_and_equity: number };
}

export interface CfRow { account_id: number; code: string; name: string; type: string; activity: "operating" | "investing" | "financing"; amount: number }
export interface CashFlow {
  method: "direct"; from: string; to: string; rows: CfRow[]; reconciles: boolean;
  totals: { operating: number; investing: number; financing: number; net_change: number; opening_cash: number; closing_cash: number };
}

export interface BudgetRow { account_id: number; code: string; name: string; type: string; budget: number; actual: number; variance: number; used_percent: number | null }
export interface BudgetVsActual {
  fiscal_year: number; through_month: number; from: string; to: string; has_budget: boolean; rows: BudgetRow[];
  totals: { income_budget: number; income_actual: number; expense_budget: number; expense_actual: number; net_budget: number; net_actual: number };
}

export interface PeriodMonth {
  period: string; starts_on: string; ends_on: string; status: "open" | "closed"; ended: boolean; entries: number;
  closed_at: string | null; closed_by: string | null; reopened_at: string | null; reopened_by: string | null; reopen_reason: string | null;
}

export interface PeriodsYear {
  fiscal_year: number; starts_on: string; ends_on: string; months: PeriodMonth[]; can_close_year: boolean;
  year_end: { id: number; fiscal_year: number; net_profit: string; created_at: string; closer?: Person | null; journal?: { id: number; number: string } | null } | null;
  closed_years: { id: number; fiscal_year: number; net_profit: string; journal_entry_id: number | null; created_at: string }[];
}

export interface FinanceOverview {
  cash: { account_id: number; code: string; name: string; bank_account_id: number | null; type: BankType; is_active: boolean; balance: number }[];
  cash_total: number; receivables: number; payables: number;
  month: { from: string; to: string; totals: PlTotals; prior_totals: PlTotals };
  periods: { current: string; current_closed: boolean; last_closed: string | null };
  drafts: { cashbook: number; transfers: number };
  open_reconciliations: { id: number; number: string; bank_account_id: number; statement_date: string; bank_account?: { id: number; name: string } }[];
  recent: CashbookEntry[];
}

/* ───────────────────────────────────────────────────────── assets ── */

export type AssetMethod = "straight_line" | "reducing_balance";
export type AssetStatus = "draft" | "active" | "disposed";

export interface AssetClass {
  id: number; code: string; name: string; method: AssetMethod; useful_life_months: number; rate: string;
  asset_account_id: number; depreciation_account_id: number; expense_account_id: number; is_active: boolean;
  asset_account?: AccountRef; depreciation_account?: AccountRef; expense_account?: AccountRef; assets_count?: number;
}

export interface FixedAsset {
  id: number; tag: string; name: string; description: string | null; asset_class_id: number; serial_number: string | null;
  location: string | null; custodian_user_id: number | null; supplier_id: number | null; acquisition_date: string;
  cost: string; residual_value: string; method: AssetMethod; useful_life_months: number; rate: string;
  accumulated_depreciation: string; status: AssetStatus; funding: string | null; funding_bank_account_id: number | null;
  capitalised_at: string | null; disposal_date: string | null; disposal_proceeds: string | null; disposal_gain_loss: string | null;
  disposal_reason: string | null; asset_class?: AssetClass; custodian?: Person | null;
}

export interface AssetEvent {
  id: number; type: string; event_date: string; from_location: string | null; to_location: string | null;
  amount: string | null; notes: string | null; journal_entry_id: number | null;
  user?: Person | null; from_custodian?: Person | null; to_custodian?: Person | null;
}

export interface ScheduleRow { period: string; opening: number; amount: number; closing: number; posted: boolean }

export interface FixedAssetDetail extends FixedAsset {
  book_value: number; schedule: ScheduleRow[]; events: AssetEvent[];
  depreciation: { id: number; period: string; amount: string; run?: { id: number; number: string; period: string } }[];
  supplier?: { id: number; code: string; name: string } | null;
  funding_bank_account?: { id: number; name: string } | null; disposal_bank_account?: { id: number; name: string } | null;
  creator?: Person | null;
}

export interface DepreciationLine { fixed_asset_id: number; tag: string; name: string; class: string | null; period: string; opening: number; amount: number; closing: number }
export interface DepreciationPreview { period: string; run_date: string; already_run: boolean; lines: DepreciationLine[]; total: number; assets_count: number }
export interface DepreciationRun {
  id: number; number: string; period: string; run_date: string; total: string; assets_count: number;
  creator?: Person | null; journal?: { id: number; number: string } | null;
  lines?: { id: number; period: string; amount: string; opening_value: string; closing_value: string; asset?: { id: number; tag: string; name: string } }[];
}

export interface AssetsOverview {
  counts: { draft: number; active: number; disposed: number };
  cost: number; accumulated: number; book_value: number;
  by_class: { id: number; code: string; name: string; count: number; cost: number; book_value: number }[];
  latest_run: DepreciationRun | null; next_period: string | null; next_due: number;
  disposed_this_year: { id: number; tag: string; name: string; disposal_date: string; disposal_proceeds: string; disposal_gain_loss: string }[];
}

export interface AssetLookups { users: (Person & { job_title?: string | null })[]; suppliers: { id: number; code: string; name: string }[]; locations: string[] }

/* ──────────────────────────────────────────────────────── helpers ── */

export const today = () => new Date().toISOString().slice(0, 10);

export function monthStart(offset = 0): string {
  const d = new Date();
  return new Date(Date.UTC(d.getFullYear(), d.getMonth() + offset, 1)).toISOString().slice(0, 10);
}

export function monthEnd(offset = 0): string {
  const d = new Date();
  return new Date(Date.UTC(d.getFullYear(), d.getMonth() + offset + 1, 0)).toISOString().slice(0, 10);
}

export function currentPeriod(offset = 0): string {
  return monthStart(offset).slice(0, 7);
}

/** "2026-03" as "Mar 2026" in the reader's language. */
export function periodLabel(period: string, locale: "en" | "sw" = "en"): string {
  const [y, m] = period.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { month: "short", year: "numeric", timeZone: "UTC" });
}

/** Fetches a statement as CSV from the API and saves it. */
export async function exportCsv(path: string, query: Record<string, string | number | undefined>, filename: string) {
  const blob = await download(path, { ...query, format: "csv" });
  saveBlob(blob, filename);
}

/** Debit-positive amount of a ledger line. */
export function net(line: { debit: string | number; credit: string | number }): number {
  return Number(line.debit) - Number(line.credit);
}
