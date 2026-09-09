/**
 * Turns internal mock records into the JSON shapes the UI consumes — the
 * front-end mirror of Laravel's API resources. Keeping these identical is what
 * lets Phase 2 swap the transport without touching a screen.
 */

import {
  applicableSteps, availableActions, buildTimeline, capabilityText,
  presentStatus, roleLabel, stepAt, workflowFor,
} from "./engine";
import type { MockDataset, MockStep, MockUser, MockVoucher, MockWorkflow } from "./seed";

export const money = (amount: number, currency = "TZS") =>
  `${currency} ${Math.round(amount).toLocaleString("en-US")}`;

export function compact(amount: number, currency = "TZS"): string {
  if (Math.abs(amount) >= 1e9) return `${currency} ${(amount / 1e9).toFixed(1)}B`;
  if (Math.abs(amount) >= 1e6) return `${currency} ${(amount / 1e6).toFixed(1)}M`;
  if (Math.abs(amount) >= 1e3) return `${currency} ${Math.round(amount / 1e3)}K`;
  return money(amount, currency);
}

const UNITS = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
  "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
const TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];

function underThousand(n: number): string {
  if (n < 20) return UNITS[n];
  if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? `-${UNITS[n % 10]}` : "");
  return `${UNITS[Math.floor(n / 100)]} hundred${n % 100 ? ` ${underThousand(n % 100)}` : ""}`;
}

export function amountInWords(amount: number, currency = "TZS"): string {
  const major = ({ TZS: "shillings", KES: "shillings", USD: "dollars", EUR: "euros" } as Record<string, string>)[currency] ?? "units";
  const whole = Math.floor(Math.abs(amount));
  if (!whole) return `Zero ${major} only`;

  const parts: string[] = [];
  let rest = whole;
  ([[1e9, "billion"], [1e6, "million"], [1e3, "thousand"]] as const).forEach(([value, label]) => {
    if (rest >= value) { parts.push(`${underThousand(Math.floor(rest / value))} ${label}`); rest %= value; }
  });
  if (rest > 0) parts.push(underThousand(rest));
  // Sentence case: only the first word is capitalised, as on a cheque.
  const text = parts.join(" ").toLowerCase();
  return `${text.charAt(0).toUpperCase()}${text.slice(1)} ${major} only`;
}

export const initials = (name: string) =>
  name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]?.toUpperCase() ?? "").join("");

export function userResource(db: MockDataset, u: MockUser) {
  const dept = db.departments.find((d) => d.id === u.department_id);
  return {
    id: u.id, company_id: u.company_id, name: u.name, initials: initials(u.name),
    email: u.email, phone: u.phone, role: u.role, role_label: roleLabel(u.role),
    employee_code: u.employee_code, job_title: u.job_title, status: u.status,
    locale: u.locale, theme: u.theme,
    department_id: u.department_id,
    department: dept ? { id: dept.id, name: dept.name } : null,
    avatar_url: null, has_signature: !!u.signature,
    signature_updated_at: u.signature ? u.last_login_at : null,
    two_factor_enabled: false, last_login_at: u.last_login_at,
    joined_at: u.joined_at, voucher_count: u.voucher_count,
  };
}

export function planResource(db: MockDataset, code: string | null) {
  const p = db.plans.find((x) => x.code === code);
  if (!p) return null;
  return {
    id: p.id, code: p.code, name: p.name, label: p.name, blurb: p.blurb,
    price: p.price, currency: p.currency, billing_cycle: p.billing_cycle,
    max_users: p.max_users, max_vouchers_per_month: p.max_vouchers_per_month,
    max_departments: p.max_departments, max_approval_levels: p.max_approval_levels,
    storage_mb: p.storage_mb, trial_days: p.trial_days, features: p.features,
    is_active: p.is_active, is_public: p.is_public, sort_order: p.sort_order,
  };
}

