/** v2 routes a voucher Employee → HOD → CEO → Cashier. */
export type Role =
  | "super_admin" | "company_admin" | "employee" | "hod" | "manager" | "ceo" | "cashier" | "finance" | "director";

export interface User {
  id: number;
  company_id: number | null;
  name: string;
  initials: string;
  email: string;
  phone: string | null;
  role: Role;
  role_label: string;
  employee_code: string | null;
  job_title: string | null;
  status: "active" | "invited" | "suspended";
  locale: "en" | "sw";
  theme: "light" | "dark";
  department_id: number | null;
  department?: { id: number; name: string } | null;
  avatar_url: string | null;
  has_signature: boolean;
  signature_updated_at: string | null;
  two_factor_enabled: boolean;
  last_login_at: string | null;
  joined_at: string | null;
  voucher_count?: number;
}

export interface Plan {
  id: number;
  code: string;
  name: string;
  label: string;
  blurb: string | null;
  price: number;
  currency: string;
  billing_cycle: "monthly" | "annual";
  max_users: number | null;
  max_vouchers_per_month: number | null;
  max_departments: number | null;
  max_approval_levels: number | null;
  storage_mb: number | null;
  trial_days: number;
  features: string[];
  is_active: boolean;
  is_public: boolean;
  sort_order: number;
  companies_count?: number;
}

export interface Company {
  id: number;
  name: string;
  slug: string;
  legal_name: string | null;
  email: string;
  phone: string | null;
  address: string | null;
  website: string | null;
  country: string;
  currency: string;
  locale: "en" | "sw";
  timezone: string;
  logo_url: string | null;
  /** Square mark for compact interface surfaces; the lockup is logo_url. */
  logo_mark_url: string | null;
  tin: string | null;
  /** The account a bank voucher is drawn on. */
  bank_name: string | null;
  bank_account_name: string | null;
  bank_account_number: string | null;
  bank_branch: string | null;
  primary_color: string;
  secondary_color?: string | null;
  accent_color: string;
  theme: "light" | "dark";
  /** The interface palette this company works in; see styles/app.css. */
  color_theme: ColorTheme;
  voucher_footer_text: string | null;
  /** The voucher design new documents render in; see VoucherTemplate. */
  voucher_template?: string;
  voucher_template_name?: string;
  voucher_template_changes_used?: number;
  voucher_template_changes_allowed?: number;
  voucher_template_changes_remaining?: number;
  status: "trial" | "active" | "past_due" | "suspended" | "cancelled";
  is_usable: boolean;
  is_expired: boolean;
  days_remaining: number | null;
  trial_ends_at: string | null;
  current_period_start: string | null;
  current_period_end: string | null;
  auto_renew: boolean;
  plan: Plan | null;
  plan_id: number | null;
  settings: Record<string, unknown>;
  users_count?: number;
  vouchers_count?: number;
  created_at: string | null;
}

export type ColorTheme = "blue" | "emerald" | "violet" | "rose";

export interface Department {
  id: number;
  name: string;
  code: string | null;
  cost_centre: string | null;
  is_active: boolean;
  hod_user_id: number | null;
  manager_user_id: number | null;
  hod?: { id: number; name: string; status?: string } | null;
  manager?: { id: number; name: string; status?: string } | null;
  users_count?: number;
  vouchers_count?: number;
  spend?: number;
}

export interface WorkflowStep {
  id?: number;
  position: number;
  name: string;
  name_sw: string | null;
  label: string;
  role: "employee" | "hod" | "manager" | "ceo" | "cashier" | "finance" | "director" | "custom";
  role_label: string;
  assigned_user_id: number | null;
  assigned_user?: { id: number; name: string; role?: string; status?: string } | null;
  assignee_hint: string | null;
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
  is_request_step: boolean;
}

export interface Workflow {
  id: number;
  name: string;
  name_sw?: string | null;
  label?: string;
  description: string | null;
  /** null = the route for every voucher type without a route of its own. */
  voucher_type_id: number | null;
  voucher_type?: { id: number; name: string; name_sw: string | null } | null;
  is_default: boolean;
  is_active: boolean;
  version: number;
  route_summary?: string;
  steps: WorkflowStep[];
  vouchers_count?: number;
  in_flight_count?: number;
  updated_at: string | null;
}

/** Why a workflow step would find nobody in a department. */
export type RoutingGap =
  | "no_hod" | "inactive_hod" | "no_manager" | "inactive_manager"
  | "inactive_person" | "missing_person" | "no_person_named" | "no_one_with_role";

