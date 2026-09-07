/**
 * The demo world the Phase 1 prototype runs on.
 *
 * Everything here is invented. Shapes match the API contract the UI already
 * consumes, so swapping this for Laravel is a transport change, not a rewrite.
 */

import type { Role } from "../types";

export interface MockUser {
  id: number;
  company_id: number | null;
  name: string;
  email: string;
  role: Role;
  job_title: string;
  employee_code: string | null;
  department_id: number | null;
  phone: string | null;
  status: "active" | "invited" | "suspended";
  locale: "en" | "sw";
  theme: "light" | "dark";
  signature: string | null;
  last_login_at: string | null;
  joined_at: string;
  voucher_count: number;
}

export interface MockCompany {
  id: number;
  name: string;
  slug: string;
  email: string;
  phone: string;
  address: string;
  currency: string;
  locale: "en" | "sw";
  logo_url: string | null;
  primary_color: string;
  theme: "light" | "dark";
  voucher_footer_text: string;
  status: "trial" | "active" | "past_due" | "suspended" | "cancelled";
  plan_code: string;
  trial_ends_at: string | null;
  current_period_start: string;
  current_period_end: string;
  auto_renew: boolean;
  created_at: string;
}

export interface MockStep {
  id: number;
  position: number;
  name: string;
  name_sw: string | null;
  role: "employee" | "hod" | "ceo" | "cashier" | "finance" | "director" | "custom";
  assigned_user_id: number | null;
  assignee_hint: string;
  can_sign: boolean;
  can_approve: boolean;
  can_reject: boolean;
  can_request_changes: boolean;
  can_pay: boolean;
  can_print: boolean;
  can_download: boolean;
  requires_signature: boolean;
  min_amount: number | null;
  max_amount: number | null;
}

export interface MockWorkflow {
  id: number;
  company_id: number;
  name: string;
  description: string;
  is_default: boolean;
  is_active: boolean;
  version: number;
  steps: MockStep[];
}

export interface MockApproval {
  id: number;
  voucher_id: number;
  step_position: number | null;
  step_name: string | null;
  step_role: string | null;
  actor_id: number | null;
  actor_name: string;
  action:
    | "created" | "submitted" | "signed" | "forwarded" | "approved"
    | "rejected" | "changes_requested" | "resubmitted" | "paid" | "cancelled";
  comment: string | null;
  signature: string | null;
  acted_at: string;
}

export interface MockVoucher {
  id: number;
  company_id: number;
  number: string;
  kind: "bank" | "cash";
  voucher_type_id: number;
  workflow_id: number;
  department_id: number | null;
  requester_id: number;
  payee: string;
  purpose: string;
  description: string | null;
  amount: number;
  currency: string;
  payment_method: string | null;
  account_ref: string | null;
  category: string | null;
  cost_centre: string | null;
  voucher_date: string;
  status: "draft" | "in_review" | "changes_requested" | "approved" | "paid" | "rejected" | "cancelled";
  current_step_position: number | null;
  step_signed_at: string | null;
  verification_code: string;
  notes_to_approver: string | null;
  submitted_at: string | null;
  approved_at: string | null;
  rejected_at: string | null;
  paid_at: string | null;
  payment_reference: string | null;
  paid_by: string | null;
  created_at: string;
  attachments: { id: number; name: string; mime: string; size_bytes: number }[];
  comments: { id: number; user_id: number; body: string; created_at: string }[];
}

export interface MockNotification {
  id: number;
  user_id: number;
  company_id: number | null;
  type: string;
  icon: string;
  title: string;
  title_sw: string | null;
  body: string | null;
  body_sw: string | null;
  entity_type: string | null;
  entity_id: number | null;
  read_at: string | null;
  created_at: string;
}

export interface MockAudit {
  id: number;
  company_id: number | null;
  actor_name: string;
  actor_role: string | null;
  action: string;
  description: string;
  change_summary: string | null;
  entity_type: string | null;
  entity_id: number | null;
  ip: string;
  user_agent: string;
  created_at: string;
}

export interface MockInvoice {
  id: number;
  company_id: number;
  number: string;
  description: string;
  amount: number;
  currency: string;
  status: "pending" | "paid" | "failed" | "refunded" | "void";
  method: "mobile_money" | "card" | "bank_transfer" | "none";
  provider_ref: string | null;
  failure_reason: string | null;
  period_start: string;
  period_end: string;
  issued_at: string;
  paid_at: string | null;
}

export interface MockDataset {
  companies: MockCompany[];
  users: MockUser[];
  departments: { id: number; company_id: number; name: string; code: string; cost_centre: string; hod_user_id: number | null; manager_user_id: number | null }[];
  voucherTypes: { id: number; company_id: number; name: string; name_sw: string; code: string; prefix: string; next_number: number; seq_padding: number; is_active: boolean; sort_order: number }[];
  workflows: MockWorkflow[];
  vouchers: MockVoucher[];
  approvals: MockApproval[];
  notifications: MockNotification[];
  audit: MockAudit[];
  invoices: MockInvoice[];
  plans: {
    id: number; code: string; name: string; name_sw: string; blurb: string; blurb_sw: string;
    price: number; currency: string; billing_cycle: "monthly" | "annual";
    max_users: number | null; max_vouchers_per_month: number | null; max_departments: number | null;
    max_approval_levels: number | null; storage_mb: number | null; trial_days: number;
    features: string[]; features_sw: string[]; is_active: boolean; is_public: boolean; sort_order: number;
  }[];
  sequences: { voucher: number; approval: number; notification: number; audit: number; comment: number; attachment: number; user: number; department: number; step: number; workflow: number };
}