export function companyResource(db: MockDataset, companyId: number | null) {
  const c = db.companies.find((x) => x.id === companyId);
  if (!c) return null;

  const end = c.status === "trial" ? c.trial_ends_at : c.current_period_end;
  const daysRemaining = end
    ? Math.max(0, Math.ceil((new Date(end).getTime() - Date.now()) / 86_400_000))
    : null;

  return {
    id: c.id, name: c.name, slug: c.slug, legal_name: c.legal_name, email: c.email,
    phone: c.phone, address: c.address, website: c.website, country: "TZ",
    tin: c.tin,
    bank_name: c.bank_name, bank_account_name: c.bank_account_name,
    bank_account_number: c.bank_account_number, bank_branch: c.bank_branch,
    currency: c.currency, locale: c.locale, timezone: "Africa/Dar_es_Salaam",
    logo_url: c.logo_url, logo_mark_url: c.logo_mark_url,
    primary_color: c.primary_color, accent_color: "#22d3ee",
    theme: c.theme, voucher_footer_text: c.voucher_footer_text,
    status: c.status,
    is_usable: !["suspended", "cancelled"].includes(c.status) && (c.status !== "trial" || (daysRemaining ?? 1) > 0),
    is_expired: end ? new Date(end).getTime() < Date.now() : false,
    days_remaining: daysRemaining,
    trial_ends_at: c.trial_ends_at,
    current_period_start: c.current_period_start,
    current_period_end: c.current_period_end,
    auto_renew: c.auto_renew,
    plan: planResource(db, c.plan_code), plan_id: db.plans.find((p) => p.code === c.plan_code)?.id ?? null,
    settings: {},
    users_count: db.users.filter((u) => u.company_id === c.id).length,
    vouchers_count: db.vouchers.filter((v) => v.company_id === c.id).length,
    created_at: c.created_at,
  };
}

export function stepResource(step: MockStep, db: MockDataset) {
  const assigned = db.users.find((u) => u.id === step.assigned_user_id);
  return {
    id: step.id, position: step.position, name: step.name, name_sw: step.name_sw,
    label: step.name, role: step.role, role_label: roleLabel(step.role),
    assigned_user_id: step.assigned_user_id,
    assigned_user: assigned ? { id: assigned.id, name: assigned.name } : null,
    assignee_hint: step.assignee_hint,
    can_sign: step.can_sign, can_approve: step.can_approve, can_reject: step.can_reject,
    can_request_changes: step.can_request_changes, can_pay: step.can_pay,
    can_print: step.can_print, can_download: step.can_download,
    requires_signature: step.requires_signature,
    min_amount: step.min_amount, max_amount: step.max_amount,
    is_request_step: step.position === 1,
  };
}

export function workflowResource(db: MockDataset, wf: MockWorkflow) {
  return {
    id: wf.id, name: wf.name, description: wf.description,
    voucher_type_id: null, is_default: wf.is_default, is_active: wf.is_active,
    version: wf.version,
    route_summary: `${wf.steps.map((s) => roleLabel(s.role)).join(" → ")} → Completed`,
    steps: wf.steps.map((s) => stepResource(s, db)),
    updated_at: null,
  };
}

export function voucherResource(
  db: MockDataset, v: MockVoucher, viewer: MockUser | null, detailed = false,
) {
  const status = presentStatus(db, v);
  const type = db.voucherTypes.find((t) => t.id === v.voucher_type_id);
  const dept = db.departments.find((d) => d.id === v.department_id);
  const requester = db.users.find((u) => u.id === v.requester_id);
  const step = stepAt(db, v, v.current_step_position);
  const locale = viewer?.locale ?? "en";

  const base: Record<string, unknown> = {
    id: v.id, number: v.number, status: v.status, kind: v.kind,
    status_key: status.key,
    status_label: locale === "sw" ? status.label_sw : status.label,
    status_label_en: status.label, status_label_sw: status.label_sw,
    status_tag: status.tag,
    payee: v.payee, purpose: v.purpose, description: v.description,
    amount: v.amount, currency: v.currency,
    amount_text: money(v.amount, v.currency),
    amount_in_words: amountInWords(v.amount, v.currency),
    payment_method: v.payment_method, account_ref: v.account_ref,
    category: v.category, cost_centre: v.cost_centre,
    voucher_date: v.voucher_date, notes_to_approver: v.notes_to_approver,
    verification_code: v.verification_code,
    voucher_type_id: v.voucher_type_id,
    voucher_type: type ? { id: type.id, name: type.name, label: locale === "sw" ? type.name_sw : type.name } : null,
    department_id: v.department_id,
    department: dept ? { id: dept.id, name: dept.name } : null,
    requester_id: v.requester_id,
    requester: requester
      ? { id: requester.id, name: requester.name, initials: initials(requester.name), job_title: requester.job_title }
      : null,
    workflow_id: v.workflow_id,
    current_step_position: v.current_step_position,
    is_signed_at_current_step: v.step_signed_at !== null,
    is_editable: ["draft", "changes_requested"].includes(v.status),
    is_terminal: ["paid", "rejected", "cancelled"].includes(v.status),
    submitted_at: v.submitted_at, approved_at: v.approved_at, rejected_at: v.rejected_at,
    paid_at: v.paid_at, payment_reference: v.payment_reference, paid_by: v.paid_by,
    payee_bank: v.payee_bank, payee_account_name: v.payee_account_name,
    payee_account_number: v.payee_account_number, payee_bank_branch: v.payee_bank_branch,
    cheque_number: v.cheque_number, cash_float: v.cash_float, received_by: v.received_by,
    created_at: v.created_at, updated_at: v.created_at,
    attachments_count: v.attachments.length,
    comments_count: v.comments.length,
  };

  if (viewer) {
    base.actions = availableActions(db, viewer, v);
    base.current_step = step
      ? {
          id: step.id, position: step.position, name: step.name, role: step.role,
          capabilities: {
            sign: step.can_sign, approve: step.can_approve, reject: step.can_reject,
            request_changes: step.can_request_changes, pay: step.can_pay,
            print: step.can_print, download: step.can_download,
          },
        }
      : null;
  }

  if (detailed) {
    base.timeline = buildTimeline(db, v);
    base.attachments = v.attachments.map((a) => ({
      id: a.id, name: a.name, mime_type: a.mime, size_bytes: a.size_bytes,
      size: humanSize(a.size_bytes), is_image: a.mime.startsWith("image/"),
      icon: a.mime.startsWith("image/") ? "ph-image" : "ph-file-pdf",
      url: `#attachment-${a.id}`, uploaded_by: requester?.name ?? null,
      created_at: v.created_at,
    }));
    base.comments = v.comments.map((c) => {
      const author = db.users.find((u) => u.id === c.user_id);
      return {
        id: c.id, body: c.body,
        user: author
          ? {
              id: author.id, name: author.name, initials: initials(author.name),
              role_label: roleLabel(author.role),
              department: db.departments.find((d) => d.id === author.department_id)?.name ?? null,
            }
          : null,
        created_at: c.created_at,
      };
    });
    const wf = workflowFor(db, v);
    base.workflow = wf ? workflowResource(db, wf) : null;
    base.applicable_steps = applicableSteps(db, v).map((s) => ({
      ...stepResource(s, db), capability_text: capabilityText(s, locale),
    }));
  }

  return base;
}

