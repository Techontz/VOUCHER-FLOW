/**
 * Workflow logic for the prototype — the front-end mirror of what the Laravel
 * service layer will do in Phase 2.
 *
 * Nothing assumes an HOD-then-CEO shape. What a participant may do at a step
 * comes entirely from that step's stored capability flags, so one company can
 * run "HOD signs, CEO approves, Cashier pays" while another routes through
 * Finance or a single approver.
 */

import type { MockDataset, MockStep, MockUser, MockVoucher, MockWorkflow } from "./seed";

export type Locale = "en" | "sw";

export function workflowFor(db: MockDataset, voucher: MockVoucher): MockWorkflow | undefined {
  return db.workflows.find((w) => w.id === voucher.workflow_id)
    ?? db.workflows.find((w) => w.company_id === voucher.company_id && w.is_default);
}

/** Steps that apply to this voucher, after amount-threshold filtering. */
export function applicableSteps(db: MockDataset, voucher: MockVoucher): MockStep[] {
  const wf = workflowFor(db, voucher);
  if (!wf) return [];
  return wf.steps
    .filter((s) => s.position === 1 || (
      (s.min_amount === null || voucher.amount >= s.min_amount) &&
      (s.max_amount === null || voucher.amount <= s.max_amount)
    ))
    .sort((a, b) => a.position - b.position);
}

export const approvalSteps = (db: MockDataset, v: MockVoucher) =>
  applicableSteps(db, v).filter((s) => s.position !== 1);

export const stepAt = (db: MockDataset, v: MockVoucher, position: number | null) =>
  position ? applicableSteps(db, v).find((s) => s.position === position) : undefined;

export const nextStepAfter = (db: MockDataset, v: MockVoucher, position: number) =>
  approvalSteps(db, v).find((s) => s.position > position);

/** Who may act at a step, resolved against this voucher. */
export function assigneesFor(db: MockDataset, voucher: MockVoucher, step: MockStep): MockUser[] {
  if (step.assigned_user_id) {
    const named = db.users.find((u) => u.id === step.assigned_user_id);
    return named ? [named] : [];
  }

  const dept = db.departments.find((d) => d.id === voucher.department_id);

  if (step.role === "employee") {
    const requester = db.users.find((u) => u.id === voucher.requester_id);
    return requester ? [requester] : [];
  }
  if (step.role === "hod" && dept?.hod_user_id) {
    const hod = db.users.find((u) => u.id === dept.hod_user_id);
    if (hod) return [hod];
  }
  if (step.role === "ceo" && dept?.manager_user_id) {
    const ceo = db.users.find((u) => u.id === dept.manager_user_id);
    if (ceo) return [ceo];
  }
  if (step.role === "custom") return [];

  return db.users.filter(
    (u) => u.company_id === voucher.company_id && u.role === step.role && u.status === "active",
  );
}

export function canActOnStep(db: MockDataset, user: MockUser, voucher: MockVoucher, step: MockStep): boolean {
  if (user.company_id !== voucher.company_id) return false;
  // A company admin may act at any step of their own tenant as an override.
  if (user.role === "company_admin") return true;
  return assigneesFor(db, voucher, step).some((u) => u.id === user.id);
}

export interface Actions {
  view: boolean; edit: boolean; delete: boolean; submit: boolean;
  sign: boolean; submit_signed: boolean; approve: boolean; reject: boolean;
  request_changes: boolean; pay: boolean; cancel: boolean; comment: boolean;
  print: boolean; download: boolean;
}

