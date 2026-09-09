# VouchFlow

A multi-tenant voucher approval SaaS. Employees raise vouchers; each company's own
approval route carries them through signing, approval and payment to a print-ready
A4 document, with every signature, comment and timestamp on the record.

Built from the VouchFlow v2 design as the UI source of truth.

```
web/       Next.js 16 (App Router) · TS    responsive web client
app/       Flutter · GetX                  mobile client
backend/   Laravel 13 API · MySQL          the system of record (Phase 2)
design/    the v2 design file              the UI/UX source of truth
```

---

## Phase 1 — the frontend prototype

**Both clients currently run entirely on local mock data. Nothing is connected to
Laravel, MySQL, a payment provider or any other service.** Every screen and every
workflow is live and interactive; the data simply lives in the browser tab (web)
or in memory (mobile) instead of on a server.

This is deliberate: the prototype exists to be shown and approved before backend
integration begins.

### How the seam is drawn

The mock is a *transport*, not a fake sprinkled through the UI. No component,
controller or model knows it exists.

| | web | mobile |
| --- | --- | --- |
| Public surface | `api.get / post / put / delete` in `web/lib/api.ts` | `ApiService.get / post / put / delete` |
| Phase 1 transport | `web/lib/mock/router.ts` | `app/lib/app/data/mock/mock_api.dart` |
| Switch to live | `NEXT_PUBLIC_API_MODE=live` | `--dart-define=API_MODE=live` |

The mock answers **the same paths, verbs and JSON shapes** the Laravel API serves
(`GET /vouchers`, `POST /vouchers/{id}/sign`, `POST /vouchers/{id}/pay`, …). Phase 2
is therefore a transport swap and a base URL — not a UI rewrite.

Two things are honestly absent rather than faked, because they are produced
server-side: **file upload** and **server-generated PDF/Excel exports**. In their
place the prototype prints the real A4 sheet through the browser (which is also
how a reader saves it as a PDF) and builds report CSVs from the report on screen.

### Running the prototype

```sh
cd web && npm install && npm run dev     # http://localhost:3000
cd app && flutter pub get && flutter run
```

No database, no API, no configuration.

### Demo accounts

Password for all of them: `Password123!`

| Role | Email | What they can do |
| --- | --- | --- |
| Employee | `frank@watercom.test` | Raises vouchers; sees **only their own** (Procurement) |
| Employee | `baraka@watercom.test` | The same, for Transport & Logistics |
| HOD | `joseph@watercom.test` | Reviews and **signs** — never approves (Procurement, Production) |
| HOD | `salum@watercom.test` | The same, for Transport & Logistics and Sales |
| HOD | `anna@watercom.test` | The same, for Human Resources |
| Managing Director | `emmanuel@watercom.test` | Approves or rejects — the final decision |
| Cashier | `mwajuma@watercom.test` | Releases the funds and records the reference |
| Company Admin | `admin@watercom.test` | Runs Watercom (T) Limited end to end |
| Super Admin | `super@vouchflow.test` | Runs the platform, across all companies |

The first tenant is **Watercom (T) Limited**, a beverage manufacturer, carrying
its own logo, letterhead, banking details and colour. None of that is baked into
the platform — it is what a company fills in under Branding, and the printed
voucher picks it up automatically. Two further tenants are seeded: one on a
four-step route with Finance between the HOD and the CEO, and one on an expiring
trial, so per-company workflows and the renewal path are both visible.

To start over from the seeded data, sign out and clear the site's storage; the web
client keeps its state under `vouchflow.mock.v2` in `localStorage`.

---

---

## A dashboard is an action queue

Every dashboard shows one thing: the work that is on that person right now.

When a user acts, the voucher moves to whoever is next in the route and **leaves
their dashboard**. An employee's queue is their own drafts and returns; a head
of department's is what has actually reached their step; the cashier's is what is
approved and unpaid; an administrator's is whatever has stalled. Completed work
never sits on a dashboard — it is found through Reports, which are themselves
scoped to what the caller may see.