/** GET /workflows/{id}/routing — who acts at each step, per department. */
export interface WorkflowRouting {
  workflow_id: number;
  steps: {
    id: number; position: number; name: string; name_sw: string | null;
    role: WorkflowStep["role"]; role_label: string;
    is_request_step: boolean; is_payment_step: boolean;
    assignment: "requester" | "named" | "department_head" | "department_manager" | "role" | "unassigned";
    min_amount: number | null; max_amount: number | null;
  }[];
  departments: {
    id: number; name: string; is_active: boolean;
    hod: { id: number; name: string; role: string; status: string } | null;
    manager: { id: number; name: string; role: string; status: string } | null;
    cells: { step_id: number; people: { id: number; name: string; role: string }[]; gap: RoutingGap | null }[];
    gaps: number;
  }[];
  gaps: number;
}

export interface VoucherType {
  id: number;
  name: string;
  name_sw: string | null;
  label: string;
  code: string;
  prefix: string;
  number_format: string;
  seq_padding: number;
  next_number: number;
  reset_yearly: boolean;
  is_active: boolean;
  sort_order: number;
  next_number_preview: string;
  vouchers_count?: number;
}

export interface VoucherActions {
  view: boolean;
  edit: boolean;
  delete: boolean;
  submit: boolean;
  sign: boolean;
  submit_signed: boolean;
  approve: boolean;
  reject: boolean;
  request_changes: boolean;
  /** The cashier releases funds and closes the voucher. */
  pay: boolean;
  /** Documents may be added — also after approval and payment, for receipts. */
  attach?: boolean;
  cancel: boolean;
  comment: boolean;
  print: boolean;
  download: boolean;
}

export interface TimelineRow {
  position: number | null;
  name: string;
  name_sw: string | null;
  sub: string;
  sub_sw: string;
  person: string;
  /** Job title of whoever acted, for the printed signature panels. */
  person_title?: string;
  act: string;
  act_sw: string;
  when: string | null;
  comment: string | null;
  signature: string | null;
  capabilities: Record<string, boolean>;
  capability_text: string;
  state: "done" | "current" | "pending" | "rejected";
  icon: string;
}

export interface Attachment {
  id: number;
  name: string;
  mime_type: string | null;
  size_bytes: number;
  size: string;
  is_image: boolean;
  icon: string;
  url: string;
  uploaded_by?: string;
  created_at: string | null;
  /** "payment_acknowledgement" for a receiver's signed copy; null otherwise. */
  document_type?: "payment_acknowledgement" | string | null;
  /** The payment a signed acknowledgement covers. */
  voucher_payment_id?: number | null;
}

/**
 * One release of money against a voucher. A voucher approved for 10,000,000
 * may be paid 9,000,000 now and 1,000,000 later — two payments, each with its
 * own receiver, reference and signed acknowledgement.
 */
export interface VoucherPayment {
  id: number;
  /** 1, 2, … in the order the money left. */
  sequence: number;
  /** The voucher number with the sequence, e.g. "PV-2026-000083/1". */
  reference: string;
  amount: number;
  amount_text: string;
  balance_after: number;
  balance_after_text: string;
  payment_method: string | null;
  payment_reference: string | null;
  cheque_number: string | null;
  received_by: string | null;
  receiver_id_number: string | null;
  payment_date: string | null;
  paid_at: string | null;
  /** The cashier's name. */
  paid_by: string | null;
  /** The cashier who released this payment (older servers send only the name). */
  paid_by_id?: number | null;
  note: string | null;
  /** When the receiver's signed copy was filed; null while it is outstanding. */
  acknowledged_at: string | null;
  acknowledgement_url: string;
  acknowledgement_attachment_ids: number[];
}

export interface Comment {
  id: number;
  body: string;
  user: { id: number; name: string; initials: string; role_label: string; department: string | null } | null;
  created_at: string | null;
}