/** The single source the list, the detail screen and the mobile app all read. */
export function availableActions(db: MockDataset, user: MockUser, voucher: MockVoucher): Actions {
  const a: Actions = {
    view: true, edit: false, delete: false, submit: false,
    sign: false, submit_signed: false, approve: false, reject: false,
    request_changes: false, pay: false, cancel: false, comment: true,
    print: false, download: false,
  };

  const isOwner = voucher.requester_id === user.id;
  const isAdmin = user.role === "company_admin" || user.role === "super_admin";
  const isTerminal = ["paid", "rejected", "cancelled"].includes(voucher.status);
  const step = voucher.status === "in_review" || voucher.status === "approved"
    ? stepAt(db, voucher, voucher.current_step_position)
    : undefined;

  // Printing follows the step's grant; the owner and admins keep it at every
  // stage, which is what "print at any stage" means.
  a.print = isOwner || isAdmin || isTerminal || (step?.can_print ?? false);
  a.download = isOwner || isAdmin || isTerminal || (step?.can_download ?? false);

  const editable = voucher.status === "draft" || voucher.status === "changes_requested";
  if ((isOwner || isAdmin) && editable) {
    a.edit = true;
    a.submit = true;
    a.delete = voucher.status === "draft";
  }
  if ((isOwner || isAdmin) && (voucher.status === "in_review" || voucher.status === "approved")) {
    a.cancel = true;
  }

  if (!step || !canActOnStep(db, user, voucher, step)) return a;

  const signed = voucher.step_signed_at !== null;

  if (step.can_sign && !signed) a.sign = true;
  // A signing-only step hands the voucher onward once signed; the decision
  // belongs to a later step, not this one.
  if (step.can_sign && !step.can_approve && signed) a.submit_signed = true;
  if (step.can_approve && voucher.status === "in_review") {
    if (!step.requires_signature || signed || !step.can_sign) a.approve = true;
  }
  if (step.can_reject && voucher.status === "in_review") a.reject = true;
  if (step.can_request_changes && voucher.status === "in_review") a.request_changes = true;
  if (step.can_pay && voucher.status === "approved") a.pay = true;

  return a;
}

export interface StatusView { key: string; label: string; label_sw: string; tag: string }

/** Human status text derived from the voucher's own workflow. */
export function presentStatus(db: MockDataset, v: MockVoucher): StatusView {
  const mk = (key: string, label: string, label_sw: string, tag: string) => ({ key, label, label_sw, tag });

  switch (v.status) {
    case "draft": return mk("draft", "Draft", "Rasimu", "tag-neutral");
    case "changes_requested": return mk("changes_requested", "Changes requested", "Mabadiliko yameombwa", "tag-accent-2");
    case "rejected": return mk("rejected", "Rejected", "Imekataliwa", "tag-accent-2");
    case "cancelled": return mk("cancelled", "Cancelled", "Imefutwa", "tag-neutral");
    case "paid": return mk("paid", "Paid & completed", "Imelipwa na kukamilika", "tag-accent");
    case "approved": return mk("awaiting_payment", "Approved — awaiting payment", "Imeidhinishwa — inasubiri malipo", "tag-info");
    default: break;
  }

  const step = stepAt(db, v, v.current_step_position);
  if (!step) return mk("in_review", "In review", "Inapitiwa", "tag-outline");

  const role = roleLabel(step.role);
  if (step.can_sign && !step.can_approve) {
    return v.step_signed_at
      ? mk("signed_pending_submit", "Signed — ready to submit", "Imesainiwa — tayari kutumwa", "tag-outline")
      : mk("awaiting_signature", `Awaiting ${role} signature`, `Inasubiri sahihi ya ${role}`, "tag-outline");
  }
  if (step.can_approve) {
    return mk("awaiting_approval", `Awaiting ${role} approval`, `Inasubiri idhini ya ${role}`, "tag-outline");
  }
  return mk("awaiting_review", `Awaiting ${step.name}`, `Inasubiri ${step.name}`, "tag-outline");
}

export function roleLabel(role: string): string {
  return ({
    employee: "Employee", hod: "HOD", ceo: "CEO", cashier: "Cashier",
    finance: "Finance", director: "Director", custom: "Custom approver",
    company_admin: "Company Administrator", super_admin: "Super Admin",
  } as Record<string, string>)[role] ?? role;
}