```
Employee submits  → leaves the employee's dashboard, appears for the HOD
HOD signs & sends → leaves the HOD's dashboard, appears for the CEO
CEO approves      → leaves the CEO's dashboard, appears for the Cashier
Cashier pays      → leaves the Cashier's dashboard, available in Reports
```

## Reports are permission-aware

Reports are where history lives, so they are also where permission matters most.

| Role | Sees | Report set |
| --- | --- | --- |
| Employee | Their own vouchers only | Register, monthly summary |
| Head of department | The departments they run | Register, department, expense, requester, approval, monthly |
| Managing Director / Director | Company-wide | All of them |
| Cashier | Company-wide, money that moved | Register, payment, approved-but-unpaid, bank, cash, monthly |
| Company Admin | Company-wide | All of them |
| Super Admin | Platform-wide | All of them |

A department filter can narrow a caller's scope; it can never widen it. Transport
reports on Transport, HR on HR, Procurement on Procurement.

---

## The core workflow

```
Employee raises a bank or cash voucher → submits
   → HOD reviews → HOD SIGNS ONLY → HOD submits the signed voucher
   → CEO reviews → CEO approves / rejects
   → Cashier releases the funds and records the reference
   → completed · printable at every stage
```

Signing, approving and paying are three separate acts.

A step that signs does not approve: once signed, its holder submits the voucher
onward, and the approve/reject decision belongs to a later step. A step that
approves does not release money: an approved voucher waits in the cashier's queue
until the funds are actually paid and a reference is recorded against it.

This is enforced in the workflow engine, not in the interface. Each client's mock
refuses the action outright — `POST /vouchers/{id}/approve` from a signing-only
step, or `POST /vouchers/{id}/pay` on a voucher that is not yet approved — exactly
as the API will.

**Nothing about that route is hard-coded.** Every company stores its own ordered
steps, and each step carries its own capability flags — sign, approve, reject,
request changes, print, download — plus an assignee (a named user or a role) and
optional amount thresholds. Three presets ship (`Sign then approve`,
`Finance in the middle`, `Single approver`) and administrators can build their own
in Settings → Approval workflow. The seeded demo runs two different routes side by
side to prove it.

## Multi-tenancy

One central MySQL database. Isolation is enforced **below the query layer**:

- `TenantContext` holds exactly one company per request, resolved by the
  `ResolveTenant` middleware straight after authentication.
- Every tenant-owned model uses `BelongsToTenant`, which applies `TenantScope`
  globally and stamps `company_id` on create.
- The scope **fails closed**: with no tenant resolved and no platform flag, it
  matches nothing. A controller that forgets to filter returns zero rows rather
  than leaking.
- Route-model binding is deliberately re-registered *after* the tenant middleware
  (see `routes/api.php`), so `{voucher}` resolves inside the caller's scope.

On top of that sits row-level visibility (`VoucherVisibility`): an employee sees
only their own vouchers; a head of department sees only the departments they head;
an approver sees what their workflow actually routes to them, plus anything they
have already acted on. Reports, exports and PDFs all reuse the same rules, so no
surface can widen what a role may see.

---

## Running it

**Prerequisites:** PHP 8.3+, Composer, MySQL 8+, Node 20+, and Flutter 3.3+ for
the mobile client.

### 1. Backend

```sh
cd backend
cp .env.example .env          # adjust DB_* if your MySQL differs
composer install
php artisan key:generate
mysql -u root -e "CREATE DATABASE vouchflow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
php artisan migrate --seed
php artisan storage:link
php artisan serve             # http://127.0.0.1:8000
```

### 2. Web

```sh
cd web
cp .env.example .env.local    # NEXT_PUBLIC_API_URL
npm install
npm run dev                   # http://localhost:3000
```

### 3. Mobile

```sh
cd app
flutter pub get
flutter run                   # Android emulator reaches the host on 10.0.2.2
# real device or hosted API:
flutter run --dart-define=API_URL=https://your-host/api
```

### Demo accounts

Password for all of them: `Password123!`