export interface Voucher {
  id: number;
  number: string;
  status: "draft" | "in_review" | "changes_requested" | "approved" | "paid" | "rejected" | "cancelled";
  /** Bank transfer or physical cash — each prints its own A4 layout. */
  kind: "bank" | "cash";
  status_key: string;
  status_label: string;
  status_label_en: string;
  status_label_sw: string;
  status_tag: string;
  payee: string;
  purpose: string;
  description: string | null;
  amount: number;
  currency: string;
  amount_text: string;
  /** Released so far — the whole amount once paid, part of it while a balance remains. */
  amount_paid?: number;
  amount_paid_text?: string;
  /** Still owed. Zero once paid. */
  balance?: number;
  balance_text?: string;
  /** Approved, some money out, some still owed (status_key "partially_paid"). */
  is_partially_paid?: boolean;
  amount_in_words: string | null;
  payment_method: string | null;
  account_ref: string | null;
  category: string | null;
  cost_centre: string | null;
  voucher_date: string | null;
  notes_to_approver: string | null;
  verification_code: string | null;
  voucher_type_id: number;
  voucher_type?: { id: number; name: string; label: string };
  department_id: number | null;
  department?: { id: number; name: string } | null;
  requester_id: number;
  requester?: { id: number; name: string; initials: string; job_title: string | null } | null;
  workflow_id: number | null;
  current_step_position: number | null;
  current_step?: {
    id: number; position: number; name: string; role: string;
    capabilities: Record<string, boolean>;
  } | null;
  is_signed_at_current_step: boolean;
  is_editable: boolean;
  is_terminal: boolean;
  submitted_at: string | null;
  approved_at: string | null;
  rejected_at: string | null;
  paid_at: string | null;
  /** The day the money moved, as recorded by the cashier. */
  payment_date?: string | null;
  /** List rows only: who refused or returned the voucher, when it was. */
  decided_by?: string | null;
  payment_reference: string | null;
  /**
   * Who released the money. The API sends the person ({ id, name, job_title });
   * the local fixture sends a plain name. Read it with personName().
   */
  paid_by: string | { id: number; name: string; job_title: string | null } | null;
  /* Particulars that belong to one format only. */
  payee_bank: string | null;
  payee_account_name: string | null;
  payee_account_number: string | null;
  payee_bank_branch: string | null;
  cheque_number: string | null;
  cash_float: string | null;
  received_by: string | null;
  created_at: string | null;
  updated_at: string | null;
  attachments_count?: number;
  comments_count?: number;
  actions?: VoucherActions;
  timeline?: TimelineRow[];
  attachments?: Attachment[];
  comments?: Comment[];
  /** Detailed voucher only: every release of money, in order. */
  payments?: VoucherPayment[];
  workflow?: Workflow;
}

export interface AppNotification {
  id: number;
  type: string;
  icon: string;
  title: string;
  body: string | null;
  entity_type: string | null;
  entity_id: number | null;
  action_url: string | null;
  is_unread: boolean;
  read_at: string | null;
  created_at: string | null;
}

export interface AuditEntry {
  id: number;
  action: string;
  description: string;
  change_summary: string | null;
  entity_type: string | null;
  entity_id: number | null;
  actor: { id: number | null; name: string; role: string | null; initials: string };
  company?: string | null;
  company_id: number | null;
  ip: string | null;
  user_agent: string | null;
  created_at: string | null;
}

export interface Invoice {
  id: number;
  number: string;
  description: string;
  amount: number;
  tax: number;
  total: number;
  currency: string;
  amount_text: string;
  status: "pending" | "paid" | "failed" | "refunded" | "void";
  status_tag: string;
  method: string;
  method_label: string;
  provider_ref: string | null;
  failure_reason: string | null;
  period_start: string | null;
  period_end: string | null;
  issued_at: string | null;
  paid_at: string | null;
  company?: string | null;
  company_id: number;
  created_at: string | null;
}

export interface Subscription {
  id: number;
  status: string;
  billing_cycle: "monthly" | "annual";
  amount: number;
  currency: string;
  seats: number | null;
  starts_at: string | null;
  trial_ends_at: string | null;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  is_expired: boolean;
  plan: Plan | null;
  company_id: number;
  company?: string | null;
}

export interface UsageMetric {
  label: string;
  used: number;
  limit: number | null;
  unit: string;
  unlimited: boolean;
  percent: number | null;
  exceeded: boolean;
}

export interface Usage {
  plan: string | null;
  users: UsageMetric;
  vouchers_this_month: UsageMetric;
  departments: UsageMetric;
  storage: UsageMetric;
  approval_levels: { label: string; limit: number | null };
}

export interface DashboardStat {
  /** Stable translation key, e.g. "dash.stat.awaitingApproval". */
  key?: string;
  params?: Record<string, string | number>;
  label: string;
  value: string;
  sub: string;
  sub_key?: string | null;
  sub_params?: Record<string, string | number>;
  icon?: string;
  trend?: string | null;
  up?: boolean | null;
}