const iso = (daysAgo: number, hour = 9, minute = 0) => {
  const d = new Date();
  d.setDate(d.getDate() - daysAgo);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
};
const day = (daysAgo: number) => iso(daysAgo).slice(0, 10);

/** A visible pen stroke, so signed vouchers and the printed sheet show a mark. */
/**
 * A drawn signature, inlined as a PNG so the prototype needs no network,
 * and so the mobile client can decode the very same value.
 */
export const SAMPLE_SIGNATURE =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAPAAAABGCAYAAADyxhn6AAADZklEQVR42u3dPUiVYRjGcQ2lIunDoaQIxEXCQTCIoJZApFpa+hobnBpcAh0cQyiXlohAosEIguYoaGhxLKhAECRwj5CgQBDqPvBMqUfNc97P3x+uTX3f57rv6/nQ8752dAAAAAAAAAAAAAAAAAAAUHoO9fb/aaLnHAKKF9rubYK7mRgHFHzF3YlecREoSHj3Eva8JhmVhPD29ne1KlQtuLe7/7kbOKuyqF1427g6Tma4lbciQ3hzPEs3U0+T6/Zt8T3HVRvCm1OQW3TtT6oO4c0mzGNtuuZ31UelAly3ySp0TwegKg39tCZj/uUXW7B1NnbA1lmIgb017xk+CDE0rZ0IoGEz9+MGT3btWR+/8l99P3PErsQiUB7TDzJ+xyFmiMnOrFkyf07zSHiLavwXxmtQ3lh9eSW8fGF+of16wK/Ne0f/WFHK2LgPBVf/FKEQdzhi4msy3rUmj3S+1hHZF+SY2bN+R4+41/deQ2QFQYk8bMfrilQ/34KuKkZLfDxVZB9bHNrLKm7lsJXO5p4WmwTxnappOBR0QrTl1WzYvacf8/Y1rttZ6eBq2g2z8xHRa5u33/Jedatm7n6viLGlquLupjbb5bo3sPBWr8c2Ce8qg6s/7seiVv4eq+2CVLeB2zrn7vklNS3wuSG+91lRP8US17ogvLn017l2+W5CbhLinRgSXzPawk+3dGY4xkHRKu/Op3H0Ed4dhjgHXbXNEuIsdoyCvFE/W3itw8IrxMLb5iDnvY0X3ur/zmWL3rjIzQqdx//5GVeEt/w19lnmau4A1myz6ntU41y5inzAw9aCrI41nLE5Vrr6PlJDQVZ0AAAAAMBuzpi9XABKmJmMP/O8HHoRmgpdCw2Fjrb7oQZUMkCdqXeGUi9Npd5azrKn6xbgIut3eh3p29Bc6H5oInQzPYE1HBoInQj1hLqq8I+uG2NIY+lJYxtIYx1NY59IXswlbxaTV3qmKH8BiRsZCd0OzYY+bPN/YIjqqLWUjdmUlZG6b4H2Nc4Raba/HpoOvQwtaRbaQkupR6ZTzwynHtrnUIFmk01341HH0MnGiwFC50NjoVuh8dBkaCb0JDQfehNaCH0NrYR+hNYzbPT1dM2VdA8L6Z7m0z3OpHseT2MYS2MaTGNsjLVb5QEAAAAAAAAAKDt/AcPmz43fXEUmAAAAAElFTkSuQmCC";

function signatureSvg(): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="260" height="90" viewBox="0 0 260 90">
<rect width="260" height="90" fill="#ffffff"/>
<path d="M18 58 C40 20, 62 20, 78 46 S112 78, 128 44 S162 12, 182 40 S214 62, 240 34"
 fill="none" stroke="#16213a" stroke-width="2.6" stroke-linecap="round"/>