export function capabilityText(step: MockStep, locale: Locale = "en"): string {
  const en: [boolean, string][] = [
    [step.can_sign, "Sign"], [step.can_approve, "Approve"], [step.can_reject, "Reject"],
    [step.can_request_changes, "Request changes"], [step.can_pay, "Record payment"],
    [step.can_print, "Print / PDF"],
  ];
  const sw: [boolean, string][] = [
    [step.can_sign, "Saini"], [step.can_approve, "Idhinisha"], [step.can_reject, "Kataa"],
    [step.can_request_changes, "Omba mabadiliko"], [step.can_pay, "Rekodi malipo"],
    [step.can_print, "Chapisha / PDF"],
  ];
  const on = (locale === "sw" ? sw : en).filter(([flag]) => flag).map(([, label]) => label);
  return on.length ? on.join(" · ") : locale === "sw" ? "Kuona tu" : "View only";
}

export interface TimelineRow {
  position: number | null; name: string; name_sw: string | null;
  sub: string; sub_sw: string; person: string;
  act: string; act_sw: string; when: string | null; comment: string | null;
  signature: string | null; capabilities: Record<string, boolean>;
  capability_text: string; state: "done" | "current" | "pending" | "rejected"; icon: string;
}

/** Built from the configured workflow joined against what actually happened. */
export function buildTimeline(db: MockDataset, v: MockVoucher): TimelineRow[] {
  const steps = applicableSteps(db, v);
  const trail = db.approvals.filter((a) => a.voucher_id === v.id);
  const paid = v.status === "paid";
  const rejected = v.status === "rejected";
  const returned = v.status === "changes_requested";
  const current = v.current_step_position;

  const rows: TimelineRow[] = steps.map((step) => {
    const events = trail.filter((e) => e.step_position === step.position);
    const atThis = !paid && !rejected && current === step.position;
    const done = paid || (current !== null && step.position < current)
      || (rejected && events.some((e) => ["approved", "signed", "forwarded"].includes(e.action)));

    const rejectEvent = [...events].reverse().find((e) => e.action === "rejected");
    const changesEvent = [...events].reverse().find((e) => e.action === "changes_requested");
    const approveEvent = [...events].reverse().find((e) => e.action === "approved");
    const payEvent = [...events].reverse().find((e) => e.action === "paid");
    const signEvent = events.find((e) => e.action === "signed");
    const forwardEvent = [...events].reverse().find((e) => e.action === "forwarded");
    const last = events[events.length - 1];

    let act = "Not started", actSw = "Haijaanza";
    let when: string | null = null;
    let comment: string | null = null;

    if (step.position === 1) {
      if (v.status === "draft") { act = "Draft — not submitted"; actSw = "Rasimu — haijatumwa"; }
      else {
        act = "Created & submitted"; actSw = "Imetengenezwa na kutumwa";
        when = v.submitted_at;
        comment = v.attachments.length ? `${v.attachments.length} supporting document(s) attached.` : null;
      }
    } else if (rejectEvent) {
      act = "Rejected"; actSw = "Imekataliwa"; when = rejectEvent.acted_at; comment = rejectEvent.comment;
    } else if (changesEvent) {
      act = "Changes requested"; actSw = "Mabadiliko yameombwa"; when = changesEvent.acted_at; comment = changesEvent.comment;
    } else if (payEvent) {
      act = "Paid"; actSw = "Imelipwa"; when = payEvent.acted_at;
      comment = payEvent.comment ?? "Funds released and reference recorded against the voucher.";
    } else if (approveEvent) {
      act = "Approved"; actSw = "Imeidhinishwa"; when = approveEvent.acted_at;
      comment = approveEvent.comment ?? "Cleared for payment.";
    } else if (signEvent && forwardEvent) {
      act = "Reviewed & signed"; actSw = "Imepitiwa na kusainiwa"; when = signEvent.acted_at;
      comment = forwardEvent.comment ?? "Signature applied and forwarded to the next step.";
    } else if (signEvent && atThis) {
      act = "Signed — not yet submitted onward"; actSw = "Imesainiwa — haijatumwa mbele";
      when = signEvent.acted_at;
      comment = "Signature captured. This step signs only; it makes no approval decision.";
    } else if (atThis) {
      if (step.can_pay) { act = "Awaiting payment"; actSw = "Inasubiri malipo"; }
      else if (step.can_approve) { act = "Awaiting approval"; actSw = "Inasubiri idhini"; }
      else { act = "Awaiting signature"; actSw = "Inasubiri sahihi"; }
    } else if (done && last) {
      act = "Passed"; actSw = "Imepita"; when = last.acted_at; comment = last.comment;
    }

    const bad = !!rejectEvent || !!changesEvent;
    const good = done && !bad;
    const assignee = assigneesFor(db, v, step)[0];
    const actor = last ? db.users.find((u) => u.id === last.actor_id) : undefined;
    const person = last?.actor_name ?? assignee?.name ?? step.assignee_hint ?? roleLabel(step.role);
    const personTitle = actor?.job_title ?? assignee?.job_title ?? roleLabel(step.role);

    return {
      position: step.position, name: step.name, name_sw: step.name_sw,
      sub: `Step ${step.position} · ${roleLabel(step.role)}`,
      sub_sw: `Hatua ${step.position} · ${roleLabel(step.role)}`,
      person, person_title: personTitle, act, act_sw: actSw, when, comment,
      signature: signEvent?.signature ?? null,
      capabilities: {
        sign: step.can_sign, approve: step.can_approve, reject: step.can_reject,
        request_changes: step.can_request_changes, pay: step.can_pay,
        print: step.can_print, download: step.can_download,
      },
      capability_text: capabilityText(step),
      state: bad ? "rejected" : good ? "done" : atThis ? "current" : "pending",
      icon: bad ? "ph-x-circle" : good ? "ph-check-circle" : atThis ? "ph-hourglass-medium" : "ph-circle-dashed",
    };
  });

  rows.push({
    position: null, name: "Completed", name_sw: "Imekamilika",
    sub: "System", sub_sw: "Mfumo", person: "VouchFlow",
    act: paid ? "Voucher completed" : rejected ? "Closed as rejected" : returned ? "Returned to requester" : "Not completed",
    act_sw: paid ? "Vocha imekamilika" : rejected ? "Imefungwa kama iliyokataliwa" : returned ? "Imerudishwa kwa mwombaji" : "Haijakamilika",
    when: paid ? v.paid_at : rejected ? v.rejected_at : null,
    comment: paid && v.verification_code
      ? `Approval ID ${v.verification_code} · PDF generated with all captured marks.`
      : null,
    signature: null,
    capabilities: { print: true, download: true },
    capability_text: "Print · Download PDF · Share",
    state: paid ? "done" : rejected ? "rejected" : "pending",
    icon: paid ? "ph-seal-check" : rejected ? "ph-x-circle" : "ph-circle-dashed",
  });

  return rows;
}

