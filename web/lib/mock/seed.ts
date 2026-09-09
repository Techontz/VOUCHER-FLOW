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
  legal_name: string | null;
  email: string;
  phone: string;
  address: string;
  website: string | null;
  tin: string | null;
  currency: string;
  locale: "en" | "sw";
  /** Full lockup, used on the printed document. Uploaded per company. */
  logo_url: string | null;
  /** Square mark, used wherever the interface has room for an avatar only. */
  logo_mark_url: string | null;
  /** The account a bank voucher is drawn on. */
  bank_name: string | null;
  bank_account_name: string | null;
  bank_account_number: string | null;
  bank_branch: string | null;
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
  /* Bank vouchers settle into an account; cash vouchers come out of a float
     and are acknowledged by hand. Each format carries only what it needs. */
  payee_bank: string | null;
  payee_account_name: string | null;
  payee_account_number: string | null;
  payee_bank_branch: string | null;
  cheque_number: string | null;
  cash_float: string | null;
  received_by: string | null;
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
  /* The first tenant is a real-world-shaped beverage manufacturer, so the demo
     shows the platform carrying a company's own identity — logo, letterhead,
     banking details — onto its documents. None of it is special-cased: every
     field here is one a company fills in under Branding. */
  const companies: MockCompany[] = [
    {
      id: 1,
      name: "Watercom (T) Limited",
      slug: "watercom",
      legal_name: "WATERCOM (T) LIMITED",
      email: "info@watercom.co.tz",
      phone: "+255 22 264 0831",
      address: "P.O. Box 20831, Kibada, Kisarawe II · Dar es Salaam, Tanzania",
      website: "www.watercom.co.tz",
      tin: "109-482-771",
      currency: "TZS", locale: "en",
      logo_url: "/demo/watercom-logo.png",
      logo_mark_url: "/demo/watercom-mark.png",
      bank_name: "CRDB Bank",
      bank_account_name: "WATERCOM T LIMITED",
      bank_account_number: "0250390569500",
      bank_branch: "Tower Branch",
      primary_color: "#2E3192", theme: "dark",
      voucher_footer_text:
        "This voucher is computer generated by VouchFlow and is valid without a wet stamp. "
        + "Retain the original for audit.",
      status: "active", plan_code: "business", trial_ends_at: null,
      current_period_start: iso(6), current_period_end: iso(-24), auto_renew: true, created_at: iso(600),
    },
    {
      id: 2, name: "Zamani Logistics", slug: "zamani-logistics", legal_name: "ZAMANI LOGISTICS LIMITED",
      email: "finance@zamani-demo.test", phone: "+255 713 000 202",
      address: "Nyerere Road · Dar es Salaam", website: null, tin: "112-004-889",
      currency: "TZS", locale: "en", logo_url: null, logo_mark_url: null,
      bank_name: "NMB Bank", bank_account_name: "ZAMANI LOGISTICS LTD",
      bank_account_number: "20110044552", bank_branch: "Kariakoo Branch",
      primary_color: "#22a7e8", theme: "dark",
      voucher_footer_text: "Computer generated voucher.", status: "active", plan_code: "enterprise",
      trial_ends_at: null, current_period_start: iso(30), current_period_end: iso(-335),
      auto_renew: true, created_at: iso(900),
    },
    {
      id: 3, name: "Baobab Business Solutions", slug: "baobab-solutions", legal_name: null,
      email: "hello@baobab-demo.test", phone: "+255 714 000 303",
      address: "Kijitonyama · Dar es Salaam", website: null, tin: null,
      currency: "TZS", locale: "en", logo_url: null, logo_mark_url: null,
      bank_name: null, bank_account_name: null, bank_account_number: null, bank_branch: null,
      primary_color: "#34d399", theme: "dark",
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

    U(2, 1, "Neema Shirima", "admin@watercom.test", "company_admin", "Company Administrator", "WC-0087", 5),
    U(3, 1, "Frank Kessy", "frank@watercom.test", "employee", "Procurement Officer", "WC-0114", 2),
    U(4, 1, "Rehema Kilonzo", "rehema@watercom.test", "hod", "Head of Finance", "WC-0032", 1, true),
    U(5, 1, "Emmanuel Massawe", "emmanuel@watercom.test", "ceo", "Managing Director", "WC-0008", 1, true),
    U(6, 1, "Mwajuma Hamisi", "mwajuma@watercom.test", "cashier", "Cashier · Finance", "WC-0056", 1, true),
    U(7, 1, "Baraka Ndosi", "baraka@watercom.test", "employee", "Transport Supervisor", "WC-0129", 4),
    U(8, 1, "Gloria Mtei", "gloria@watercom.test", "employee", "Quality Assurance Officer", "WC-0141", 7),
    U(9, 1, "Joseph Mrisho", "joseph@watercom.test", "hod", "Head of Procurement", "WC-0021", 2, true),
    U(12, 1, "Salum Bakari", "salum@watercom.test", "hod", "Transport Manager", "WC-0044", 4, true),
    U(13, 1, "Anna Lyimo", "anna@watercom.test", "hod", "Head of Human Resources", "WC-0061", 5, true),
    U(14, 1, "Doreen Massawe", "doreen@watercom.test", "employee", "Human Resources Officer", "WC-0152", 5),

    U(10, 2, "Erick Mbise", "admin@zamani.test", "company_admin", "Group Administrator", "ZL-0001", 8),
    U(11, 2, "Salma Juma", "salma@zamani.test", "finance", "Finance Controller", "ZL-0004", 8, true),
  ];

  const departments = [
    { id: 1, company_id: 1, name: "Finance", code: "FIN", cost_centre: "CC-FIN", hod_user_id: 4, manager_user_id: 5 },
    { id: 2, company_id: 1, name: "Procurement", code: "PRO", cost_centre: "CC-PRO", hod_user_id: 9, manager_user_id: 5 },
    { id: 3, company_id: 1, name: "Production", code: "PRD", cost_centre: "CC-PRD", hod_user_id: 9, manager_user_id: 5 },
    { id: 4, company_id: 1, name: "Transport & Logistics", code: "TRN", cost_centre: "CC-TRN", hod_user_id: 12, manager_user_id: 5 },
    { id: 5, company_id: 1, name: "Human Resources", code: "HR", cost_centre: "CC-HR", hod_user_id: 13, manager_user_id: 5 },
    { id: 6, company_id: 1, name: "Sales & Distribution", code: "SLS", cost_centre: "CC-SLS", hod_user_id: 12, manager_user_id: 5 },
    { id: 7, company_id: 1, name: "Quality Assurance", code: "QA", cost_centre: "CC-QA", hod_user_id: 4, manager_user_id: 5 },
    { id: 8, company_id: 2, name: "Fleet", code: "FLT", cost_centre: "CC-FLT", hod_user_id: 11, manager_user_id: 10 },
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
    bank?: { name: string; accountName: string; accountNumber: string; branch: string; cheque?: string };
    float?: string; receivedBy?: string;
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
      payee_bank: spec.bank?.name ?? null,
      payee_account_name: spec.bank?.accountName ?? null,
      payee_account_number: spec.bank?.accountNumber ?? null,
      payee_bank_branch: spec.bank?.branch ?? null,
      cheque_number: spec.bank?.cheque ?? null,
      cash_float: spec.float ?? null,
      received_by: spec.receivedBy ?? null,
      created_at: iso(spec.daysAgo, 7, 58),
      attachments: (spec.files ?? []).map((f, i) => ({
        id: id * 10 + i, name: f.name, mime: f.mime, size_bytes: f.size,
      })),
      comments: [],
    };
  };

  const vouchers: MockVoucher[] = [
    /* Live work, positioned so every persona opens the prototype with a real
       queue in front of them and an empty one the moment they clear it. */

    // ── awaiting the Procurement head ──
    V({
      number: "PV-2026-001248", kind: "bank", typeId: 101, dept: 2, requester: 3,
      payee: "Kibo Preforms Limited", purpose: "PET preforms — Afiya 500 ml line",
      desc: "420,000 × 24.5 g preforms for the Afiya still-water line, against framework contract WC/PR/2026/04.",
      amount: 18400000, method: "Bank Transfer", category: "Raw materials", ref: "INV-KP-88213",
      bank: { name: "NMB Bank", accountName: "Kibo Preforms Limited", accountNumber: "40910022317", branch: "Ubungo Branch" },
      daysAgo: 2, status: "in_review", step: 2,
      files: [{ name: "invoice-KP-88213.pdf", mime: "application/pdf", size: 184320 },
              { name: "goods-received-note.jpg", mime: "image/jpeg", size: 942080 }],
      trail: [{ action: "created", actor: 3, daysAgo: 2, hour: 7 }, { action: "submitted", actor: 3, step: 1, daysAgo: 2, hour: 8 }],
    }),

    // ── signed by the Transport head, still to be sent onward ──
    V({
      number: "PV-2026-001247", kind: "bank", typeId: 101, dept: 4, requester: 7,
      payee: "Coastal Transporters Limited", purpose: "Distribution haulage — Mwanza and Mbeya routes",
      desc: "Outbound haulage of 38 pallets of finished goods to the Mwanza and Mbeya depots, week 36.",
      amount: 6750000, method: "Bank Transfer", category: "Distribution", ref: "INV-CT-4471",
      bank: { name: "CRDB Bank", accountName: "Coastal Transporters Ltd", accountNumber: "0152447199031", branch: "Nyerere Road Branch" },
      daysAgo: 3, status: "in_review", step: 2, signedAt: iso(2, 9, 14),
      files: [{ name: "delivery-schedule.pdf", mime: "application/pdf", size: 512000 }],
      trail: [
        { action: "created", actor: 7, daysAgo: 3, hour: 7 },
        { action: "submitted", actor: 7, step: 1, daysAgo: 3, hour: 8 },
        { action: "signed", actor: 12, step: 2, signed: true, daysAgo: 2, hour: 9, comment: "Rates match the 2026 haulage schedule. Both depots confirmed receipt windows." },
      ],
    }),

    // ── awaiting the HR head ──
    V({
      number: "PC-2026-000324", kind: "cash", typeId: 102, dept: 5, requester: 14,
      payee: "Bahati Catering Services", purpose: "Staff canteen supplies — September",
      desc: "Monthly canteen provisions for the Kibada plant, 240 staff meals per week.",
      amount: 940000, method: "Cash", category: "Staff welfare", ref: "RCP-1180",
      float: "Kibada plant petty cash float",
      daysAgo: 1, status: "in_review", step: 2,
      trail: [{ action: "created", actor: 14, daysAgo: 1, hour: 8 }, { action: "submitted", actor: 14, step: 1, daysAgo: 1, hour: 9 }],
    }),

    // ── awaiting the Managing Director ──
    V({
      number: "PV-2026-001245", kind: "bank", typeId: 101, dept: 3, requester: 3,
      payee: "BOC Tanzania Limited", purpose: "Food-grade CO₂ — Supa Cola line",
      desc: "Twelve tonnes of beverage-grade carbon dioxide for the Supa Cola carbonation plant.",
      amount: 9200000, method: "Bank Transfer", category: "Raw materials", ref: "INV-BOC-2214",
      bank: { name: "Stanbic Bank", accountName: "BOC Tanzania Limited", accountNumber: "9120044178", branch: "Mikocheni Branch" },
      daysAgo: 5, status: "in_review", step: 3,
      files: [{ name: "certificate-of-analysis.pdf", mime: "application/pdf", size: 96000 }],
      trail: [
        { action: "created", actor: 3, daysAgo: 5, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 5, hour: 8 },
        { action: "signed", actor: 9, step: 2, signed: true, daysAgo: 4, hour: 9 },
        { action: "forwarded", actor: 9, step: 2, daysAgo: 4, hour: 10, comment: "Checked against the production plan for October." },
      ],
    }),
    V({
      number: "PV-2026-001244", kind: "bank", typeId: 101, dept: 1, requester: 3,
      payee: "TANESCO", purpose: "Kibada plant electricity — August",
      desc: "Industrial supply for the Kibada bottling plant, meter 41-882-0173, August 2026.",
      amount: 14850000, method: "Bank Transfer", category: "Utilities", ref: "BILL-4188-08",
      bank: { name: "CRDB Bank", accountName: "Tanzania Electric Supply Co Ltd", accountNumber: "0150310099200", branch: "Azikiwe Branch" },
      daysAgo: 6, status: "in_review", step: 3,
      files: [{ name: "tanesco-august.pdf", mime: "application/pdf", size: 220000 }],
      trail: [
        { action: "created", actor: 3, daysAgo: 6, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 6, hour: 8 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 5, hour: 9 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 5, hour: 10 },
      ],
    }),
    V({
      number: "PC-2026-000322", kind: "cash", typeId: 102, dept: 7, requester: 8,
      payee: "Afri-Chem Supplies", purpose: "Laboratory reagents — water testing",
      desc: "Microbiological media and reagents for routine potable-water testing.",
      amount: 1320000, method: "Cash", category: "Quality control", ref: "QT-7741",
      float: "Laboratory petty cash float",
      daysAgo: 4, status: "in_review", step: 3,
      trail: [
        { action: "created", actor: 8, daysAgo: 4, hour: 8 },
        { action: "submitted", actor: 8, step: 1, daysAgo: 4, hour: 9 },
        { action: "signed", actor: 4, step: 2, signed: true, daysAgo: 3, hour: 11 },
        { action: "forwarded", actor: 4, step: 2, daysAgo: 3, hour: 11 },
      ],
    }),

    // ── approved, waiting on the cashier ──
    V({
      number: "PV-2026-001240", kind: "bank", typeId: 101, dept: 2, requester: 3,
      payee: "Tanpack Labels Limited", purpose: "Shrink labels — Afiya and Jembe",
      desc: "Roll-fed shrink sleeves for the Afiya 500 ml and Jembe Energy 300 ml lines.",
      amount: 7600000, method: "Bank Transfer", category: "Packaging", ref: "INV-TP-6620",
      bank: { name: "NMB Bank", accountName: "Tanpack Labels Limited", accountNumber: "40120087755", branch: "Chang'ombe Branch" },
      daysAgo: 8, status: "approved", step: 4,
      files: [{ name: "artwork-approval.pdf", mime: "application/pdf", size: 310000 }],
      trail: [
        { action: "created", actor: 3, daysAgo: 8, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 8, hour: 8 },
        { action: "signed", actor: 9, step: 2, signed: true, daysAgo: 7, hour: 9 },
        { action: "forwarded", actor: 9, step: 2, daysAgo: 7, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 6, hour: 15, comment: "Cleared for payment." },
      ],
    }),
    V({
      number: "PC-2026-000318", kind: "cash", typeId: 102, dept: 4, requester: 7,
      payee: "Msasani Motor Spares", purpose: "Tyres and spares — delivery truck T 4471 DTX",
      desc: "Four drive tyres and a service kit for the Mbeya route truck.",
      amount: 2150000, method: "Cash", category: "Fleet maintenance", ref: "RCP-3312",
      float: "Transport petty cash float",
      daysAgo: 9, status: "approved", step: 4,
      trail: [
        { action: "created", actor: 7, daysAgo: 9, hour: 7 },
        { action: "submitted", actor: 7, step: 1, daysAgo: 9, hour: 8 },
        { action: "signed", actor: 12, step: 2, signed: true, daysAgo: 8, hour: 9 },
        { action: "forwarded", actor: 12, step: 2, daysAgo: 8, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 7, hour: 15 },
      ],
    }),
    V({
      number: "PV-2026-001239", kind: "bank", typeId: 101, dept: 5, requester: 14,
      payee: "National Social Security Fund", purpose: "Statutory contributions — August 2026",
      desc: "Employer and employee NSSF contributions for 214 staff, August payroll.",
      amount: 5480000, method: "Bank Transfer", category: "Statutory", ref: "NSSF-08-2026",
      bank: { name: "CRDB Bank", accountName: "National Social Security Fund", accountNumber: "0150200011003", branch: "Tower Branch" },
      daysAgo: 10, status: "approved", step: 4,
      trail: [
        { action: "created", actor: 14, daysAgo: 10, hour: 7 },
        { action: "submitted", actor: 14, step: 1, daysAgo: 10, hour: 8 },
        { action: "signed", actor: 13, step: 2, signed: true, daysAgo: 9, hour: 9 },
        { action: "forwarded", actor: 13, step: 2, daysAgo: 9, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 8, hour: 15 },
      ],
    }),

    // ── closed ──
    V({
      number: "PV-2026-001236", kind: "bank", typeId: 101, dept: 3, requester: 3,
      payee: "Kilimanjaro Sugar Distributors", purpose: "Refined sugar — 20 tonnes",
      desc: "Refined white sugar for the Supa Cola and Afiya juice lines, September production run.",
      amount: 22300000, method: "Bank Transfer", category: "Raw materials", ref: "INV-KS-1180",
      bank: { name: "NBC Bank", accountName: "Kilimanjaro Sugar Distributors", accountNumber: "011103004471", branch: "Moshi Branch", cheque: "CHQ-004471" },
      daysAgo: 6, status: "paid", step: null,
      paymentRef: "TRF-2026-884120", paidBy: "Mwajuma Hamisi",
      trail: [
        { action: "created", actor: 3, daysAgo: 6, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 6, hour: 8 },
        { action: "signed", actor: 9, step: 2, signed: true, daysAgo: 5, hour: 9 },
        { action: "forwarded", actor: 9, step: 2, daysAgo: 5, hour: 10 },
        { action: "approved", actor: 5, step: 3, daysAgo: 5, hour: 15 },
        { action: "paid", actor: 6, step: 4, daysAgo: 4, hour: 10, comment: "Funds released and reference recorded against the voucher." },
      ],
    }),
    V({
      number: "AD-2026-000042", kind: "cash", typeId: 104, dept: 4, requester: 7,
      payee: "Baraka Ndosi", purpose: "Travel advance — Mbeya depot stock audit",
      desc: "Three nights, per diem and fuel for the quarterly Mbeya depot stock count.",
      amount: 860000, method: "Mobile Money", category: "Travel", ref: "ADV-0042",
      float: "Transport petty cash float",
      daysAgo: 14, status: "rejected", step: null,
      trail: [
        { action: "created", actor: 7, daysAgo: 14, hour: 7 },
        { action: "submitted", actor: 7, step: 1, daysAgo: 14, hour: 8 },
        { action: "signed", actor: 12, step: 2, signed: true, daysAgo: 13, hour: 9 },
        { action: "forwarded", actor: 12, step: 2, daysAgo: 13, hour: 10 },
        { action: "rejected", actor: 5, step: 3, daysAgo: 13, hour: 14, comment: "The Mbeya depot holds its own float — draw the advance there and resubmit against CC-TRN." },
      ],
    }),

    // ── back with the requester ──
    V({
      number: "EX-2026-000011", kind: "bank", typeId: 103, dept: 2, requester: 3,
      payee: "Sumaria Industries Limited", purpose: "Closures and caps — August arrears",
      desc: "Outstanding balance on 1.2 million 28 mm closures delivered in August.",
      amount: 3150000, method: "Bank Transfer", category: "Packaging", ref: "INV-SI-5590",
      bank: { name: "Exim Bank", accountName: "Sumaria Industries Ltd", accountNumber: "0100200455", branch: "Nyerere Road Branch" },
      daysAgo: 5, status: "changes_requested", step: null,
      trail: [
        { action: "created", actor: 3, daysAgo: 5, hour: 7 },
        { action: "submitted", actor: 3, step: 1, daysAgo: 5, hour: 8 },
        { action: "changes_requested", actor: 9, step: 2, daysAgo: 4, hour: 11, comment: "Attach the August goods-received note and the reconciled supplier statement before this goes forward." },
      ],
    }),
    V({
      number: "PV-2026-001249", kind: "bank", typeId: 101, dept: 2, requester: 3,
      payee: "Coastal Packaging Limited", purpose: "Shrink film — October order",
      desc: "Draft pending the supplier's confirmed quotation.",
      amount: 4100000, method: "Bank Transfer", category: "Packaging", ref: "",
      daysAgo: 0, status: "draft", step: null,
      trail: [{ action: "created", actor: 3, daysAgo: 0, hour: 9 }],
    }),
  ];

  // A little history so charts and reports are not empty.
  const payees = ["Coastal Transporters Limited", "Afri-Chem Supplies", "DAWASA", "Tanpack Labels Limited", "Msasani Motor Spares", "Kariakoo Stationers"];
  const purposes = ["Depot haulage retainer", "Water treatment chemicals", "Plant water supply", "Label reprint run", "Fleet servicing", "Plant consumables"];
  let hist = 0;
  for (let monthsAgo = 6; monthsAgo >= 1; monthsAgo--) {
    for (let i = 0; i < 3 + (monthsAgo % 3); i++) {
      hist++;
      const daysAgo = monthsAgo * 30 + i * 3;
      const rejected = hist % 9 === 0;
      // Spread the history across the company's employees and their own
      // departments, so each persona's register looks like a real caseload
      // and the signing step resolves to that department's actual head.
      // Spread across the company's own people and their real departments, so
      // every register looks like a caseload and each signing step resolves to
      // that department's actual head.
      const [requesterId, deptId, hodId] = ([
        [3, 2, 9], [3, 3, 9], [7, 4, 12], [7, 6, 12], [14, 5, 13], [8, 7, 4], [3, 1, 4],
      ] as const)[hist % 7];
      vouchers.push(
        V({
          number: `PV-2026-${String(1100 + hist).padStart(6, "0")}`,
          kind: hist % 3 === 0 ? "cash" : "bank",
          typeId: 101, dept: deptId, requester: requesterId,
          payee: payees[hist % payees.length], purpose: purposes[hist % purposes.length],
          desc: "Recurring operational cost, approved against the monthly budget.",
          amount: (2 + (hist * 7) % 88) * 100000,
          method: hist % 3 === 0 ? "Cash" : "Bank Transfer",
          category: ["Distribution", "Packaging", "Utilities", "Fleet maintenance", "Quality control"][hist % 5],
          ref: `INV-${20000 + hist}`, daysAgo,
          status: rejected ? "rejected" : "paid",
          step: null,
          paymentRef: rejected ? undefined : `TRX-${700000 + hist}`,
          paidBy: rejected ? undefined : "Mwajuma Hamisi",
          bank: hist % 3 === 0 ? undefined : {
            name: ["CRDB Bank", "NMB Bank", "NBC Bank"][hist % 3],
            accountName: payees[hist % payees.length],
            accountNumber: `01${(500000 + hist * 137).toString().padStart(9, "0")}`,
            branch: ["Tower Branch", "Ubungo Branch", "Kariakoo Branch"][hist % 3],
          },
          float: hist % 3 === 0 ? "Kibada plant petty cash float" : undefined,
          receivedBy: hist % 3 === 0 && !rejected ? payees[hist % payees.length] : undefined,
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
      number: "PV-2026-000001", kind: "bank", typeId: 201, dept: 8, requester: 11,
      payee: "Kilimanjaro Fuel Supplies", purpose: "Diesel for the Arusha convoy",
      desc: "Fuel for six trucks on the Arusha run, week 36.",
      amount: 12400000, method: "Bank Transfer", category: "Transport", ref: "FU-2201",
      daysAgo: 2, status: "in_review", step: 3,
    }),
    company_id: 2, workflow_id: 2,
  });

  vouchers[0].comments = [
    { id: 1, user_id: 3, body: "Supplier holds this price until the 30th; the October run needs the preforms on site by the 24th.", created_at: iso(2, 9, 20) },
  ];
  vouchers[3].comments = [
    { id: 2, user_id: 9, body: "Checked against the October production plan — the volume matches the Supa Cola schedule.", created_at: iso(4, 11, 5) },
  ];

  users.forEach((u) => {
    u.voucher_count = vouchers.filter((v) => v.requester_id === u.id).length;
  });

  const notifications: MockNotification[] = [
    { id: 1, user_id: 9, company_id: 1, type: "voucher.awaiting", icon: "ph-signature", title: "PV-2026-001248 needs your signature", title_sw: "PV-2026-001248 inahitaji sahihi yako", body: "Frank Kessy submitted TZS 18,400,000 for PET preforms.", body_sw: "Frank Kessy alituma TZS 18,400,000 kwa preforms za PET.", entity_type: "Voucher", entity_id: 1, read_at: null, created_at: iso(0, 8, 2) },
    { id: 2, user_id: 13, company_id: 1, type: "voucher.awaiting", icon: "ph-signature", title: "PC-2026-000324 needs your signature", title_sw: "PC-2026-000324 inahitaji sahihi yako", body: "Doreen Massawe submitted TZS 940,000 for canteen supplies.", body_sw: "Doreen Massawe alituma TZS 940,000 kwa vifaa vya mkahawa.", entity_type: "Voucher", entity_id: 3, read_at: null, created_at: iso(0, 9, 10) },
    { id: 3, user_id: 5, company_id: 1, type: "voucher.awaiting", icon: "ph-seal-check", title: "3 vouchers await your approval", title_sw: "Vocha 3 zinasubiri idhini yako", body: "TZS 25,370,000 signed and forwarded for the final decision.", body_sw: "TZS 25,370,000 zimesainiwa na kutumwa kwa uamuzi wa mwisho.", entity_type: "Voucher", entity_id: 4, read_at: null, created_at: iso(0, 10, 14) },
    { id: 4, user_id: 6, company_id: 1, type: "voucher.awaiting", icon: "ph-wallet", title: "3 vouchers cleared for payment", title_sw: "Vocha 3 zimeidhinishwa kwa malipo", body: "TZS 15,230,000 approved and awaiting release.", body_sw: "TZS 15,230,000 zimeidhinishwa na zinasubiri kutolewa.", entity_type: "Voucher", entity_id: 7, read_at: null, created_at: iso(0, 11, 0) },
    { id: 5, user_id: 3, company_id: 1, type: "voucher.changes_requested", icon: "ph-arrow-u-up-left", title: "EX-2026-000011 needs changes", title_sw: "EX-2026-000011 inahitaji mabadiliko", body: 'Joseph Mrisho: "Attach the August goods-received note before this goes forward."', body_sw: 'Joseph Mrisho: "Ambatisha risiti ya bidhaa ya Agosti kabla haijaendelea."', entity_type: "Voucher", entity_id: 12, read_at: null, created_at: iso(4, 11, 5) },
    { id: 6, user_id: 7, company_id: 1, type: "voucher.rejected", icon: "ph-x-circle", title: "AD-2026-000042 was rejected", title_sw: "AD-2026-000042 imekataliwa", body: 'Emmanuel Massawe: "The Mbeya depot holds its own float."', body_sw: 'Emmanuel Massawe: "Ghala la Mbeya lina fedha zake."', entity_type: "Voucher", entity_id: 11, read_at: null, created_at: iso(13, 14, 5) },
    { id: 7, user_id: 3, company_id: 1, type: "voucher.paid", icon: "ph-check-circle", title: "PV-2026-001236 has been paid", title_sw: "PV-2026-001236 imelipwa", body: "Mwajuma Hamisi released TZS 22,300,000 · reference TRF-2026-884120.", body_sw: "Mwajuma Hamisi alitoa TZS 22,300,000 · kumbukumbu TRF-2026-884120.", entity_type: "Voucher", entity_id: 10, read_at: iso(13), created_at: iso(14, 10, 12) },
    { id: 8, user_id: 2, company_id: 1, type: "billing", icon: "ph-credit-card", title: "Payment received", title_sw: "Malipo yamepokelewa", body: "TZS 249,000 for the Business plan.", body_sw: "TZS 249,000 kwa mpango wa Business.", entity_type: null, entity_id: null, read_at: null, created_at: iso(6, 11, 2) },
  ];

  const audit: MockAudit[] = [
    { id: 1, company_id: 1, actor_name: "Salum Bakari", actor_role: "hod", action: "voucher.signed", description: "Signed voucher PV-2026-001247", change_summary: "Awaiting HOD signature → Signed", entity_type: "Voucher", entity_id: 2, ip: "41.59.12.8", user_agent: "Chrome, Windows", created_at: iso(2, 9, 14) },
    { id: 2, company_id: 1, actor_name: "Frank Kessy", actor_role: "employee", action: "voucher.submitted", description: "Submitted voucher PV-2026-001248", change_summary: "Draft → Awaiting HOD signature", entity_type: "Voucher", entity_id: 1, ip: "197.250.4.19", user_agent: "VouchFlow Android", created_at: iso(2, 8, 2) },
    { id: 3, company_id: 1, actor_name: "Mwajuma Hamisi", actor_role: "cashier", action: "voucher.paid", description: "Recorded payment for PV-2026-001236", change_summary: "Approved → Paid", entity_type: "Voucher", entity_id: 10, ip: "41.59.12.61", user_agent: "Safari, macOS", created_at: iso(14, 10, 12) },
    { id: 4, company_id: 1, actor_name: "Emmanuel Massawe", actor_role: "ceo", action: "voucher.rejected", description: "Rejected voucher AD-2026-000042", change_summary: "Awaiting approval → Rejected", entity_type: "Voucher", entity_id: 11, ip: "197.250.4.19", user_agent: "VouchFlow iOS", created_at: iso(13, 14, 5) },
    { id: 5, company_id: 1, actor_name: "Neema Shirima", actor_role: "company_admin", action: "branding.updated", description: "Uploaded the company logo and set the document letterhead", change_summary: "Branding updated", entity_type: "Company", entity_id: 1, ip: "41.59.12.8", user_agent: "Chrome, Windows", created_at: iso(30, 9, 40) },
    { id: 6, company_id: 1, actor_name: "Neema Shirima", actor_role: "company_admin", action: "workflow.updated", description: "Changed the approval workflow to 4 steps", change_summary: "Workflow v1 → v2", entity_type: "Workflow", entity_id: 1, ip: "41.59.12.8", user_agent: "Chrome, Windows", created_at: iso(20, 11, 20) },
    { id: 7, company_id: null, actor_name: "Grace Kimaro", actor_role: "super_admin", action: "platform.company_created", description: "Provisioned company Watercom (T) Limited", change_summary: "New tenant", entity_type: "Company", entity_id: 1, ip: "102.68.77.2", user_agent: "Chrome, Windows", created_at: iso(600, 10, 37) },
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