export function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1_048_576).toFixed(1)} MB`;
}

export function notificationResource(n: MockDataset["notifications"][number], locale: "en" | "sw") {
  return {
    id: n.id, type: n.type, icon: n.icon || "ph-bell",
    title: locale === "sw" && n.title_sw ? n.title_sw : n.title,
    body: locale === "sw" && n.body_sw ? n.body_sw : n.body,
    entity_type: n.entity_type, entity_id: n.entity_id,
    action_url: n.entity_type === "Voucher" && n.entity_id ? `/vouchers/${n.entity_id}` : null,
    is_unread: n.read_at === null, read_at: n.read_at, created_at: n.created_at,
  };
}

export function invoiceResource(i: MockDataset["invoices"][number], db: MockDataset) {
  return {
    id: i.id, number: i.number, description: i.description,
    amount: i.amount, tax: 0, total: i.amount, currency: i.currency,
    amount_text: money(i.amount, i.currency),
    status: i.status,
    status_tag: i.status === "paid" ? "tag-accent" : i.status === "pending" ? "tag-outline" : "tag-accent-2",
    method: i.method,
    method_label: ({ mobile_money: "Mobile Money", card: "Card", bank_transfer: "Bank transfer", none: "—" } as Record<string, string>)[i.method],
    provider_ref: i.provider_ref, failure_reason: i.failure_reason,
    period_start: i.period_start, period_end: i.period_end,
    issued_at: i.issued_at, paid_at: i.paid_at,
    company: db.companies.find((c) => c.id === i.company_id)?.name ?? null,
    company_id: i.company_id, created_at: i.issued_at,
  };
}

export function auditResource(a: MockDataset["audit"][number], db: MockDataset) {
  return {
    id: a.id, action: a.action, description: a.description,
    change_summary: a.change_summary, entity_type: a.entity_type, entity_id: a.entity_id,
    actor: { id: null, name: a.actor_name, role: a.actor_role, initials: initials(a.actor_name) },
    company: db.companies.find((c) => c.id === a.company_id)?.name ?? null,
    company_id: a.company_id, ip: a.ip, user_agent: a.user_agent, created_at: a.created_at,
  };
}

export function paginate<T>(rows: T[], page: number, perPage: number) {
  const total = rows.length;
  const lastPage = Math.max(1, Math.ceil(total / perPage));
  const current = Math.min(Math.max(1, page), lastPage);
  const from = (current - 1) * perPage;
  return {
    data: rows.slice(from, from + perPage),
    meta: {
      current_page: current, last_page: lastPage, per_page: perPage, total,
      from: total ? from + 1 : null, to: Math.min(from + perPage, total) || null,
    },
  };
}