| Role | Email | What they can do |
| --- | --- | --- |
| Employee | `john@acme.test` | Creates vouchers; sees **only their own** |
| HOD | `asha@acme.test` | Reviews and **signs** — cannot approve |
| CEO | `daniel@acme.test` | Approves or rejects |
| Cashier | `fatuma@acme.test` | Releases the funds and records the reference |
| Company Admin | `admin@acme.test` | Runs one company end to end |
| Super Admin | `super@vouchflow.test` | Runs the platform, across all companies |

A second tenant (`admin@zamani.test`) runs a **four-step** route with Finance
between the HOD and the Manager, and a third (`admin@baobab.test`) sits on an
expiring trial so the renewal path is visible.

---

## What is included

**Vouchers** — two corporate formats kept separate throughout. A **bank voucher**
carries the payee's bank, account name, number and branch, and names the company
account it is drawn on; a **cash voucher** names the petty cash float it comes out
of and records who physically received the money. Five voucher types, with
per-tenant sequential numbering
(`PV-2026-000123`, format and padding configurable), attachments, comments,
amount-in-words, verification codes, drafts, edit-and-resubmit.

**Approvals** — configurable multi-step routes, digital signatures (draw, upload
or reuse a saved one), request-changes and reject with a recorded reason, an
approval timeline generated from the voucher's own workflow, and Print/Download
**at every stage**, not just at the end.

**Documents** — an A4 voucher built as a real financial document: the company's
own letterhead, a ruled particulars table with the amount and the amount in words
beneath the description, payment particulars alongside, and an authorisation band
carrying **Prepared by / Signed by / Approved by / Paid by** with each officer's
signature and an official SIGNED, APPROVED or PAID mark. Attachments, comments,
the timeline and the audit trail fold away beneath it, so what is on screen is
what prints.

**Administration** — employees and roles, departments with heads and managers,
voucher types and numbering, branding, company profile, and the workflow builder.

**Platform** — companies, plans and limits, subscriptions, payments and refunds,
cross-tenant users and audit log.

**Billing** — plans with enforced limits (seats, monthly volume, departments,
approval depth, storage), trials with expiry, online payment (mobile money, card,
bank transfer) through a swappable gateway, invoices and receipts. An expired
tenant can still *read* its data and settle up; writes are blocked with `402`.

**Reporting** — voucher, expense, department, employee, approval and monthly
reports, each exportable to PDF, Excel and CSV.

**Also** — registration and OTP verification, guided onboarding, notifications,
search and filtering, an append-only audit log, English + Swahili throughout
(English default), light and dark themes, and full responsive layout down to
360 px with a mobile tab bar and drawer.

---

## Tests

```sh
cd app  && flutter test                       # workflow rules, against the mock
cd app  && flutter test integration_test      # the app itself, on a device
cd backend && php artisan test                # the API (Phase 2)
```

`app/test/workflow_test.dart` drives the mock directly and asserts the rules the
client cares about: the full employee → HOD → CEO → cashier run, that an employee
sees nothing but their own work, that a head of another department is refused,
that the HOD step offers no approval, that approving does not pay, that a payment
needs a reference, and that a rejection reaches the requester with its reason.

`app/integration_test/app_test.dart` runs the real app on a simulator: each
persona lands on the right home screen, the HOD is offered signing and not
approval, and the cashier records a payment end to end.

Covering the guarantees that matter: tenant isolation (including that the scope
fails closed), employee privacy across list/detail/report/PDF, the signs-but-does-
not-approve rule, three- and four-step and single-approver routes, workflow
editing, billing limits, payment success and decline, subscription expiry, and
per-tenant numbering.

The web client was driven end to end in a real browser during development —
every page for every role, the whole workflow from creation to payment, the A4
sheet, both themes, and the responsive layout down to 390 px.

## Notes for production

- `PAYMENTS_DRIVER=demo` settles deterministically (any reference ending `0000`
  is declined, so the failure path is testable). Implement `PaymentGateway::charge`
  against a real PSP to go live; nothing else changes.
- OTPs are written to the log and returned in the response outside production.
  Wire a mail/SMS driver and they stop being returned.
- Attachments are stored on the `local` disk under `companies/{id}/…` and served
  through an authorised controller, never a public URL. Point the disk at S3 for
  production.