<path d="M16 72 L236 70" fill="none" stroke="#16213a" stroke-width="1.4" stroke-linecap="round" opacity=".65"/>
</svg>`;
}

const STEP = (
  id: number, position: number, name: string, nameSw: string,
  role: MockStep["role"], hint: string, caps: Partial<MockStep>,
): MockStep => ({
  id, position, name, name_sw: nameSw, role,
  assigned_user_id: null, assignee_hint: hint,
  can_sign: false, can_approve: false, can_reject: false, can_request_changes: false,
  can_pay: false, can_print: true, can_download: true, requires_signature: false,
  min_amount: null, max_amount: null,
  ...caps,
});

/** The default route a new company starts on: request → sign → approve → pay. */
export const DEFAULT_STEPS = (): MockStep[] => [
  STEP(1, 1, "Request", "Ombi", "employee", "Voucher creator", {}),
  STEP(2, 2, "Department review", "Ukaguzi wa idara", "hod", "Head of the requesting department",
    { can_sign: true, can_request_changes: true, requires_signature: true }),
  STEP(3, 3, "Executive approval", "Idhini ya mkurugenzi", "ceo", "Chief executive / approving manager",
    { can_approve: true, can_reject: true, can_request_changes: true }),
  STEP(4, 4, "Payment", "Malipo", "cashier", "Cashier / finance officer", { can_pay: true }),
];

export const WORKFLOW_PRESETS: Record<string, { name: string; description: string; steps: () => MockStep[] }> = {
  default: {
    name: "Sign, approve, pay",
    description: "Employee → HOD (sign) → CEO (approve) → Cashier (pay)",
    steps: DEFAULT_STEPS,
  },
  finance: {
    name: "Finance in the middle",
    description: "Employee → HOD → Finance → CEO → Cashier",
    steps: () => [
      STEP(11, 1, "Request", "Ombi", "employee", "Voucher creator", {}),
      STEP(12, 2, "Department review", "Ukaguzi wa idara", "hod", "Head of the requesting department",
        { can_sign: true, can_request_changes: true, requires_signature: true }),
      STEP(13, 3, "Finance verification", "Uhakiki wa fedha", "finance", "Finance officer",
        { can_sign: true, can_approve: true, can_reject: true, can_request_changes: true }),
      STEP(14, 4, "Executive approval", "Idhini ya mkurugenzi", "ceo", "Chief executive",
        { can_approve: true, can_reject: true }),
      STEP(15, 5, "Payment", "Malipo", "cashier", "Cashier / finance officer", { can_pay: true }),
    ],
  },
  single: {
    name: "Single approver",
    description: "Employee → CEO (sign, approve, reject) → Cashier",
    steps: () => [
      STEP(21, 1, "Request", "Ombi", "employee", "Voucher creator", {}),
      STEP(22, 2, "Approval", "Idhini", "ceo", "Chief executive",
        { can_sign: true, can_approve: true, can_reject: true, can_request_changes: true }),
      STEP(23, 3, "Payment", "Malipo", "cashier", "Cashier / finance officer", { can_pay: true }),
    ],
  },
};

export function buildSeed(): MockDataset {
  const companies: MockCompany[] = [
    {
      id: 1, name: "Acme Tanzania Ltd", slug: "acme-tanzania", email: "accounts@acme-demo.test",
      phone: "+255 712 000 101", address: "Plot 44, Mikocheni · Dar es Salaam",
      currency: "TZS", locale: "en", logo_url: null, primary_color: "#2f7bf6", theme: "dark",
      voucher_footer_text: "This voucher is computer generated and valid without a wet stamp.",
      status: "active", plan_code: "business", trial_ends_at: null,
      current_period_start: iso(6), current_period_end: iso(-24), auto_renew: true, created_at: iso(600),
    },
    {
      id: 2, name: "Zamani Logistics", slug: "zamani-logistics", email: "finance@zamani-demo.test",
      phone: "+255 713 000 202", address: "Nyerere Road · Dar es Salaam",
      currency: "TZS", locale: "en", logo_url: null, primary_color: "#22a7e8", theme: "dark",
      voucher_footer_text: "Computer generated voucher.", status: "active", plan_code: "enterprise",
      trial_ends_at: null, current_period_start: iso(30), current_period_end: iso(-335),
      auto_renew: true, created_at: iso(900),
    },
    {
      id: 3, name: "Baobab Business Solutions", slug: "baobab-solutions", email: "hello@baobab-demo.test",
      phone: "+255 714 000 303", address: "Kijitonyama · Dar es Salaam",
      currency: "TZS", locale: "en", logo_url: null, primary_color: "#34d399", theme: "dark",
      voucher_footer_text: "Computer generated voucher.", status: "trial", plan_code: "starter",
      trial_ends_at: iso(-3), current_period_start: iso(11), current_period_end: iso(-3),
      auto_renew: false, created_at: iso(11),
    },
  ];

  const U = (
    id: number, company_id: number | null, name: string, email: string, role: Role,
    job_title: string, code: string | null, department_id: number | null, signed = false,
  ): MockUser => ({
    id, company_id, name, email, role, job_title, employee_code: code, department_id,
    phone: null, status: "active", locale: "en", theme: "dark",
    signature: signed ? SAMPLE_SIGNATURE : null,
    last_login_at: iso(0, 8, 12), joined_at: iso(400), voucher_count: 0,
  });

  const users: MockUser[] = [
    U(1, null, "Grace Kimaro", "super@vouchflow.test", "super_admin", "Platform Super Admin", null, null),

    U(2, 1, "Neema William", "admin@acme.test", "company_admin", "Company Administrator", "AC-0087", 4),
    U(3, 1, "John Mwakyusa", "john@acme.test", "employee", "Procurement Officer", "AC-0114", 2),
    U(4, 1, "Asha Mushi", "asha@acme.test", "hod", "Head of Finance", "AC-0032", 1, true),
    U(5, 1, "Daniel Joseph", "daniel@acme.test", "ceo", "Chief Executive Officer", "AC-0008", 3, true),
    U(6, 1, "Fatuma Kalinga", "fatuma@acme.test", "cashier", "Cashier · Finance", "AC-0056", 1, true),
    U(7, 1, "Baraka Ndosi", "baraka@acme.test", "employee", "IT Officer", "AC-0129", 5),
    U(8, 1, "Zawadi Mrema", "zawadi@acme.test", "employee", "Sales Executive", "AC-0141", 6),
    U(9, 1, "Peter Sanga", "peter@acme.test", "hod", "Head of Procurement", "AC-0021", 2, true),

    U(10, 2, "Erick Mbise", "admin@zamani.test", "company_admin", "Group Administrator", "ZL-0001", 7),
    U(11, 2, "Salma Juma", "salma@zamani.test", "finance", "Finance Controller", "ZL-0004", 7, true),
  ];

  const departments = [
    { id: 1, company_id: 1, name: "Finance", code: "FIN", cost_centre: "CC-FIN", hod_user_id: 4, manager_user_id: 5 },
    { id: 2, company_id: 1, name: "Procurement", code: "PRO", cost_centre: "CC-PRO", hod_user_id: 9, manager_user_id: 5 },
    { id: 3, company_id: 1, name: "Operations", code: "OPS", cost_centre: "CC-OPS", hod_user_id: 4, manager_user_id: 5 },
    { id: 4, company_id: 1, name: "Human Resources", code: "HR", cost_centre: "CC-HR", hod_user_id: 4, manager_user_id: 5 },
    { id: 5, company_id: 1, name: "IT", code: "IT", cost_centre: "CC-IT", hod_user_id: 9, manager_user_id: 5 },
    { id: 6, company_id: 1, name: "Sales", code: "SLS", cost_centre: "CC-SLS", hod_user_id: 9, manager_user_id: 5 },
    { id: 7, company_id: 2, name: "Fleet", code: "FLT", cost_centre: "CC-FLT", hod_user_id: 11, manager_user_id: 10 },
  ];

  const voucherTypes = [1, 2, 3].flatMap((companyId) =>
    [
      ["Payment Voucher", "Vocha ya malipo", "payment", "PV"],
      ["Petty Cash Voucher", "Vocha ya fedha taslimu", "petty_cash", "PC"],
      ["Expense Voucher", "Vocha ya matumizi", "expense", "EX"],
      ["Advance Voucher", "Vocha ya malipo ya awali", "advance", "AD"],
      ["Reimbursement Voucher", "Vocha ya kurejeshewa", "reimbursement", "RB"],
      ["Other", "Nyingine", "other", "OV"],
    ].map(([name, nameSw, code, prefix], i) => ({
      id: companyId * 100 + i + 1, company_id: companyId,
      name, name_sw: nameSw, code, prefix,
      // Continues the seeded register rather than restarting at 1.
      next_number: [1246, 319, 88, 43, 27, 9][i] ?? 1,
      seq_padding: 6, is_active: true, sort_order: i,
    })),
  );

  const workflows: MockWorkflow[] = [
    { id: 1, company_id: 1, name: "Sign, approve, pay", description: "Employee → HOD (sign) → CEO (approve) → Cashier (pay)", is_default: true, is_active: true, version: 1, steps: DEFAULT_STEPS() },
    { id: 2, company_id: 2, name: "Finance in the middle", description: WORKFLOW_PRESETS.finance.description, is_default: true, is_active: true, version: 1, steps: WORKFLOW_PRESETS.finance.steps() },
    { id: 3, company_id: 3, name: "Sign, approve, pay", description: WORKFLOW_PRESETS.default.description, is_default: true, is_active: true, version: 1, steps: DEFAULT_STEPS() },
  ];

  let vid = 0;
  const approvals: MockApproval[] = [];
  let aid = 0;

  const V = (spec: {
    number: string; kind: "bank" | "cash"; typeId: number; dept: number; requester: number;
    payee: string; purpose: string; desc: string; amount: number; method: string;
    category: string; ref: string; daysAgo: number;
    status: MockVoucher["status"]; step: number | null; signedAt?: string | null;
    files?: { name: string; mime: string; size: number }[];
    trail?: { action: MockApproval["action"]; actor: number; step?: number; comment?: string; signed?: boolean; daysAgo: number; hour?: number }[];
    paymentRef?: string; paidBy?: string;
  }): MockVoucher => {
    const id = ++vid;
    const requesterName = users.find((u) => u.id === spec.requester)!.name;

    (spec.trail ?? []).forEach((t) => {
      const wf = workflows.find((w) => w.id === 1)!;
      const stepDef = t.step ? wf.steps.find((s) => s.position === t.step) : undefined;
      approvals.push({
        id: ++aid, voucher_id: id,
        step_position: t.step ?? null,
        step_name: stepDef?.name ?? null,
        step_role: stepDef?.role ?? null,
        actor_id: t.actor,
        actor_name: users.find((u) => u.id === t.actor)?.name ?? requesterName,
        action: t.action, comment: t.comment ?? null,
        signature: t.signed ? SAMPLE_SIGNATURE : null,
        acted_at: iso(t.daysAgo, t.hour ?? 9, 14),
      });
    });

    return {
      id, company_id: 1, number: spec.number, kind: spec.kind,
      voucher_type_id: spec.typeId, workflow_id: 1, department_id: spec.dept,
      requester_id: spec.requester, payee: spec.payee, purpose: spec.purpose,
      description: spec.desc, amount: spec.amount, currency: "TZS",
      payment_method: spec.method, account_ref: spec.ref, category: spec.category,
      cost_centre: departments.find((d) => d.id === spec.dept)?.cost_centre ?? null,
      voucher_date: day(spec.daysAgo), status: spec.status,
      current_step_position: spec.step, step_signed_at: spec.signedAt ?? null,
      verification_code: `VF-${(1000 + id * 37).toString(36).toUpperCase().padStart(4, "0")}-${(id * 911).toString(36).toUpperCase().padStart(4, "0")}`,
      notes_to_approver: null,
      submitted_at: spec.status === "draft" ? null : iso(spec.daysAgo, 8, 2),
      approved_at: ["approved", "paid"].includes(spec.status) ? iso(Math.max(0, spec.daysAgo - 1), 15, 31) : null,
      rejected_at: spec.status === "rejected" ? iso(Math.max(0, spec.daysAgo - 1), 14, 5) : null,
      paid_at: spec.status === "paid" ? iso(Math.max(0, spec.daysAgo - 2), 10, 12) : null,
      payment_reference: spec.paymentRef ?? null,
      paid_by: spec.paidBy ?? null,
      created_at: iso(spec.daysAgo, 7, 58),
      attachments: (spec.files ?? []).map((f, i) => ({
        id: id * 10 + i, name: f.name, mime: f.mime, size_bytes: f.size,
      })),
      comments: [],
    };
  };

  const vouchers: MockVoucher[] = [
    V({
      number: "PV-2026-001245", kind: "bank", typeId: 101, dept: 2, requester: 3,
      payee: "Highland Freight Services", purpose: "Freight to Arusha — September consignment",
      desc: "Road freight for 14 pallets of stock to the Arusha branch, per framework contract rate.",
      amount: 4850000, method: "Bank Transfer", category: "Logistics", ref: "INV-88213",
      daysAgo: 2, status: "in_review", step: 2,
      files: [{ name: "invoice-88213.pdf", mime: "application/pdf", size: 184320 },
              { name: "delivery-note.jpg", mime: "image/jpeg", size: 942080 }],
      trail: [{ action: "created", actor: 3, daysAgo: 2, hour: 7 }, { action: "submitted", actor: 3, step: 1, daysAgo: 2, hour: 8 }],
    }),
    V({
      number: "PV-2026-001244", kind: "bank", typeId: 101, dept: 1, requester: 3,
      payee: "Mikocheni Property Holdings", purpose: "Office rent — Q4 2026",
      desc: "Quarterly rent for the Mikocheni head office, per lease clause 4.2.",
      amount: 21500000, method: "Bank Transfer", category: "Premises", ref: "LEASE-Q4",
      daysAgo: 3, status: "in_review", step: 2, signedAt: iso(2, 9, 14),
      files: [{ name: "lease-agreement.pdf", mime: "application/pdf", size: 512000 }],
      trail: [
        { action: "created", actor: 3, daysAgo: 3, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 3, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 2, hour: 9, comment: "Within the Q3 budget. Rate matches the framework contract." },
      ],
    }),
    V({
      number: "PC-2026-000318", kind: "cash", typeId: 102, dept: 5, requester: 7,
      payee: "Serengeti Computer Supplies", purpose: "Replacement laptop batteries",
      desc: "Eight replacement batteries for field laptops.",
      amount: 1450000, method: "Cash", category: "Capital equipment", ref: "QT-4471",
      daysAgo: 4, status: "in_review", step: 3,
      files: [{ name: "quotation-4471.pdf", mime: "application/pdf", size: 96000 }],
      trail: [
        { action: "created", actor: 7, daysAgo: 4, hour: 7 },
        { action: "submitted", actor: 7, step: 1, daysAgo: 4, hour: 8 },
        { action: "signed", actor: 9, step: 2, signed: true, daysAgo: 3, hour: 9 },
        { action: "forwarded", actor: 9, step: 2, daysAgo: 3, hour: 10, comment: "Verified against the IT asset register." },
      ],
    }),
    V({
      number: "PV-2026-001240", kind: "bank", typeId: 101, dept: 1, requester: 3,
      payee: "Riverside Consulting Ltd", purpose: "External audit fieldwork — Q3",
      desc: "Three days of audit fieldwork at the head office.",
      amount: 3250000, method: "Bank Transfer", category: "Professional fees", ref: "INV-77120",
      daysAgo: 6, status: "approved", step: 4,
      files: [{ name: "engagement-letter.pdf", mime: "application/pdf", size: 220000 }],
      trail: [
        { action: "created", actor: 3, daysAgo: 6, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 6, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 5, hour: 9 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 5, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 5, hour: 15, comment: "Cleared for payment." },
      ],
    }),
    V({
      number: "PC-2026-000317", kind: "cash", typeId: 102, dept: 3, requester: 3,
      payee: "Kariakoo Stationers", purpose: "Office consumables — September",
      desc: "Paper, toner and general stationery for the month.",
      amount: 350000, method: "Cash", category: "Staff welfare", ref: "RCP-9921",
      daysAgo: 7, status: "approved", step: 4,
      trail: [
        { action: "created", actor: 3, daysAgo: 7, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 7, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 6, hour: 9 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 6, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 6, hour: 15 },
      ],
    }),
    V({
      number: "PV-2026-001238", kind: "bank", typeId: 101, dept: 3, requester: 3,
      payee: "Uhuru Internet Services", purpose: "Branch connectivity — August",
      desc: "Monthly connectivity for the Arusha branch.",
      amount: 780000, method: "Bank Transfer", category: "Utilities", ref: "INV-5512",
      daysAgo: 12, status: "paid", step: null,
      paymentRef: "TRX-884120", paidBy: "Fatuma Kalinga",
      trail: [
        { action: "created", actor: 3, daysAgo: 12, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 12, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 11, hour: 9 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 11, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 11, hour: 15 },
        { action: "paid", actor: 6, step: 4, daysAgo: 10, hour: 10, comment: "Funds released and reference recorded against the voucher." },
      ],
    }),
    V({
      number: "AD-2026-000042", kind: "cash", typeId: 104, dept: 3, requester: 3,
      payee: "John Mwakyusa", purpose: "Travel advance — Mwanza site visit",
      desc: "Three nights, per diem and fuel for the Mwanza inspection.",
      amount: 980000, method: "Mobile Money", category: "Transport", ref: "ADV-0042",
      daysAgo: 14, status: "rejected", step: null,
      trail: [
        { action: "created", actor: 3, daysAgo: 14, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 14, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 13, hour: 9 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 13, hour: 10 },
        { action: "rejected", actor: 5, step: 3, daysAgo: 13, hour: 14, comment: "Use the branch float for Mwanza travel — resubmit against cost centre 42." },
      ],
    }),
    V({
      number: "EX-2026-000011", kind: "bank", typeId: 103, dept: 5, requester: 7,
      payee: "Uhuru Internet Services", purpose: "Branch internet — August arrears",
      desc: "Outstanding connectivity charges for the Arusha branch.",
      amount: 620000, method: "Bank Transfer", category: "Professional fees", ref: "INV-5590",
      daysAgo: 5, status: "changes_requested", step: null,
      trail: [
        { action: "created", actor: 7, daysAgo: 5, hour: 7 },
        { action: "submitted", actor: 7, step: 1, daysAgo: 5, hour: 8 },
        { action: "changes_requested", actor: 9, step: 2, daysAgo: 4, hour: 11, comment: "Attach the August invoice and the signed service report." },
      ],
    }),
    V({
      number: "PV-2026-001246", kind: "bank", typeId: 101, dept: 2, requester: 3,
      payee: "Coastal Packaging Ltd", purpose: "Packaging materials — October order",
      desc: "Draft pending the supplier quotation.",
      amount: 2750000, method: "Bank Transfer", category: "Logistics", ref: "",
      daysAgo: 0, status: "draft", step: null,
      trail: [{ action: "created", actor: 3, daysAgo: 0, hour: 9 }],
    }),
  ];

  // A little history so charts and reports are not empty.
  const payees = ["Highland Freight Services", "Kariakoo Stationers", "Uhuru Internet Services", "Coastal Packaging Ltd", "Serengeti Computer Supplies"];
  const purposes = ["Monthly courier retainer", "Warehouse cleaning contract", "Generator servicing", "Branch water supply", "Security guarding — monthly"];
  let hist = 0;
  for (let monthsAgo = 6; monthsAgo >= 1; monthsAgo--) {
    for (let i = 0; i < 3 + (monthsAgo % 3); i++) {
      hist++;
      const daysAgo = monthsAgo * 30 + i * 3;
      const rejected = hist % 9 === 0;
      // Spread the history across the company's employees and their own
      // departments, so each persona's register looks like a real caseload
      // and the signing step resolves to that department's actual head.
      const [requesterId, deptId, hodId] = ([
        [3, 2, 9], [7, 5, 9], [8, 6, 9], [3, 3, 4], [7, 4, 4], [8, 1, 4],
      ] as const)[hist % 6];
      vouchers.push(
        V({
          number: `PV-2026-${String(1100 + hist).padStart(6, "0")}`,
          kind: hist % 3 === 0 ? "cash" : "bank",
          typeId: 101, dept: deptId, requester: requesterId,
          payee: payees[hist % payees.length], purpose: purposes[hist % purposes.length],
          desc: "Recurring operational cost, approved against the monthly budget.",
          amount: (2 + (hist * 7) % 88) * 100000,
          method: hist % 3 === 0 ? "Cash" : "Bank Transfer",
          category: ["Logistics", "Premises", "Transport", "Utilities"][hist % 4],
          ref: `INV-${20000 + hist}`, daysAgo,
          status: rejected ? "rejected" : "paid",
          step: null,
          paymentRef: rejected ? undefined : `TRX-${700000 + hist}`,
          paidBy: rejected ? undefined : "Fatuma Kalinga",
          trail: [
            { action: "created", actor: requesterId, daysAgo, hour: 7 },
            { action: "submitted", actor: requesterId, step: 1, daysAgo, hour: 8 },
            { action: "signed", actor: hodId, step: 2, signed: true, daysAgo: daysAgo - 1, hour: 9 },
            { action: "forwarded", actor: hodId, step: 2, daysAgo: daysAgo - 1, hour: 10 },
            rejected
              ? { action: "rejected" as const, actor: 5, step: 3, daysAgo: daysAgo - 1, hour: 14, comment: "Outside the approved budget for this period." }
              : { action: "approved" as const, actor: 5, step: 3, daysAgo: daysAgo - 1, hour: 15 },
            ...(rejected ? [] : [{ action: "paid" as const, actor: 6, step: 4, daysAgo: daysAgo - 2, hour: 10 }]),
          ],
        }),
      );
    }
  }

  vouchers.push({
    ...V({
      number: "PV-2026-000001", kind: "bank", typeId: 201, dept: 7, requester: 11,
      payee: "Kilimanjaro Fuel Supplies", purpose: "Diesel for the Arusha convoy",
      desc: "Fuel for six trucks on the Arusha run, week 36.",
      amount: 12400000, method: "Bank Transfer", category: "Transport", ref: "FU-2201",
      daysAgo: 2, status: "in_review", step: 3,
    }),
    company_id: 2, workflow_id: 2,
  });

  vouchers[1].comments = [
    { id: 1, user_id: 4, body: "Within the Q3 logistics budget. Rate matches the framework contract.", created_at: iso(2, 9, 20) },
  ];
  vouchers[2].comments = [
    { id: 2, user_id: 7, body: "Quotation attached — the supplier holds this price until the 30th.", created_at: iso(3, 11, 5) },
  ];

  users.forEach((u) => {
    u.voucher_count = vouchers.filter((v) => v.requester_id === u.id).length;
  });

  const notifications: MockNotification[] = [
    { id: 1, user_id: 4, company_id: 1, type: "voucher.awaiting", icon: "ph-signature", title: "PV-2026-001245 needs your signature", title_sw: "PV-2026-001245 inahitaji sahihi yako", body: "John Mwakyusa submitted TZS 4,850,000 for freight to Arusha.", body_sw: "John Mwakyusa alituma TZS 4,850,000 kwa usafirishaji hadi Arusha.", entity_type: "Voucher", entity_id: 1, read_at: null, created_at: iso(0, 8, 2) },
    { id: 2, user_id: 5, company_id: 1, type: "voucher.awaiting", icon: "ph-seal-check", title: "PC-2026-000318 awaits your approval", title_sw: "PC-2026-000318 inasubiri idhini yako", body: "Signed by Peter Sanga — now with you for the final decision.", body_sw: "Imesainiwa na Peter Sanga — sasa iko kwako kwa uamuzi wa mwisho.", entity_type: "Voucher", entity_id: 3, read_at: null, created_at: iso(0, 10, 14) },
    { id: 3, user_id: 6, company_id: 1, type: "voucher.awaiting", icon: "ph-wallet", title: "2 vouchers cleared for payment", title_sw: "Vocha 2 zimeidhinishwa kwa malipo", body: "TZS 3,600,000 approved and awaiting release.", body_sw: "TZS 3,600,000 zimeidhinishwa na zinasubiri kutolewa.", entity_type: "Voucher", entity_id: 4, read_at: null, created_at: iso(0, 11, 0) },
    { id: 4, user_id: 3, company_id: 1, type: "voucher.rejected", icon: "ph-x-circle", title: "AD-2026-000042 was rejected", title_sw: "AD-2026-000042 imekataliwa", body: 'Daniel Joseph: "Use the branch float for Mwanza travel."', body_sw: 'Daniel Joseph: "Tumia fedha ya tawi kwa safari ya Mwanza."', entity_type: "Voucher", entity_id: 7, read_at: null, created_at: iso(1, 14, 5) },
    { id: 5, user_id: 3, company_id: 1, type: "voucher.paid", icon: "ph-check-circle", title: "PV-2026-001238 has been paid", title_sw: "PV-2026-001238 imelipwa", body: "Fatuma Kalinga released TZS 780,000 · reference TRX-884120.", body_sw: "Fatuma Kalinga alitoa TZS 780,000 · kumbukumbu TRX-884120.", entity_type: "Voucher", entity_id: 6, read_at: iso(9), created_at: iso(10, 10, 12) },
    { id: 6, user_id: 2, company_id: 1, type: "billing", icon: "ph-credit-card", title: "Payment received", title_sw: "Malipo yamepokelewa", body: "TZS 249,000 for the Business plan.", body_sw: "TZS 249,000 kwa mpango wa Business.", entity_type: null, entity_id: null, read_at: null, created_at: iso(6, 11, 2) },
  ];

  const audit: MockAudit[] = [
    { id: 1, company_id: 1, actor_name: "Asha Mushi", actor_role: "hod", action: "voucher.signed", description: "Signed voucher PV-2026-001244", change_summary: "Awaiting HOD signature → Signed", entity_type: "Voucher", entity_id: 2, ip: "41.59.12.8", user_agent: "Chrome, Windows", created_at: iso(2, 9, 14) },
    { id: 2, company_id: 1, actor_name: "John Mwakyusa", actor_role: "employee", action: "voucher.submitted", description: "Submitted voucher PV-2026-001245", change_summary: "Draft → Awaiting HOD signature", entity_type: "Voucher", entity_id: 1, ip: "197.250.4.19", user_agent: "VouchFlow Android", created_at: iso(2, 8, 2) },
    { id: 3, company_id: 1, actor_name: "Fatuma Kalinga", actor_role: "cashier", action: "voucher.paid", description: "Recorded payment for PV-2026-001238", change_summary: "Approved → Paid", entity_type: "Voucher", entity_id: 6, ip: "41.59.12.61", user_agent: "Safari, macOS", created_at: iso(10, 10, 12) },
    { id: 4, company_id: 1, actor_name: "Daniel Joseph", actor_role: "ceo", action: "voucher.rejected", description: "Rejected voucher AD-2026-000042", change_summary: "Awaiting CEO approval → Rejected", entity_type: "Voucher", entity_id: 7, ip: "197.250.4.19", user_agent: "VouchFlow iOS", created_at: iso(13, 14, 5) },
    { id: 5, company_id: 1, actor_name: "Neema William", actor_role: "company_admin", action: "workflow.updated", description: "Changed the approval workflow to 4 steps", change_summary: "Workflow v1 → v2", entity_type: "Workflow", entity_id: 1, ip: "41.59.12.8", user_agent: "Chrome, Windows", created_at: iso(20, 11, 20) },
    { id: 6, company_id: null, actor_name: "Grace Kimaro", actor_role: "super_admin", action: "platform.company_suspended", description: "Suspended company Nyota Agro Traders", change_summary: "Active → Suspended", entity_type: "Company", entity_id: 3, ip: "102.68.77.2", user_agent: "Chrome, Windows", created_at: iso(25, 10, 37) },
  ];

  const invoices: MockInvoice[] = [
    { id: 1, company_id: 1, number: "INV-2026-0412", description: "Business · monthly", amount: 249000, currency: "TZS", status: "paid", method: "mobile_money", provider_ref: "MM-20260901-4471", failure_reason: null, period_start: day(6), period_end: day(-24), issued_at: iso(6), paid_at: iso(6, 11, 2) },
    { id: 2, company_id: 1, number: "INV-2026-0413", description: "Business · monthly (next period)", amount: 249000, currency: "TZS", status: "pending", method: "none", provider_ref: null, failure_reason: null, period_start: day(-24), period_end: day(-54), issued_at: iso(0), paid_at: null },
    { id: 3, company_id: 2, number: "INV-2026-0411", description: "Enterprise · annual", amount: 8400000, currency: "TZS", status: "paid", method: "bank_transfer", provider_ref: "BT-20260828-1120", failure_reason: null, period_start: day(30), period_end: day(-335), issued_at: iso(30), paid_at: iso(30, 12, 0) },
    { id: 4, company_id: 3, number: "INV-2026-0407", description: "Trial", amount: 0, currency: "TZS", status: "pending", method: "none", provider_ref: null, failure_reason: null, period_start: day(11), period_end: day(-3), issued_at: iso(11), paid_at: null },
  ];

  const plans = [
    { id: 1, code: "starter", name: "Starter", name_sw: "Starter", blurb: "Up to 10 users and 100 vouchers a month.", blurb_sw: "Hadi watumiaji 10 na vocha 100 kwa mwezi.", price: 79000, currency: "TZS", billing_cycle: "monthly" as const, max_users: 10, max_vouchers_per_month: 100, max_departments: 5, max_approval_levels: 2, storage_mb: 2048, trial_days: 14, features: ["10 users", "100 vouchers / month", "2 approval levels", "PDF vouchers", "Email support"], features_sw: ["Watumiaji 10", "Vocha 100 / mwezi", "Hatua 2 za idhini", "Vocha za PDF", "Msaada kwa barua pepe"], is_active: true, is_public: true, sort_order: 1 },
    { id: 2, code: "business", name: "Business", name_sw: "Business", blurb: "Departments, branding and reporting for growing companies.", blurb_sw: "Idara, chapa na ripoti kwa kampuni zinazokua.", price: 249000, currency: "TZS", billing_cycle: "monthly" as const, max_users: 50, max_vouchers_per_month: null, max_departments: 20, max_approval_levels: 4, storage_mb: 25600, trial_days: 14, features: ["50 users", "Unlimited vouchers", "4 approval levels", "Custom branding", "Reports & exports", "Priority support"], features_sw: ["Watumiaji 50", "Vocha bila kikomo", "Hatua 4 za idhini", "Chapa yako", "Ripoti na uhamishaji", "Msaada wa kipaumbele"], is_active: true, is_public: true, sort_order: 2 },
    { id: 3, code: "premium", name: "Premium", name_sw: "Premium", blurb: "Deeper workflows and more room for larger finance teams.", blurb_sw: "Mitiririko mipana na nafasi zaidi kwa timu kubwa za fedha.", price: 590000, currency: "TZS", billing_cycle: "monthly" as const, max_users: 150, max_vouchers_per_month: null, max_departments: 60, max_approval_levels: 6, storage_mb: 102400, trial_days: 14, features: ["150 users", "Unlimited vouchers", "6 approval levels", "Advanced reports", "Priority support"], features_sw: ["Watumiaji 150", "Vocha bila kikomo", "Hatua 6 za idhini", "Ripoti za kina", "Msaada wa kipaumbele"], is_active: true, is_public: true, sort_order: 3 },
    { id: 4, code: "enterprise", name: "Enterprise", name_sw: "Enterprise", blurb: "Multiple companies, custom workflows, integrations.", blurb_sw: "Kampuni nyingi, mitiririko maalum, miunganisho.", price: 0, currency: "TZS", billing_cycle: "annual" as const, max_users: null, max_vouchers_per_month: null, max_departments: null, max_approval_levels: null, storage_mb: null, trial_days: 30, features: ["Unlimited users", "Custom workflows", "Multi-company", "API & integrations", "Dedicated manager"], features_sw: ["Watumiaji bila kikomo", "Mitiririko maalum", "Kampuni nyingi", "API na miunganisho", "Meneja maalum"], is_active: true, is_public: true, sort_order: 4 },
  ];

  return {
    companies, users, departments, voucherTypes, workflows, vouchers, approvals,
    notifications, audit, invoices, plans,
    sequences: {
      voucher: vouchers.length + 1, approval: aid + 1, notification: notifications.length + 1,
      audit: audit.length + 1, comment: 10, attachment: 1000,
      user: users.length + 1, department: departments.length + 1, step: 100, workflow: workflows.length + 1,
    },
  };
}