/**
 * Row-level visibility. Tenant isolation is handled by the caller; this narrows
 * further, so an employee sees only their own vouchers and an approver only
 * what the workflow actually routes to them.
 */
export function visibleVouchers(db: MockDataset, user: MockUser): MockVoucher[] {
  const inTenant = db.vouchers.filter((v) => v.company_id === user.company_id);

  if (user.role === "super_admin") return db.vouchers;
  if (user.role === "company_admin") return inTenant;

  if (user.role === "employee") {
    return inTenant.filter((v) => v.requester_id === user.id);
  }

  const scopedDepartments = db.departments
    .filter((d) => d.hod_user_id === user.id || d.manager_user_id === user.id)
    .map((d) => d.id);

  return inTenant.filter((v) => {
    if (v.requester_id === user.id) return true;
    if (v.status === "draft") return false;

    // Anything they have already acted on stays visible.
    if (db.approvals.some((a) => a.voucher_id === v.id && a.actor_id === user.id)) return true;

    // Steps that name them personally.
    const wf = workflowFor(db, v);
    if (wf?.steps.some((s) => s.assigned_user_id === user.id)) return true;

    // The cashier sees everything that has reached, or passed, payment.
    if (user.role === "cashier") return ["approved", "paid"].includes(v.status);

    // Roles that are not department-bound act for the whole company.
    if (user.role === "finance" || user.role === "director" || user.role === "ceo") {
      return wf?.steps.some((s) => s.role === user.role && s.assigned_user_id === null) ?? false;
    }

    return scopedDepartments.includes(v.department_id ?? -1);
  });
}

