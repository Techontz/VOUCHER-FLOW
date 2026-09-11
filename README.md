# VouchFlow

A multi-tenant voucher approval SaaS. Employees raise vouchers; each company's own
approval route carries them through signing, approval and payment to a print-ready
A4 document, with every signature, comment and timestamp on the record.

```
backend/   Laravel 13 · Sanctum · MySQL    the system of record
web/       Next.js 16 (App Router) · TS    responsive web client
app/       Flutter · GetX                  mobile client
design/    the v2 design file              the UI/UX source of truth
```

Both clients talk to the **same** Laravel API, the same accounts and the same
database. There is no second backend.

```
Next.js  ─┐
          ├─→  Laravel REST API  ─→  MySQL (one database, many tenants)
Flutter  ─┘
```

---

## Running the whole system locally

You need PHP 8.3+, Composer, MySQL, Node 20+ and the Flutter SDK.

### 1. Backend

```sh
cd backend
composer install
cp .env.example .env && php artisan key:generate
mysql -uroot -e "CREATE DATABASE vouchflow CHARACTER SET utf8mb4"
php artisan migrate:fresh --seed        # schema + three demo tenants
php artisan storage:link                # serves company logos
php artisan serve                       # http://127.0.0.1:8000
```

### 2. Web

```sh
cd web
npm install
npm run dev                             # http://localhost:3000
```

`web/.env.local` already points at `http://127.0.0.1:8000/api`. Set
`NEXT_PUBLIC_API_MODE=mock` to run the in-browser fixture with no backend.

### 3. Mobile

```sh
cd app
flutter pub get
flutter run                             # talks to the API by default
```

The Android emulator reaches the host through `10.0.2.2`, which is the default
there. For a real device or a hosted API:

```sh
flutter run --dart-define=API_URL=https://api.example.com/api
flutter run --dart-define=API_MODE=mock     # offline, no backend
```

### Demo accounts

Password for every one of them: `Password123!`

| Role | Email | What they see |
| --- | --- | --- |
| Employee | `frank@watercom.test` | their own vouchers, nothing else |
| HOD | `joseph@watercom.test` | Procurement & Production — reviews and **signs**, never approves |
| HOD | `salum@watercom.test` | Transport & Logistics, Sales |
| Managing Director | `emmanuel@watercom.test` | company-wide; approves or rejects |
| Cashier | `mwajuma@watercom.test` | approved and unpaid; releases the money |
| Company Admin | `admin@watercom.test` | all of Watercom |
| Super Admin | `super@vouchflow.test` | all companies |

Two further tenants exist — **Zamani Logistics** (a five-step route with Finance
in the middle) and **Baobab Business Solutions** (on trial) — so tenant isolation
and configurable workflows are exercised against real variety rather than claimed.

---

## A dashboard is an action queue

The rule the product is built around: **a dashboard shows what is waiting on
*you*, right now.** Completing your step removes the voucher from your dashboard
and puts it on whoever is next. Finished work is found through Reports.

| Role | Their queue |
| --- | --- |
| Employee | drafts and vouchers returned for changes |
| HOD / approver | vouchers parked on a step they may act on |
| Cashier | approved and unpaid |
| Company Admin | what has **stalled** — three days on one step |

An empty dashboard therefore means the work is genuinely clear, not that nothing
has happened. Driven end to end, the queues move like this:

```
STAGE                       EMP  HOD  CEO  CASH
employee created draft        1    0    0     0
employee submitted            0    1    0     0
HOD signed and forwarded      0    0    1     0
CEO approved                  0    0    0     1
cashier paid                  0    0    0     0
```

## Reports are permission-aware

Reports are where history lives, so the catalogue is filtered per role **and** the
endpoint refuses what the catalogue withheld — a hidden card is not a control.

| Role | Scope ceiling | Reports offered |
| --- | --- | --- |
| Employee | their own vouchers | 2 |
| HOD | the departments they head | 7 |
| Cashier | company-wide, money released | 5 |
| MD / Admin | company-wide | 7 |

A department filter **narrows** the caller's ceiling and can never widen it, which
is enforced in the query rather than in the UI. Every report exports to PDF, Excel
and CSV.

## The core workflow

Watercom's default route, and the one a new tenant is provisioned with:

```
Employee          create → submit
  ↓
HOD               review → SIGN → submit onward      (never approves)
  ↓
CEO / Manager     APPROVE or REJECT
  ↓
Cashier           record payment → PAID
  ↓
Reports
```

**The HOD step carries no approve capability.** That is not a UI decision — the
step's `can_approve` flag is false, the API refuses the action with 422, and a
test holds it down.

Payment sits deliberately *outside* the approval chain. Advancing into a cashier
step would park a voucher in "under review" when the reviewing is finished; what
is outstanding at that point is a payment, and the status says so.

### It is configuration, not code

