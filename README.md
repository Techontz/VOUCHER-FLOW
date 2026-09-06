# VouchFlow

A multi-tenant voucher approval SaaS. Employees raise vouchers; each company's own
approval route carries them through signing and approval to a print-ready A4 PDF,
with every signature, comment and timestamp on the record.

Built from the VouchFlow design as the UI source of truth.

```
backend/   Laravel 13 API · MySQL          the system of record
web/       Next.js 16 (App Router) · TS    responsive web client
app/       Flutter · GetX                  mobile client
```

---

## The core workflow

```
Employee creates → submits → HOD reviews → HOD SIGNS ONLY → HOD submits signed
                → Manager reviews → Manager approves / rejects → completed → PDF
```

Signing and approving are separate acts. A step that signs does not approve: once
signed, its holder submits the voucher onward, and the approve/reject decision
belongs to a later step. This is enforced in `WorkflowEngine`, not in the UI —
the API refuses `POST /vouchers/{id}/approve` from a signing-only step even if
asked directly.

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
| Manager | `daniel@acme.test` | Approves or rejects |
| Finance | `fatuma@acme.test` | Approves where the route includes Finance |
| Company Admin | `admin@acme.test` | Runs one company end to end |
| Super Admin | `super@vouchflow.test` | Runs the platform, across all companies |

A second tenant (`admin@zamani.test`) runs a **four-step** route with Finance
between the HOD and the Manager, and a third (`admin@baobab.test`) sits on an
expiring trial so the renewal path is visible.

---

## What is included

**Vouchers** — five voucher types with per-tenant sequential numbering
(`PV-2026-000123`, format and padding configurable), attachments, comments,
amount-in-words, verification codes, drafts, edit-and-resubmit.

**Approvals** — configurable multi-step routes, digital signatures (draw, upload
or reuse a saved one), request-changes and reject with a recorded reason, an
approval timeline generated from the voucher's own workflow, and Print/Download
**at every stage**, not just at the end.

**Documents** — server-generated A4 PDFs in Poppins, carrying the company logo,
colour, footer text and every captured signature. Authorisation blocks are built
from the route the voucher actually travelled.

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
cd backend && php artisan test     # 39 tests
```

Covering the guarantees that matter: tenant isolation (including that the scope
fails closed), employee privacy across list/detail/report/PDF, the signs-but-does-
not-approve rule, three- and four-step and single-approver routes, workflow
editing, billing limits, payment success and decline, subscription expiry, and
per-tenant numbering.

The web and mobile clients were driven end to end in a real browser during
development — sign-in, voucher creation, signing, approval, PDF, reports,
platform administration, mobile layout and dark theme.

## Notes for production

- `PAYMENTS_DRIVER=demo` settles deterministically (any reference ending `0000`
  is declined, so the failure path is testable). Implement `PaymentGateway::charge`
  against a real PSP to go live; nothing else changes.
- OTPs are written to the log and returned in the response outside production.
  Wire a mail/SMS driver and they stop being returned.
- Attachments are stored on the `local` disk under `companies/{id}/…` and served
  through an authorised controller, never a public URL. Point the disk at S3 for
  production.