/** The "awaiting me" queue: parked on a step this user may act on. */
export function pendingFor(db: MockDataset, user: MockUser): MockVoucher[] {
  return visibleVouchers(db, user).filter((v) => {
    if (v.status !== "in_review" && v.status !== "approved") return false;
    const step = stepAt(db, v, v.current_step_position);
    if (!step) return false;
    if (!canActOnStep(db, user, v, step)) return false;
    const actions = availableActions(db, user, v);
    return actions.sign || actions.submit_signed || actions.approve || actions.reject || actions.pay;
  });
}

/**
 * What this user must personally do next.
 *
 * A dashboard is a queue of work, not a record of it. A voucher belongs here
 * only while this user is the one holding it up; the moment they act, it moves
 * to whoever is next and leaves this list. History lives in Reports.
 */
export function actionQueueFor(db: MockDataset, user: MockUser): MockVoucher[] {
  if (user.role === "employee") {
    // The requester's own move: finish a draft, or answer a request for changes.
    return db.vouchers
      .filter((v) => v.company_id === user.company_id
        && v.requester_id === user.id
        && (v.status === "draft" || v.status === "changes_requested"))
      .sort((a, b) => b.voucher_date.localeCompare(a.voucher_date));
  }

  const queue = pendingFor(db, user);

  if (user.role === "company_admin") {
    // An administrator sits outside the route by default, so their queue is
    // what the route itself has failed to move: anything idle too long.
    return stalledVouchers(db, user);
  }

  // An approver may also have their own drafts waiting on them.
  const mine = db.vouchers.filter((v) => v.company_id === user.company_id
    && v.requester_id === user.id
    && (v.status === "draft" || v.status === "changes_requested"));

  return [...queue, ...mine.filter((m) => !queue.some((q) => q.id === m.id))];
}

/** How long a voucher has been sitting on its current step, in days. */
export function idleDays(db: MockDataset, voucher: MockVoucher): number {
  const events = db.approvals.filter((a) => a.voucher_id === voucher.id);
  const last = events[events.length - 1];
  const since = last?.acted_at ?? voucher.submitted_at ?? voucher.created_at;
  return Math.floor((Date.now() - new Date(since).getTime()) / 86_400_000);
}

/** Open vouchers that have not moved in a while — the administrator's queue. */
export function stalledVouchers(db: MockDataset, user: MockUser, thresholdDays = 3): MockVoucher[] {
  return visibleVouchers(db, user)
    .filter((v) => (v.status === "in_review" || v.status === "approved")
      && idleDays(db, v) >= thresholdDays)
    .sort((a, b) => idleDays(db, b) - idleDays(db, a));
}

/** Everything still moving through the route, for company-wide counters. */
export function inFlight(db: MockDataset, user: MockUser): MockVoucher[] {
  return visibleVouchers(db, user)
    .filter((v) => v.status === "in_review" || v.status === "approved");
}

/**
 * The departments a user may report on.
 *
 * An employee reports on nothing but their own work, a head on the departments
 * they run, and a company-wide role on all of them.
 */
export function reportableDepartments(db: MockDataset, user: MockUser): number[] | "all" | "own" {
  if (user.role === "employee") return "own";
  if (user.role === "super_admin" || user.role === "company_admin") return "all";
  if (user.role === "ceo" || user.role === "director" || user.role === "finance" || user.role === "cashier") return "all";

  const headed = db.departments
    .filter((d) => d.company_id === user.company_id
      && (d.hod_user_id === user.id || d.manager_user_id === user.id))
    .map((d) => d.id);

  return headed.length ? headed : (user.department_id ? [user.department_id] : []);
}