Nothing above is hard-coded. A workflow is a list of steps, and each step stores
what it may do: `sign`, `approve`, `reject`, `request_changes`, `print`,
`download`, `pay`, plus `requires_signature` and amount thresholds. A Company
Admin can rename a step, reorder it, pin it to a named person, or take a
capability away. Three presets ship; the builder composes any route.

## Multi-tenancy

One MySQL database, many companies, and the isolation is enforced in the query
layer rather than the UI.

- Every tenant-owned model uses `BelongsToTenant`, which adds a global scope and
  stamps `company_id` on create, so a controller cannot forget either.
- `TenantScope` **fails closed**: with no tenant resolved and no platform flag it
  matches nothing, so a missing middleware leaks no data rather than all of it.
- Route-model binding resolves *inside* the scope, so another company's voucher
  returns **404, not 403** — answering "forbidden" would confirm it exists.
- `VoucherVisibility` narrows further within a tenant: an employee sees only their
  own, an HOD only the departments they head.

## Authorisation

`app/Policies` is the single door every authorisation question goes through —
`VoucherPolicy`, `CompanyPolicy`, `WorkflowPolicy`. The policies delegate to the
services that own the rules rather than restating them, so the API, a console
command and a queued job all get the same answer.

The frontend never decides anything. It renders the `actions` map the API returns
with each voucher, and the API re-checks on every call.

## Bank and cash vouchers

They are different instruments and are kept apart end to end: different fields on
the form, different validation, different API payloads, different panels on the
printed document, and a payment report that splits them — because one reconciles
against a bank statement and the other against a float.

A bank voucher carries the payee's bank, account name, account number, branch and
cheque number, and prints the company's own "drawn on" account. A cash voucher
carries the float it came from and the name of whoever received the notes. Neither
is ever asked for the other's fields.

## The document

The A4 sheet is the same in all three places it appears — the web preview, the
mobile preview and the server-generated PDF: the tenant's letterhead and TIN, the
voucher type and number, a ruled particulars table with TOTAL PAYABLE, the amount
in words, a payment panel carrying only the particulars that format uses, and an
authorisation band with **Prepared by / Signed by / Approved by / Paid by** and
official SIGNED, APPROVED and PAID marks.

It stays white and print-friendly whatever theme the application is wearing,
because it is a financial document rather than a piece of the interface.

## Company branding

Everything the document needs is per-tenant and editable from the Branding screen:
logo lockup, square mark, legal name, address, phone, email, website, TIN,
registration number, primary and accent colour, voucher header and footer text,
and the company's banking details. The PDF reads them from the company row.

Watercom is seeded demo data through those same columns. Nothing about it is
special to the platform.

---

## What is included

**Database** — 21 migrations. Companies, plans, subscriptions and invoices;
departments, users and roles; voucher types, workflows and workflow steps;
vouchers, approvals, attachments and comments; notifications, audit logs and OTP
codes. Foreign keys throughout, indexes on the paths the queues actually query,
and soft deletes where history matters.

**API** — Sanctum token auth, 101 REST endpoints under `/api`, Form Request
validation, API Resources, policies, and services holding the business logic
(`WorkflowEngine`, `VoucherVisibility`, `VoucherPdfService`, `UsageLimits`,
`Notifier`, `AuditLogger`). Critical transitions — submit, sign, approve, reject,
pay — run in a database transaction.

**Auth** — register (provisions a whole tenant), login, logout, logout-all, OTP,
forgot/reset password, change password, session listing and revocation, profile,
and a saved signature a user can draw, upload, reuse, replace or delete.

**Web** — every role's screens, a typed API client with loading/empty/error
states, permission-aware rendering, route protection, the live A4 preview, the
workflow builder, branding, reports with exports, billing and the platform admin.

**Mobile** — GetX for state, routing, bindings and dependency injection; the
operational workflow for employee, HOD, manager and cashier, with the same
document renderer and signature capture.

## Tests

```sh
cd backend && php artisan test                 # 61 tests, 229 assertions
cd web && npx tsc --noEmit && npx next build
cd app && flutter analyze && flutter test      # 9 unit tests
cd app && flutter test integration_test/       # 4 on a device, against the API
```

The backend suite covers the full lifecycle draft → paid in both formats, tenant
isolation (including cross-tenant payment), employee privacy, report permissions
and the scope ceiling, the action-queue transitions, configurable workflows,
billing limits, and the printed document.

## Notes for production

- `CORS_ALLOWED_ORIGINS` is an explicit allowlist; set it to your front-end
  origins. Bearer tokens mean credentialed requests are never needed.
- Attachments are stored on the **private** disk and streamed through an
  authorised endpoint; they are never reachable by a predictable URL.
- Notifications are stored and read through the API. Email, push and WhatsApp
  transports are deliberately not wired: `Notifier` is the seam they attach to.
- `PaymentGateway` is the seam for a real payment provider. No secret belongs in
  either client.
- Run `php artisan config:cache route:cache` on deploy, and put the queue behind
  a real worker before enabling outbound notifications.