/** Which dashboard the backend built — decided by workflow steps, not only by role. */
export type DashboardView = "employee" | "hod" | "approver" | "cashier" | "admin" | "platform";

export interface DashboardBanner {
  count: number;
  key: string;
  params?: Record<string, string | number>;
  title: string;
  body_key: string;
  body: string;
  action: { key: string; label: string; href: string } | null;
}

export interface DashboardActivity {
  id: number;
  action: string;
  action_label: string;
  actor_id: number | null;
  actor: string | null;
  voucher_id: number;
  voucher_number: string | null;
  amount_text: string | null;
  at: string | null;
}

export interface DashboardMoneyTotal { count: number; total: number; total_text: string }

export interface DashboardPayload {
  role: Role;
  greeting: string;
  data: {
    headline: string;
    sub: string;
    stats: DashboardStat[];
    recent?: Voucher[];
    queue?: Voucher[];
    volume?: { period: string; label: string; count: number; total: number; is_current: boolean }[];
    by_department?: { id: number; name: string; count: number; total: number; total_text?: string; share: string }[];
    by_stage?: { name: string; count: number; total: number; share: string }[];
    attention?: { id: number; name: string; status: string; plan: string | null; users_count: number; note: string }[];
    view?: DashboardView;
    banner?: DashboardBanner | null;
    queue_total_text?: string;
    recent_activity?: DashboardActivity[];
    recent_activity_key?: string;
    recent_activity_label?: string;
    recently_signed?: { id: number; number: string; payee: string; amount_text: string; status: string }[];
    departments?: { id: number; name: string; total: number; total_text: string }[];
    payment_totals?: { paid: DashboardMoneyTotal; bank: DashboardMoneyTotal; cash: DashboardMoneyTotal };
    overview?: { active_users: number; departments: number };
    workflow?: {
      id: number; name: string; name_sw?: string | null;
      steps: { position: number; name: string; name_sw?: string | null; role: string; action: "request" | "sign" | "approve" | "pay" | "review" }[];
    } | null;
    subscription?: { plan: string | null; status: string; trial_ends_at: string | null; renews_at: string | null; days_remaining: number | null } | null;
    recent_companies?: any[];
    recent_payments?: any[];
  };
  /** The work that is this user's to do right now. */
  queue?: Voucher[];
  queue_total?: number;
  queue_total_text?: string;
}

export interface Paginated<T> {
  data: T[];
  links?: unknown;
  meta?: {
    current_page: number;
    last_page: number;
    per_page: number;
    total: number;
    from: number | null;
    to: number | null;
    total_amount?: number;
    currency?: string;
    unread_count?: number;
    collected?: number;
    outstanding?: number;
  };
}

/* — two-step sign-in (POST /auth/login → /auth/login/send-code → /auth/login/verify) — */

export type LoginChannel = "email" | "sms";

export interface LoginChannelOption {
  channel: LoginChannel;
  /** Masked, e.g. "f•••@watercom.test" or "+255 7•• ••• 418". */
  destination: string;
}

/** What /auth/login returns instead of a token when a code is required. */
export interface LoginChallenge {
  requires_verification: true;
  /** Opaque; kept in memory only, never persisted. */
  challenge: string;
  channels: LoginChannelOption[];
  /** Set when there was only one channel and the code has already gone. */
  sent_to: LoginChannel | null;
  /** Challenge lifetime, seconds. */
  expires_in: number;
  code_expires_in: number | null;
  resend_in: number | null;
}

/** POST /auth/login/send-code */
export interface LoginCodeSent {
  sent_to: LoginChannel;
  destination: string;
  code_expires_in: number;
  resend_in: number;
  sends_remaining: number;
}

/** One voucher design from the server's catalogue. Presentation only. */
export interface VoucherTemplate {
  key: string;
  number: number;
  name: string;
  name_sw: string;
  description: string;
  description_sw: string;
  is_default: boolean;
}

export interface VoucherTemplateChange {
  id: number;
  previous_template: string | null;
  previous_template_name: string | null;
  new_template: string;
  new_template_name: string;
  changed_by: number | null;
  changed_by_name: string | null;
  changed_by_role: string | null;
  source: "registration" | "company_admin" | "super_admin" | "platform_create";
  reason: string | null;
  counted: boolean;
  created_at: string | null;
}

/** A company's design and what it may still do about it. */
export interface VoucherTemplateState {
  template: string;
  template_name: string;
  changes_used: number;
  changes_allowed: number;
  changes_remaining: number;
  templates: VoucherTemplate[];
  history: VoucherTemplateChange[];
}
