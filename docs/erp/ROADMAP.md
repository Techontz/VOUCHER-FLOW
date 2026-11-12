# Universal ERP, phased plan

Each phase ships complete: migrations, services with the posting rules, permissions, audit
trail, web screens, mobile screens where the role works on a phone, automated tests for that
phase's acceptance criteria, and demo data. Nothing ships as a screen without the rules behind it.

Estimates are for one senior full-stack engineer and assume the Phase 1 foundations
(tenancy, module/permission gates, stock ledger, journal poster, numbering) are reused as-is.
Two engineers in parallel roughly halve calendar time from Phase 3 on, because Fleet and HR
depend on the core but not on each other.

| Phase | Scope | Status | Estimate |
| --- | --- | --- | --- |
| 0 | VouchFlow: vouchers, configurable workflows, HOD signature, CEO approval, cashier payment, A4 PDF, reports | Live |: |
| 1 | Core ERP: business setup & templates, configurable roles, inventory & warehouses, customers & suppliers, accounting foundation; liquid-glass redesign | **Live** (this release) |: |
| 2 | Sales & dispatch, procurement | Next | 6–8 weeks |
| 3 | Fleet & transport | | 4–5 weeks |
| 4 | HR Flow & payroll | | 6–8 weeks |
| 5 | VouchFlow ↔ ERP integration | | 2–3 weeks |
| 6 | Production, industry templates, CRM, assets, documents, advanced reports | | 8–10 weeks |

## Phase 2: Sales, dispatch & procurement

**Sales**: quotations → sales orders → invoices; price lists and customer pricing; credit-limit
and prepayment policy; receipts; returns and credit notes; statements and aged receivables.

**Finance verification & dispatch** (spec §7): order → stock check → invoice/payment request →
payment recorded and verified by finance → loading order → actual loaded quantities →
signatures → delivery note → gate pass → proof of delivery. Ordered, approved, loaded and
received quantities are four columns, not one. **Stock is issued at loading confirmation, once**
the ledger's existing exactly-once guarantee carries it.

**Procurement**: requisitions → approval → quotations and comparison → purchase order → GRN
(exists) → supplier invoice matched against PO and GRN (clears GRNI) → payable. Service lines
for repairs, rent and insurance with no stock item.

Accounting additions: AR/AP sub-ledgers, receipts and payments, VAT on invoices, bank accounts.

Acceptance: 3, 4, 5, 6, 9. Risk: the finance-verification flow touches four roles and needs the
client's real sign-off order before build: **one workshop with Watercom first**.

## Phase 3: Fleet & transport

Vehicle register (owned/hired), drivers, trips linked to orders and loading orders, mileage,
fuel issue and consumption standards per vehicle/route with variance alerts, trip expenses and
allowances, the four transport cost options (customer's vehicle, company vehicle charged,
transport included in price, hired vehicle), maintenance schedules, tyres, insurance and licence
expiry, downtime, and trip profitability with configurable allocation of fixed costs.

Acceptance: 7, 8. Risk: fixed-cost allocation rules (insurance, maintenance) must be agreed with
finance so costs are allocated once, design the allocation table before the reports.

## Phase 4: HR Flow & payroll

Employee records (extending `users`), contracts, departments and transfers; recruitment and
onboarding; attendance, shifts, overtime (biometric import as a file first); leave types,
balances and approvals; payroll with allowances, deductions, loans and advances, **statutory
rules configurable by country and effective date** (Tanzania: PAYE, NSSF, WCF, SDL, HESLB),
preview → authorise → lock → post; payslips; self-service; appraisals, training, discipline,
exit and clearance.

Acceptance: 10, 13 (HR). Risks: statutory rates change, they must be data with effective dates,
never code; salary and disciplinary data need field-level permissions beyond module gates.

## Phase 5: VouchFlow integration

A payment voucher raised *from* a supplier invoice, fuel request, repair, insurance renewal,
petty-cash top-up or employee advance, carrying a reference back to its source. HOD signature
and CEO approval stay VouchFlow's existing workflow. Cashier payment posts Dr payable / Cr bank
(or cash) through the journal poster, keyed to the voucher so it posts once. A rejected voucher
can never be paid (already enforced).

Acceptance: 9, 11, 12 end to end. Risk: low, both sides already exist; the work is the links.

## Phase 6: Production, templates & breadth

Bills of materials, production orders, material issue (the existing issue document), WIP,
finished goods receipt with QC, wastage, batch genealogy and production costing; deeper
templates; CRM pipeline; asset register with depreciation posting; document management with
retention and access control; report builder and exports; period closing, P&L, balance sheet,
cash flow.

## Cross-cutting, every phase

- Each module behind `module:` and `permission:` gates; a role matrix row per new permission.
- Postings only through `StockLedger` / `JournalPoster`, keyed to their source document.
- Tests for the phase's acceptance criteria and tenant isolation of every new table.
- Backup and restore rehearsal before the first production tenant uses accounting.

## Known gaps today

- The Flutter app does not compile on Flutter 3.47: `phosphor_flutter 2.1.0` extends the now
  final `IconData`. Needs a dependency upgrade or override (decision pending).
- ERP screens are on the web only; the mobile app has the redesign but not yet ERP screens
  (planned with Phase 2, starting with stock lookup, counts and GRN capture for storekeepers).
- The web's in-browser mock mode does not cover ERP endpoints; ERP screens need the live API.
