/**
 * The mock API surface.
 *
 * Paths, verbs and response shapes match the Laravel routes one-for-one, so
 * Phase 2 replaces this module with real HTTP and no screen changes.
 */

import {
  applicableSteps, assigneesFor, availableActions, capabilityText, nextStepAfter,
  pendingFor, presentStatus, roleLabel, stepAt, visibleVouchers, workflowFor,
} from "./engine";
import {
  amountInWords, auditResource, companyResource, compact, initials, invoiceResource,
  money, notificationResource, paginate, planResource, userResource, voucherResource,
  workflowResource,
} from "./present";
import { DEFAULT_STEPS, WORKFLOW_PRESETS, SAMPLE_SIGNATURE, type MockStep, type MockUser, type MockVoucher } from "./seed";
import { store } from "./store";

export class MockError extends Error {
  constructor(
    public status: number,
    message: string,
    public errors: Record<string, string[]> = {},
    public code?: string,
  ) {
    super(message);
  }
}

type Query = Record<string, string>;
type Body = Record<string, any>;

const now = () => new Date().toISOString();

function requireUser(token: string | null): MockUser {
  const user = store.currentUser(token);
  if (!user) throw new MockError(401, "Unauthenticated.");
  return user;
}

function findVoucher(id: number, user: MockUser): MockVoucher {
  const db = store.db;
  const voucher = db.vouchers.find((v) => v.id === id);
  if (!voucher) throw new MockError(404, "Voucher not found.");
  if (user.role !== "super_admin" && voucher.company_id !== user.company_id) {
    throw new MockError(404, "Voucher not found.");
  }
  if (!visibleVouchers(db, user).some((v) => v.id === id)) {
    throw new MockError(403, "This voucher belongs to another part of the business.");
  }
  return voucher;
}

function recordAudit(action: string, description: string, user: MockUser, entity?: { type: string; id: number }, summary?: string) {
  store.mutate((db) => {
    db.audit.unshift({
      id: store.nextId("audit"), company_id: user.company_id,
      actor_name: user.name, actor_role: user.role,
      action, description, change_summary: summary ?? null,
      entity_type: entity?.type ?? null, entity_id: entity?.id ?? null,
      ip: "127.0.0.1", user_agent: "VouchFlow Web (prototype)",
      created_at: now(),
    });
  });
}

function notify(userIds: number[], payload: { type: string; icon: string; title: string; title_sw?: string; body?: string; body_sw?: string; voucherId?: number; companyId: number | null }) {
  store.mutate((db) => {
    userIds.forEach((uid) => {
      db.notifications.unshift({
        id: store.nextId("notification"), user_id: uid, company_id: payload.companyId,
        type: payload.type, icon: payload.icon,
        title: payload.title, title_sw: payload.title_sw ?? null,
        body: payload.body ?? null, body_sw: payload.body_sw ?? null,
        entity_type: payload.voucherId ? "Voucher" : null,
        entity_id: payload.voucherId ?? null,
        read_at: null, created_at: now(),
      });
    });
  });
}

/** Moves a voucher to the next applicable step, or closes it out. */
function advance(voucher: MockVoucher, fromPosition: number) {
  const db = store.db;
  const next = nextStepAfter(db, voucher, fromPosition);

  if (next) {
    voucher.current_step_position = next.position;
    voucher.step_signed_at = null;
    // A payment step is reached only once the voucher is approved.
    if (next.can_pay && !next.can_approve) voucher.status = "approved";
    else voucher.status = "in_review";

    const verb = next.can_pay ? "payment" : next.can_approve ? "approval" : "signature";
    notify(assigneesFor(db, voucher, next).map((u) => u.id), {
      type: "voucher.awaiting", icon: next.can_pay ? "ph-wallet" : next.can_approve ? "ph-seal-check" : "ph-signature",
      title: `${voucher.number} needs your ${verb}`,
      title_sw: `${voucher.number} inahitaji ${next.can_pay ? "malipo" : next.can_approve ? "idhini" : "sahihi"} yako`,
      body: `${db.users.find((u) => u.id === voucher.requester_id)?.name ?? ""} · ${money(voucher.amount, voucher.currency)} — ${voucher.purpose}`,
      voucherId: voucher.id, companyId: voucher.company_id,
    });
    return;
  }

  voucher.status = "paid";
  voucher.paid_at = voucher.paid_at ?? now();
  voucher.current_step_position = null;
  voucher.step_signed_at = null;
}

function logAction(voucher: MockVoucher, user: MockUser, action: string, step: MockStep | undefined, comment?: string | null, signature?: string | null) {
  store.mutate((db) => {
    db.approvals.push({
      id: store.nextId("approval"), voucher_id: voucher.id,
      step_position: step?.position ?? null, step_name: step?.name ?? null,
      step_role: step?.role ?? null, actor_id: user.id, actor_name: user.name,
      action: action as never, comment: comment ?? null,
      signature: signature ?? null, acted_at: now(),
    });
  });
}

/* ══════════════════════════════════════════════════════════════ handlers ══ */

export function handle(method: string, path: string, body: Body = {}, query: Query = {}, token: string | null = null): unknown {
  const db = store.db;
  const seg = path.replace(/^\/+/, "").split("/");
  const num = (v: string | undefined) => Number(v);
  const int = (v: string | undefined, fallback: number) => (v ? Number(v) : fallback);

  /* ---------------------------------------------------------- public ---- */

  if (method === "GET" && path === "/plans") {
    return { data: db.plans.filter((p) => p.is_public).map((p) => planResource(db, p.code)) };
  }

  if (method === "POST" && path === "/auth/login") {
    const identifier = String(body.email ?? "").trim().toLowerCase();
    const user = db.users.find((u) => u.email.toLowerCase() === identifier);
    if (!user || String(body.password ?? "") !== "Password123!") {
      throw new MockError(422, "These credentials do not match our records.", {
        email: ["These credentials do not match our records."],
      });
    }
    store.mutate((d) => {
      const row = d.users.find((u) => u.id === user.id)!;
      row.last_login_at = now();
    });
    const authToken = store.signIn(user.id);
    return { token: authToken, user: userResource(db, user), company: companyResource(db, user.company_id) };
  }

  if (method === "POST" && path === "/auth/register") {
    // The prototype signs the caller straight in as the demo administrator.
    const admin = db.users.find((u) => u.role === "company_admin")!;
    const authToken = store.signIn(admin.id);
    return {
      token: authToken, user: userResource(db, admin),
      company: companyResource(db, admin.company_id),
      requires_verification: true,
      otp: { identifier: String(body.email ?? admin.email), purpose: "registration", expires_in: 600, code: "418205" },
    };
  }

  if (method === "POST" && (path === "/auth/otp/send" || path === "/auth/forgot-password")) {
    return {
      message: "If that address matches an account, a code is on its way.",
      otp: { identifier: String(body.identifier ?? body.email ?? ""), purpose: body.purpose ?? "registration", expires_in: 600, code: "418205" },
    };
  }

  if (method === "POST" && path === "/auth/otp/verify") {
    if (String(body.code ?? "") !== "418205") {
      throw new MockError(422, "That code is not correct.", { code: ["That code is not correct."] });
    }
    return { verified: true, user: null, token: null };
  }

  if (method === "POST" && path === "/auth/reset-password") {
    if (String(body.code ?? "") !== "418205") {
      throw new MockError(422, "That reset code is not valid.", { code: ["That reset code is not valid."] });
    }
    return { message: "Password updated. Sign in with your new password." };
  }

  /* --------------------------------------------------- authenticated ---- */

  const user = requireUser(token);
  const locale = user.locale;
  const companyId = user.company_id;

  if (method === "GET" && path === "/auth/me") {
    return { user: userResource(db, user), company: companyResource(db, companyId) };
  }
  if (method === "POST" && (path === "/auth/logout" || path === "/auth/logout-all")) {
    store.signOut();
    return { message: "Signed out." };
  }
  if (method === "GET" && path === "/auth/sessions") {
    return { data: [{ id: 1, device: "This browser (prototype)", last_used_at: now(), created_at: now(), is_current: true }] };
  }
  if (method === "POST" && path === "/auth/change-password") {
    if (String(body.current_password ?? "") !== "Password123!") {
      throw new MockError(422, "That is not your current password.", { current_password: ["That is not your current password."] });
    }
    return { message: "Password updated." };
  }

  if ((method === "PUT" || method === "POST") && path === "/profile") {
    store.mutate((d) => {
      const row = d.users.find((u) => u.id === user.id)!;
      (["name", "phone", "job_title", "locale", "theme"] as const).forEach((k) => {
        if (body[k] !== undefined && body[k] !== null) (row as never as Body)[k] = body[k];
      });
    });
    return { data: userResource(store.db, store.db.users.find((u) => u.id === user.id)!) };
  }
  if (method === "GET" && path === "/profile/signature") return { signature: user.signature };
  if (method === "POST" && path === "/profile/signature") {
    store.mutate((d) => { d.users.find((u) => u.id === user.id)!.signature = String(body.signature ?? ""); });
    return { message: "Signature saved.", updated_at: now() };
  }
  if (method === "DELETE" && path === "/profile/signature") {
    store.mutate((d) => { d.users.find((u) => u.id === user.id)!.signature = null; });
    return { message: "Signature removed." };
  }

  /* -------------------------------------------------------- dashboard ---- */

  if (method === "GET" && path === "/dashboard") return dashboard(user);

  /* --------------------------------------------------------- vouchers ---- */

  if (method === "GET" && path === "/vouchers/pending") {
    return { data: pendingFor(db, user).map((v) => voucherResource(db, v, user)) };
  }

  if (method === "GET" && path === "/vouchers") {
    let rows = visibleVouchers(db, user);
    const scope = query.scope ?? "all";
    if (scope === "mine") rows = rows.filter((v) => v.requester_id === user.id);
    if (scope === "pending") rows = pendingFor(db, user);

    const status = query.status;
    if (status && status !== "all") {
      if (status === "pending") rows = rows.filter((v) => v.status === "in_review");
      else if (status === "drafts") rows = rows.filter((v) => v.status === "draft");
      else rows = rows.filter((v) => v.status === status);
    }
    if (query.kind) rows = rows.filter((v) => v.kind === query.kind);
    if (query.department_id) rows = rows.filter((v) => v.department_id === num(query.department_id));
    if (query.voucher_type_id) rows = rows.filter((v) => v.voucher_type_id === num(query.voucher_type_id));
    if (query.requester_id) rows = rows.filter((v) => v.requester_id === num(query.requester_id));
    if (query.from) rows = rows.filter((v) => v.voucher_date >= query.from);
    if (query.to) rows = rows.filter((v) => v.voucher_date <= query.to);
    if (query.min_amount) rows = rows.filter((v) => v.amount >= num(query.min_amount));
    if (query.max_amount) rows = rows.filter((v) => v.amount <= num(query.max_amount));

    const q = (query.q ?? "").trim().toLowerCase();
    if (q.length > 1) {
      rows = rows.filter((v) => {
        const requester = db.users.find((u) => u.id === v.requester_id)?.name ?? "";
        return `${v.number}${v.purpose}${v.payee}${requester}${v.amount}`.toLowerCase().includes(q);
      });
    }

    const dir = query.direction === "asc" ? 1 : -1;
    const key = query.sort ?? "date";
    rows = [...rows].sort((a, b) => {
      const va = key === "amount" ? a.amount : key === "number" ? a.number : key === "status" ? a.status : a.voucher_date;
      const vb = key === "amount" ? b.amount : key === "number" ? b.number : key === "status" ? b.status : b.voucher_date;
      return va < vb ? -dir : va > vb ? dir : 0;
    });

    const page = paginate(rows, int(query.page, 1), int(query.per_page, 20));
    return {
      data: page.data.map((v) => voucherResource(db, v, user)),
      meta: {
        ...page.meta,
        total_amount: rows.reduce((sum, v) => sum + v.amount, 0),
        currency: db.companies.find((c) => c.id === companyId)?.currency ?? "TZS",
      },
    };
  }

  if (seg[0] === "vouchers" && seg[1] && !Number.isNaN(num(seg[1]))) {
    const id = num(seg[1]);
    const action = seg[2];

    if (method === "GET" && !action) {
      return { data: voucherResource(db, findVoucher(id, user), user, true) };
    }

    if (method === "DELETE" && !action) {
      const voucher = findVoucher(id, user);
      if (!availableActions(db, user, voucher).delete) throw new MockError(403, "Only a draft may be deleted.");
      store.mutate((d) => { d.vouchers = d.vouchers.filter((v) => v.id !== id); });
      recordAudit("voucher.deleted", `Deleted draft voucher ${voucher.number}`, user, { type: "Voucher", id });
      return { message: `Draft ${voucher.number} deleted.` };
    }

    if (method === "PUT" && !action) {
      const voucher = findVoucher(id, user);
      if (!availableActions(db, user, voucher).edit) throw new MockError(403, "This voucher can no longer be edited.");
      store.mutate((d) => {
        const row = d.vouchers.find((v) => v.id === id)!;
        (["payee", "purpose", "description", "payment_method", "account_ref", "category", "voucher_date", "notes_to_approver", "kind"] as const)
          .forEach((k) => { if (body[k] !== undefined) (row as never as Body)[k] = body[k]; });
        if (body.amount !== undefined) row.amount = Number(body.amount) || 0;
        if (body.currency) row.currency = String(body.currency);
        if (body.department_id !== undefined) row.department_id = body.department_id ? Number(body.department_id) : null;
        if (body.voucher_type_id) row.voucher_type_id = Number(body.voucher_type_id);
      });
      recordAudit("voucher.updated", `Updated voucher ${voucher.number}`, user, { type: "Voucher", id });
      return { data: voucherResource(store.db, store.db.vouchers.find((v) => v.id === id)!, user, true) };
    }

    if (method === "POST" && action) {
      const voucher = findVoucher(id, user);
      const actions = availableActions(db, user, voucher);
      const step = stepAt(db, voucher, voucher.current_step_position);
      const comment = body.comment ? String(body.comment) : null;

      const mutateVoucher = (fn: (v: MockVoucher) => void) =>
        store.mutate((d) => { fn(d.vouchers.find((v) => v.id === id)!); });

      switch (action) {
        case "submit": {
          if (!actions.submit) throw new MockError(422, "This voucher has already been submitted.");
          const first = approvalStepsFor(voucher)[0];
          const resubmit = voucher.status === "changes_requested";
          logAction(voucher, user, resubmit ? "resubmitted" : "submitted", applicableSteps(db, voucher)[0], comment);
          mutateVoucher((v) => {
            v.submitted_at = v.submitted_at ?? now();
            if (!first) { v.status = "paid"; v.current_step_position = null; }
            else { v.status = "in_review"; v.current_step_position = first.position; v.step_signed_at = null; }
          });
          if (first) {
            const fresh = store.db.vouchers.find((v) => v.id === id)!;
            notify(assigneesFor(store.db, fresh, first).map((u) => u.id), {
              type: "voucher.awaiting", icon: first.can_approve ? "ph-seal-check" : "ph-signature",
              title: `${voucher.number} needs your ${first.can_approve ? "approval" : "signature"}`,
              title_sw: `${voucher.number} inahitaji ${first.can_approve ? "idhini" : "sahihi"} yako`,
              body: `${user.name} · ${money(voucher.amount, voucher.currency)} — ${voucher.purpose}`,
              voucherId: id, companyId: voucher.company_id,
            });
          }
          recordAudit("voucher.submitted", `Submitted voucher ${voucher.number}`, user, { type: "Voucher", id }, "Draft → In review");
          break;
        }

        case "sign": {
          if (!actions.sign) throw new MockError(422, "That action is not available at this step.");
          const signature = body.use_saved_signature ? user.signature : (body.signature ?? user.signature);
          if (!signature) throw new MockError(422, "A signature is required.");
          if (body.save_signature && body.signature) {
            store.mutate((d) => { d.users.find((u) => u.id === user.id)!.signature = String(body.signature); });
          }
          logAction(voucher, user, "signed", step, comment, String(signature));
          mutateVoucher((v) => { v.step_signed_at = now(); });
          notify([voucher.requester_id], {
            type: "voucher.signed", icon: "ph-signature",
            title: `${voucher.number} signed by ${user.name}`,
            title_sw: `${voucher.number} imesainiwa na ${user.name}`,
            body: `${step?.name ?? "This step"} complete — the voucher continues along the approval route.`,
            voucherId: id, companyId: voucher.company_id,
          });
          recordAudit("voucher.signed", `Signed voucher ${voucher.number}`, user, { type: "Voucher", id });
          break;
        }

        case "submit-signed": {
          if (!actions.submit_signed) throw new MockError(422, "Sign the voucher before submitting it onward.");
          logAction(voucher, user, "forwarded", step, comment);
          mutateVoucher((v) => advance(v, step!.position));
          recordAudit("voucher.forwarded", `Submitted signed voucher ${voucher.number} onward`, user, { type: "Voucher", id });
          break;
        }

        case "approve": {
          if (!actions.approve) throw new MockError(422, "This step may not approve — it signs only.");
          if (step?.can_sign && !voucher.step_signed_at) {
            const signature = body.signature ?? user.signature;
            if (signature) {
              logAction(voucher, user, "signed", step, null, String(signature));
              mutateVoucher((v) => { v.step_signed_at = now(); });
            }
          }
          logAction(voucher, user, "approved", step, comment);
          mutateVoucher((v) => { v.approved_at = now(); advance(v, step!.position); });
          notify([voucher.requester_id], {
            type: "voucher.approved", icon: "ph-seal-check",
            title: `${voucher.number} approved`,
            title_sw: `${voucher.number} imeidhinishwa`,
            body: "Cleared for payment — the cashier will release the funds.",
            voucherId: id, companyId: voucher.company_id,
          });
          recordAudit("voucher.approved", `Approved voucher ${voucher.number}`, user, { type: "Voucher", id }, "In review → Approved");
          break;
        }

        case "reject": {
          if (!actions.reject) throw new MockError(422, "This step may not reject.");
          if (!comment || comment.trim().length < 3) {
            throw new MockError(422, "A reason is required.", { comment: ["A reason is required."] });
          }
          logAction(voucher, user, "rejected", step, comment);
          mutateVoucher((v) => { v.status = "rejected"; v.rejected_at = now(); v.current_step_position = null; v.step_signed_at = null; });
          notify([voucher.requester_id], {
            type: "voucher.rejected", icon: "ph-x-circle",
            title: `${voucher.number} was rejected`, title_sw: `${voucher.number} imekataliwa`,
            body: `${user.name}: ${comment}`, voucherId: id, companyId: voucher.company_id,
          });
          recordAudit("voucher.rejected", `Rejected voucher ${voucher.number}`, user, { type: "Voucher", id }, "In review → Rejected");
          break;
        }

        case "request-changes": {
          if (!actions.request_changes) throw new MockError(422, "This step may not request changes.");
          if (!comment || comment.trim().length < 3) {
            throw new MockError(422, "Say what needs to change.", { comment: ["Say what needs to change."] });
          }
          logAction(voucher, user, "changes_requested", step, comment);
          mutateVoucher((v) => { v.status = "changes_requested"; v.current_step_position = null; v.step_signed_at = null; });
          notify([voucher.requester_id], {
            type: "voucher.changes_requested", icon: "ph-arrow-u-up-left",
            title: `${voucher.number} needs changes`, title_sw: `${voucher.number} inahitaji mabadiliko`,
            body: `${user.name}: ${comment}`, voucherId: id, companyId: voucher.company_id,
          });
          recordAudit("voucher.changes_requested", `Requested changes on ${voucher.number}`, user, { type: "Voucher", id });
          break;
        }

        case "pay": {
          if (!actions.pay) throw new MockError(422, "This voucher is not cleared for payment.");
          const reference = String(body.reference ?? "").trim();
          if (!reference) {
            throw new MockError(422, "A payment reference is required.", { reference: ["A payment reference is required."] });
          }
          logAction(voucher, user, "paid", step, comment ?? "Funds released and reference recorded against the voucher.");
          mutateVoucher((v) => {
            v.status = "paid"; v.paid_at = now(); v.payment_reference = reference;
            v.paid_by = user.name; v.current_step_position = null; v.step_signed_at = null;
            if (body.method) v.payment_method = String(body.method);
          });
          notify([voucher.requester_id], {
            type: "voucher.paid", icon: "ph-check-circle",
            title: `${voucher.number} has been paid`, title_sw: `${voucher.number} imelipwa`,
            body: `${user.name} released ${money(voucher.amount, voucher.currency)} · reference ${reference}.`,
            voucherId: id, companyId: voucher.company_id,
          });
          recordAudit("voucher.paid", `Recorded payment for ${voucher.number}`, user, { type: "Voucher", id }, "Approved → Paid");
          break;
        }

        case "cancel": {
          if (!actions.cancel) throw new MockError(422, "This voucher is already closed.");
          logAction(voucher, user, "cancelled", step, comment);
          mutateVoucher((v) => { v.status = "cancelled"; v.current_step_position = null; });
          recordAudit("voucher.cancelled", `Cancelled voucher ${voucher.number}`, user, { type: "Voucher", id });
          break;
        }

        case "comments": {
          const text = String(body.body ?? "").trim();
          if (!text) throw new MockError(422, "Write something first.", { body: ["Write something first."] });
          store.mutate((d) => {
            d.vouchers.find((v) => v.id === id)!.comments.push({
              id: store.nextId("comment"), user_id: user.id, body: text, created_at: now(),
            });
          });
          const fresh = store.db.vouchers.find((v) => v.id === id)!;
          const added = fresh.comments[fresh.comments.length - 1];
          return {
            data: {
              id: added.id, body: added.body,
              user: { id: user.id, name: user.name, initials: initials(user.name), role_label: roleLabel(user.role), department: null },
              created_at: added.created_at,
            },
          };
        }

        default:
          throw new MockError(404, `Unknown action "${action}".`);
      }

      return { data: voucherResource(store.db, store.db.vouchers.find((v) => v.id === id)!, user, true) };
    }
  }

  if (method === "POST" && path === "/vouchers") {
    const type = db.voucherTypes.find((t) => t.id === Number(body.voucher_type_id))
      ?? db.voucherTypes.find((t) => t.company_id === companyId)!;
    const wf = db.workflows.find((w) => w.company_id === companyId && w.is_default)!;
    const id = store.nextId("voucher");
    const amount = Number(body.amount) || 0;

    const created: MockVoucher = {
      id, company_id: companyId!, number: nextNumber(type.id),
      kind: (body.kind === "cash" ? "cash" : "bank"),
      voucher_type_id: type.id, workflow_id: wf.id,
      department_id: body.department_id ? Number(body.department_id) : user.department_id,
      requester_id: user.id,
      payee: String(body.payee ?? ""), purpose: String(body.purpose ?? ""),
      description: body.description ? String(body.description) : null,
      amount, currency: String(body.currency ?? "TZS"),
      payment_method: body.payment_method ? String(body.payment_method) : null,
      account_ref: body.account_ref ? String(body.account_ref) : null,
      category: body.category ? String(body.category) : null,
      cost_centre: db.departments.find((d) => d.id === Number(body.department_id))?.cost_centre ?? null,
      voucher_date: String(body.voucher_date ?? now().slice(0, 10)),
      status: "draft", current_step_position: null, step_signed_at: null,
      verification_code: `VF-${Math.random().toString(36).slice(2, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`,
      notes_to_approver: body.notes_to_approver ? String(body.notes_to_approver) : null,
      submitted_at: null, approved_at: null, rejected_at: null,
      paid_at: null, payment_reference: null, paid_by: null,
      created_at: now(), attachments: [], comments: [],
    };

    store.mutate((d) => { d.vouchers.unshift(created); });
    logAction(created, user, "created", undefined);
    recordAudit("voucher.created", `Created voucher ${created.number}`, user, { type: "Voucher", id });

    if (body.submit) handle("POST", `/vouchers/${id}/submit`, {}, {}, token);
    return { data: voucherResource(store.db, store.db.vouchers.find((v) => v.id === id)!, user, true) };
  }

  /* ---------------------------------------------- company & reference ---- */

  if (method === "GET" && path === "/company") {
    return { data: companyResource(db, companyId), usage: usage(companyId) };
  }
  if ((method === "PUT" || method === "POST") && (path === "/company" || path === "/company/branding")) {
    store.mutate((d) => {
      const c = d.companies.find((x) => x.id === companyId)!;
      (["name", "email", "phone", "address", "currency", "locale", "primary_color", "voucher_footer_text"] as const)
        .forEach((k) => { if (body[k] !== undefined && body[k] !== null && body[k] !== "") (c as never as Body)[k] = body[k]; });
    });
    return { data: companyResource(store.db, companyId) };
  }
  if (method === "GET" && path === "/company/usage") return { data: usage(companyId) };

  if (method === "GET" && path === "/departments") {
    const quarterStart = new Date(); quarterStart.setMonth(Math.floor(quarterStart.getMonth() / 3) * 3, 1);
    return {
      data: db.departments.filter((d) => d.company_id === companyId).map((d) => ({
        id: d.id, name: d.name, code: d.code, cost_centre: d.cost_centre, is_active: true,
        hod_user_id: d.hod_user_id, manager_user_id: d.manager_user_id,
        hod: d.hod_user_id ? { id: d.hod_user_id, name: db.users.find((u) => u.id === d.hod_user_id)?.name ?? "" } : null,
        manager: d.manager_user_id ? { id: d.manager_user_id, name: db.users.find((u) => u.id === d.manager_user_id)?.name ?? "" } : null,
        users_count: db.users.filter((u) => u.department_id === d.id).length,
        vouchers_count: db.vouchers.filter((v) => v.department_id === d.id).length,
        spend: db.vouchers
          .filter((v) => v.department_id === d.id && v.status === "paid" && new Date(v.voucher_date) >= quarterStart)
          .reduce((s, v) => s + v.amount, 0),
        created_at: null,
      })),
    };
  }

  if (method === "POST" && path === "/departments") {
    const id = store.nextId("department");
    store.mutate((d) => {
      d.departments.push({
        id, company_id: companyId!, name: String(body.name), code: String(body.code ?? ""),
        cost_centre: String(body.cost_centre ?? ""),
        hod_user_id: body.hod_user_id ? Number(body.hod_user_id) : null,
        manager_user_id: body.manager_user_id ? Number(body.manager_user_id) : null,
      });
    });
    recordAudit("department.created", `Created department ${body.name}`, user, { type: "Department", id });
    return { data: { id, name: body.name } };
  }
  if (seg[0] === "departments" && seg[1] && method === "PUT") {
    const id = num(seg[1]);
    store.mutate((d) => {
      const row = d.departments.find((x) => x.id === id);
      if (!row) throw new MockError(404, "Department not found.");
      (["name", "code", "cost_centre"] as const).forEach((k) => { if (body[k] !== undefined) (row as never as Body)[k] = body[k]; });
      row.hod_user_id = body.hod_user_id ? Number(body.hod_user_id) : null;
      row.manager_user_id = body.manager_user_id ? Number(body.manager_user_id) : null;
    });
    return { data: { id } };
  }
  if (seg[0] === "departments" && seg[1] && method === "DELETE") {
    const id = num(seg[1]);
    if (db.vouchers.some((v) => v.department_id === id)) {
      throw new MockError(422, "This department has vouchers on record. Deactivate it instead.");
    }
    store.mutate((d) => { d.departments = d.departments.filter((x) => x.id !== id); });
    return { message: "Department deleted." };
  }

  if (method === "GET" && path === "/voucher-types") {
    return {
      data: db.voucherTypes.filter((t) => t.company_id === companyId).map((t) => ({
        id: t.id, name: t.name, name_sw: t.name_sw, label: locale === "sw" ? t.name_sw : t.name,
        code: t.code, prefix: t.prefix, number_format: "{prefix}-{year}-{seq}",
        seq_padding: t.seq_padding, next_number: t.next_number, reset_yearly: true,
        is_active: t.is_active, sort_order: t.sort_order,
        next_number_preview: previewNumber(t.id),
        vouchers_count: db.vouchers.filter((v) => v.voucher_type_id === t.id).length,
      })),
    };
  }

  if (method === "GET" && path === "/directory") {
    return {
      data: db.users.filter((u) => u.company_id === companyId && u.status === "active").map((u) => ({
        id: u.id, name: u.name, email: u.email, role: u.role,
        job_title: u.job_title, department_id: u.department_id,
      })),
    };
  }

  if (method === "GET" && path === "/employees") {
    let rows = db.users.filter((u) => u.company_id === companyId);
    if (query.role) rows = rows.filter((u) => u.role === query.role);
    if (query.status) rows = rows.filter((u) => u.status === query.status);
    if (query.department_id) rows = rows.filter((u) => u.department_id === num(query.department_id));
    const q = (query.q ?? "").toLowerCase();
    if (q) rows = rows.filter((u) => `${u.name}${u.email}${u.employee_code ?? ""}`.toLowerCase().includes(q));
    const page = paginate(rows, int(query.page, 1), int(query.per_page, 25));
    return { data: page.data.map((u) => userResource(db, u)), meta: page.meta };
  }

  if (method === "POST" && path === "/employees") {
    const id = store.nextId("user");
    store.mutate((d) => {
      d.users.push({
        id, company_id: companyId, name: String(body.name), email: String(body.email),
        role: body.role, job_title: String(body.job_title ?? ""), employee_code: body.employee_code ?? null,
        department_id: body.department_id ? Number(body.department_id) : null,
        phone: body.phone ?? null, status: "invited", locale: "en", theme: "dark",
        signature: null, last_login_at: null, joined_at: now(), voucher_count: 0,
      });
    });
    recordAudit("user.created", `Added ${body.name} as ${roleLabel(String(body.role))}`, user, { type: "User", id });
    return { data: userResource(store.db, store.db.users.find((u) => u.id === id)!), temporary_password: "Password123!" };
  }

  if (seg[0] === "employees" && seg[1] && method === "PUT") {
    const id = num(seg[1]);
    store.mutate((d) => {
      const row = d.users.find((u) => u.id === id);
      if (!row || row.company_id !== companyId) throw new MockError(404, "User not found.");
      (["name", "email", "phone", "employee_code", "job_title", "role", "status"] as const)
        .forEach((k) => { if (body[k] !== undefined) (row as never as Body)[k] = body[k]; });
      if (body.department_id !== undefined) row.department_id = body.department_id ? Number(body.department_id) : null;
    });
    return { data: userResource(store.db, store.db.users.find((u) => u.id === id)!) };
  }
  if (seg[0] === "employees" && seg[1] && method === "DELETE") {
    const id = num(seg[1]);
    if (id === user.id) throw new MockError(422, "You cannot remove your own account.");
    store.mutate((d) => { d.users = d.users.filter((u) => u.id !== id); });
    return { message: "Removed." };
  }
  if (seg[0] === "employees" && seg[2] === "resend-invitation") {
    return { message: "Invitation reissued.", temporary_password: "Password123!" };
  }

  /* -------------------------------------------------------- workflows ---- */

  if (method === "GET" && path === "/workflows/presets") {
    return {
      data: Object.entries(WORKFLOW_PRESETS).map(([key, preset]) => ({
        key, name: preset.name, description: preset.description, steps: preset.steps().length,
      })),
    };
  }
  if (method === "POST" && path === "/workflows/apply-preset") {
    const preset = WORKFLOW_PRESETS[String(body.preset)] ?? WORKFLOW_PRESETS.default;
    store.mutate((d) => {
      const wf = d.workflows.find((w) => w.company_id === companyId && w.is_default)!;
      wf.name = preset.name; wf.description = preset.description;
      wf.steps = preset.steps(); wf.version += 1;
    });
    recordAudit("workflow.preset_applied", `Applied the "${preset.name}" workflow preset`, user);
    return { data: workflowResource(store.db, store.db.workflows.find((w) => w.company_id === companyId && w.is_default)!) };
  }
  if (method === "GET" && path === "/workflows") {
    return { data: db.workflows.filter((w) => w.company_id === companyId).map((w) => workflowResource(db, w)) };
  }
  if (seg[0] === "workflows" && seg[1] && method === "PUT") {
    const id = num(seg[1]);
    store.mutate((d) => {
      const wf = d.workflows.find((w) => w.id === id);
      if (!wf) throw new MockError(404, "Workflow not found.");
      wf.name = String(body.name ?? wf.name);
      wf.description = String(body.description ?? wf.description);
      wf.version += 1;
      wf.steps = (body.steps as Body[]).map((s, i) => ({
        id: s.id ?? store.nextId("step"), position: i + 1,
        name: String(s.name), name_sw: s.name_sw ?? null, role: s.role,
        assigned_user_id: s.assigned_user_id ? Number(s.assigned_user_id) : null,
        assignee_hint: String(s.assignee_hint ?? ""),
        can_sign: !!s.can_sign, can_approve: !!s.can_approve, can_reject: !!s.can_reject,
        can_request_changes: !!s.can_request_changes, can_pay: !!s.can_pay,
        can_print: s.can_print !== false, can_download: s.can_download !== false,
        requires_signature: !!s.can_sign,
        min_amount: s.min_amount != null && s.min_amount !== "" ? Number(s.min_amount) : null,
        max_amount: s.max_amount != null && s.max_amount !== "" ? Number(s.max_amount) : null,
      }));
    });
    recordAudit("workflow.updated", "Changed the approval workflow", user, { type: "Workflow", id });
    return { data: workflowResource(store.db, store.db.workflows.find((w) => w.id === id)!) };
  }

  /* ----------------------------------------------------- notifications ---- */

  if (method === "GET" && path === "/notifications") {
    const rows = db.notifications.filter((n) => n.user_id === user.id);
    const page = paginate(rows, int(query.page, 1), int(query.per_page, 30));
    return {
      data: page.data.map((n) => notificationResource(n, locale)),
      meta: { ...page.meta, unread_count: rows.filter((n) => n.read_at === null).length },
    };
  }
  if (method === "GET" && path === "/notifications/unread-count") {
    return { unread_count: db.notifications.filter((n) => n.user_id === user.id && n.read_at === null).length };
  }
  if (method === "POST" && path === "/notifications/read-all") {
    let count = 0;
    store.mutate((d) => {
      d.notifications.forEach((n) => { if (n.user_id === user.id && !n.read_at) { n.read_at = now(); count++; } });
    });
    return { message: `${count} notifications marked as read.`, count };
  }
  if (seg[0] === "notifications" && seg[2] === "read") {
    store.mutate((d) => {
      const n = d.notifications.find((x) => x.id === num(seg[1]));
      if (n) n.read_at = now();
    });
    return { data: { id: num(seg[1]) } };
  }
  if (seg[0] === "notifications" && seg[1] && method === "DELETE") {
    store.mutate((d) => { d.notifications = d.notifications.filter((n) => n.id !== num(seg[1])); });
    return { message: "Notification removed." };
  }

  /* ---------------------------------------------------------- reports ---- */

  if (method === "GET" && path === "/reports") return { data: reportKinds() };
  if (seg[0] === "reports" && seg[1] && !seg[2]) return report(seg[1], user, query);
  if (seg[0] === "reports" && seg[2] === "export") {
    throw new MockError(422, "Exports arrive with the backend in Phase 2. The on-screen report is live.");
  }

  /* ---------------------------------------------------------- billing ---- */

  if (method === "GET" && path === "/billing/subscription") {
    const company = db.companies.find((c) => c.id === companyId)!;
    const plan = planResource(db, company.plan_code);
    return {
      subscription: {
        id: 1, status: company.status === "trial" ? "trialing" : "active",
        billing_cycle: "monthly", amount: plan?.price ?? 0, currency: company.currency,
        seats: plan?.max_users ?? null, starts_at: company.current_period_start,
        trial_ends_at: company.trial_ends_at,
        current_period_start: company.current_period_start,
        current_period_end: company.current_period_end,
        cancel_at_period_end: false, is_expired: false, plan,
        company_id: company.id, company: company.name,
      },
      plan, usage: usage(companyId),
      company_status: company.status,
      is_expired: companyResource(db, companyId)!.is_expired,
      days_remaining: companyResource(db, companyId)!.days_remaining,
      auto_renew: company.auto_renew,
      available_plans: db.plans.map((p) => planResource(db, p.code)),
    };
  }
  if (method === "GET" && path === "/billing/invoices") {
    const rows = db.invoices.filter((i) => i.company_id === companyId);
    const page = paginate(rows, int(query.page, 1), int(query.per_page, 20));
    return { data: page.data.map((i) => invoiceResource(i, db)), meta: page.meta };
  }
  if (method === "POST" && path === "/billing/subscribe") {
    const plan = db.plans.find((p) => p.id === Number(body.plan_id));
    if (!plan) throw new MockError(422, "Unknown plan.");
    store.mutate((d) => { d.companies.find((c) => c.id === companyId)!.plan_code = plan.code; });
    const id = db.invoices.length + 1;
    store.mutate((d) => {
      d.invoices.unshift({
        id, company_id: companyId!, number: `INV-2026-${String(500 + id).padStart(4, "0")}`,
        description: `${plan.name} · monthly`, amount: plan.price, currency: "TZS",
        status: "pending", method: "none", provider_ref: null, failure_reason: null,
        period_start: now().slice(0, 10), period_end: now().slice(0, 10),
        issued_at: now(), paid_at: null,
      });
    });
    return {
      message: `Subscribed to the ${plan.name} plan.`,
      subscription: { id: 1, plan: planResource(db, plan.code) },
      invoice: invoiceResource(store.db.invoices.find((i) => i.id === id)!, store.db),
    };
  }
  if (seg[0] === "billing" && seg[1] === "invoices" && seg[3] === "pay") {
    const id = num(seg[2]);
    const reference = String(body.reference ?? "");
    if (body.method !== "bank_transfer" && !reference) {
      throw new MockError(422, "A payment reference is required.", { reference: ["A payment reference is required."] });
    }
    if (reference.replace(/\D/g, "").endsWith("0000")) {
      store.mutate((d) => {
        const inv = d.invoices.find((i) => i.id === id)!;
        inv.status = "failed"; inv.failure_reason = "The payment was declined by the provider. No money left the account.";
        inv.method = body.method;
      });
      throw new MockError(422, "The payment was declined by the provider. No money left the account.");
    }
    store.mutate((d) => {
      const inv = d.invoices.find((i) => i.id === id)!;
      inv.status = "paid"; inv.method = body.method; inv.paid_at = now();
      inv.provider_ref = `DEMO-${Date.now().toString().slice(-10)}`; inv.failure_reason = null;
    });
    return { message: "Payment successful.", invoice: invoiceResource(store.db.invoices.find((i) => i.id === id)!, store.db) };
  }
  if (method === "POST" && path === "/billing/auto-renew") {
    store.mutate((d) => { d.companies.find((c) => c.id === companyId)!.auto_renew = !!body.auto_renew; });
    return { auto_renew: !!body.auto_renew };
  }

  /* -------------------------------------------------------- audit log ---- */

  if (method === "GET" && path === "/audit-logs/actions") {
    return { data: Array.from(new Set(db.audit.map((a) => a.action))).sort() };
  }
  if (method === "GET" && path === "/audit-logs") {
    let rows = user.role === "super_admin" ? db.audit : db.audit.filter((a) => a.company_id === companyId);
    if (query.action) rows = rows.filter((a) => a.action.startsWith(query.action));
    const q = (query.q ?? "").toLowerCase();
    if (q) rows = rows.filter((a) => `${a.description}${a.actor_name}`.toLowerCase().includes(q));
    const page = paginate(rows, int(query.page, 1), int(query.per_page, 30));
    return { data: page.data.map((a) => auditResource(a, db)), meta: page.meta };
  }

  /* --------------------------------------------------------- platform ---- */

  if (seg[0] === "platform") {
    if (user.role !== "super_admin") throw new MockError(403, "This area is restricted to platform administrators.");

    if (method === "GET" && seg[1] === "companies" && !seg[2]) {
      let rows = db.companies;
      if (query.status) rows = rows.filter((c) => c.status === query.status);
      const q = (query.q ?? "").toLowerCase();
      if (q) rows = rows.filter((c) => `${c.name}${c.email}`.toLowerCase().includes(q));
      const page = paginate(rows, int(query.page, 1), int(query.per_page, 25));
      return { data: page.data.map((c) => companyResource(db, c.id)), meta: page.meta };
    }
    if (method === "GET" && seg[1] === "companies" && seg[2]) {
      const id = num(seg[2]);
      const vouchers = db.vouchers.filter((v) => v.company_id === id);
      return {
        ...companyResource(db, id)!,
        data: companyResource(db, id),
        usage: usage(id),
        subscription: null,
        invoices: db.invoices.filter((i) => i.company_id === id).map((i) => invoiceResource(i, db)),
        admins: db.users.filter((u) => u.company_id === id && u.role === "company_admin").map((u) => userResource(db, u)),
        vouchers: {
          total: vouchers.length,
          pending: vouchers.filter((v) => v.status === "in_review").length,
          approved: vouchers.filter((v) => ["approved", "paid"].includes(v.status)).length,
          rejected: vouchers.filter((v) => v.status === "rejected").length,
          value: vouchers.filter((v) => v.status === "paid").reduce((s, v) => s + v.amount, 0),
        },
      };
    }
    if (seg[1] === "companies" && (seg[3] === "suspend" || seg[3] === "activate")) {
      store.mutate((d) => {
        d.companies.find((c) => c.id === num(seg[2]))!.status = seg[3] === "suspend" ? "suspended" : "active";
      });
      return { data: companyResource(store.db, num(seg[2])) };
    }
    if (method === "GET" && seg[1] === "plans") {
      return {
        data: db.plans.map((p) => ({
          ...planResource(db, p.code)!,
          companies_count: db.companies.filter((c) => c.plan_code === p.code).length,
        })),
      };
    }
    if (method === "GET" && seg[1] === "payments") {
      let rows = db.invoices;
      if (query.status) rows = rows.filter((i) => i.status === query.status);
      if (query.method) rows = rows.filter((i) => i.method === query.method);
      const page = paginate(rows, int(query.page, 1), int(query.per_page, 25));
      return {
        data: page.data.map((i) => invoiceResource(i, db)),
        meta: {
          ...page.meta,
          collected: db.invoices.filter((i) => i.status === "paid").reduce((s, i) => s + i.amount, 0),
          outstanding: db.invoices.filter((i) => ["pending", "failed"].includes(i.status)).reduce((s, i) => s + i.amount, 0),
        },
      };
    }
    if (method === "GET" && seg[1] === "users") {
      let rows = db.users;
      if (query.role) rows = rows.filter((u) => u.role === query.role);
      if (query.status) rows = rows.filter((u) => u.status === query.status);
      const q = (query.q ?? "").toLowerCase();
      if (q) rows = rows.filter((u) => `${u.name}${u.email}`.toLowerCase().includes(q));
      const page = paginate(rows, int(query.page, 1), int(query.per_page, 25));
      return {
        data: page.data.map((u) => ({
          ...userResource(db, u),
          company: db.companies.find((c) => c.id === u.company_id)?.name ?? null,
        })),
        meta: page.meta,
      };
    }
    if (seg[1] === "users" && seg[2] && method === "PUT") {
      store.mutate((d) => {
        const row = d.users.find((u) => u.id === num(seg[2]))!;
        if (body.status) row.status = body.status;
        if (body.role) row.role = body.role;
      });
      return { data: userResource(store.db, store.db.users.find((u) => u.id === num(seg[2]))!) };
    }
  }

  throw new MockError(404, `No mock route for ${method} ${path}`);
}

/* ═════════════════════════════════════════════════════════════ helpers ══ */

function approvalStepsFor(v: MockVoucher) {
  return applicableSteps(store.db, v).filter((s) => s.position !== 1);
}

function previewNumber(typeId: number): string {
  const t = store.db.voucherTypes.find((x) => x.id === typeId)!;
  const year = new Date().getFullYear();
  return `${t.prefix}-${year}-${String(t.next_number).padStart(t.seq_padding, "0")}`;
}

function nextNumber(typeId: number): string {
  return store.mutate((d) => {
    const t = d.voucherTypes.find((x) => x.id === typeId)!;
    const year = new Date().getFullYear();
    const value = `${t.prefix}-${year}-${String(t.next_number).padStart(t.seq_padding, "0")}`;
    t.next_number += 1;
    return value;
  });
}

function usage(companyId: number | null) {
  const db = store.db;
  const company = db.companies.find((c) => c.id === companyId);
  const plan = db.plans.find((p) => p.code === company?.plan_code);
  const month = new Date(); month.setDate(1); month.setHours(0, 0, 0, 0);

  const metric = (label: string, used: number, limit: number | null, unit = "") => ({
    label, used, limit, unit, unlimited: limit === null,
    percent: limit ? Math.min(100, Math.round((used / limit) * 100)) : null,
    exceeded: limit !== null && used >= limit,
  });

  return {
    plan: plan?.name ?? null,
    users: metric("Users", db.users.filter((u) => u.company_id === companyId).length, plan?.max_users ?? null),
    vouchers_this_month: metric("Vouchers this month",
      db.vouchers.filter((v) => v.company_id === companyId && new Date(v.created_at) >= month).length,
      plan?.max_vouchers_per_month ?? null),
    departments: metric("Departments", db.departments.filter((d) => d.company_id === companyId).length, plan?.max_departments ?? null),
    storage: metric("Storage",
      Math.round(db.vouchers.filter((v) => v.company_id === companyId).reduce((s, v) => s + v.attachments.reduce((a, x) => a + x.size_bytes, 0), 0) / 1_048_576),
      plan?.storage_mb ?? null, "MB"),
    approval_levels: { label: "Approval levels", limit: plan?.max_approval_levels ?? null },
  };
}

const stat = (label: string, value: string, sub: string, icon?: string, trend?: string, up?: boolean) =>
  ({ label, value, sub, icon: icon ?? "ph-chart-bar", trend: trend ?? null, up: up ?? null });

function dashboard(user: MockUser) {
  const db = store.db;
  const currency = db.companies.find((c) => c.id === user.company_id)?.currency ?? "TZS";
  const greeting = new Date().getHours() < 12 ? "Good morning" : new Date().getHours() < 17 ? "Good afternoon" : "Good evening";
  const visible = visibleVouchers(db, user);
  const queue = pendingFor(db, user);
  const plural = (n: number) => `${n} ${n === 1 ? "voucher" : "vouchers"}`;

  const detail = (v: MockVoucher) => voucherResource(db, v, user);

  if (user.role === "super_admin") {
    const paidTotal = db.invoices.filter((i) => i.status === "paid").reduce((s, i) => s + i.amount, 0);
    return {
      role: user.role, greeting,
      data: {
        headline: `${db.companies.length} companies · ${db.users.filter((u) => u.company_id).length} users · ${db.vouchers.length} vouchers`,
        sub: `Monthly revenue ${compact(paidTotal)} · ${db.companies.filter((c) => c.status !== "active").length} accounts need attention.`,
        stats: [
          stat("Total companies", String(db.companies.length), `${db.companies.filter((c) => c.status === "active").length} active · ${db.companies.filter((c) => c.status === "trial").length} trial`, "ph-buildings", "+4", true),
          stat("Monthly revenue", compact(paidTotal), "invoices paid", "ph-currency-circle-dollar", "+18%", true),
          stat("Total users", String(db.users.filter((u) => u.company_id).length), "across all companies", "ph-users-three", "+12", true),
          stat("Total vouchers", String(db.vouchers.length), "platform-wide", "ph-receipt", "+11%", true),
          stat("Awaiting action", String(db.vouchers.filter((v) => ["in_review", "approved"].includes(v.status)).length), "in a workflow", "ph-list-checks"),
          stat("Paid", String(db.vouchers.filter((v) => v.status === "paid").length), "closed vouchers", "ph-check-circle", "96%", true),
        ],
        recent_companies: db.companies.map((c) => ({
          id: c.id, name: c.name, plan: db.plans.find((p) => p.code === c.plan_code)?.name ?? null,
          status: c.status, users_count: db.users.filter((u) => u.company_id === c.id).length,
          vouchers_count: db.vouchers.filter((v) => v.company_id === c.id).length, created_at: c.created_at,
        })),
        recent_payments: db.invoices.slice(0, 6).map((i) => ({
          id: i.id, number: i.number, company: db.companies.find((c) => c.id === i.company_id)?.name,
          total: i.amount, currency: i.currency, status: i.status, method: i.method, created_at: i.issued_at,
        })),
      },
    };
  }

  if (user.role === "cashier") {
    const due = visible.filter((v) => v.status === "approved");
    const paidThisMonth = visible.filter((v) => v.status === "paid");
    const cash = due.filter((v) => v.kind === "cash").reduce((s, v) => s + v.amount, 0);
    const bank = due.filter((v) => v.kind === "bank").reduce((s, v) => s + v.amount, 0);
    return {
      role: user.role, greeting,
      data: {
        headline: `${plural(due.length)} awaiting payment`,
        sub: "Each one is approved and cleared for release.",
        stats: [
          stat("Due today", String(due.length), compact(due.reduce((s, v) => s + v.amount, 0)), "ph-hourglass-medium"),
          stat("Cash to release", compact(cash), `${plural(due.filter((v) => v.kind === "cash").length)} · cash`, "ph-money"),
          stat("Bank transfers", compact(bank), `${plural(due.filter((v) => v.kind === "bank").length)} · bank`, "ph-bank"),
          stat("Paid", String(paidThisMonth.length), compact(paidThisMonth.reduce((s, v) => s + v.amount, 0)), "ph-check-circle", "+9%", true),
        ],
        queue: due.map(detail),
        recent: paidThisMonth.slice(0, 6).map(detail),
      },
    };
  }

  if (user.role === "employee") {
    const mine = visible;
    const inFlight = mine.filter((v) => ["in_review", "approved"].includes(v.status));
    return {
      role: user.role, greeting,
      data: {
        headline: inFlight.length ? `${plural(inFlight.length)} in the approval workflow` : "Create a voucher",
        sub: "You see only your own vouchers.",
        stats: [
          stat("My vouchers", String(mine.length), "all time", "ph-receipt", "+3", true),
          stat("In the workflow", String(inFlight.length), "with an approver", "ph-hourglass-medium"),
          stat("Paid", String(mine.filter((v) => v.status === "paid").length), "released", "ph-check-circle"),
          stat("Total requested", compact(mine.reduce((s, v) => s + v.amount, 0), currency), "all time", "ph-coins"),
        ],
        recent: mine.slice(0, 6).map(detail),
      },
    };
  }

  const isApprover = ["hod", "ceo", "finance", "director"].includes(user.role);
  if (isApprover) {
    const signOnly = queue.every((v) => !stepAt(db, v, v.current_step_position)?.can_approve);
    const acted = db.approvals.filter((a) => a.actor_id === user.id && ["signed", "approved"].includes(a.action)).length;
    const scoped = db.departments.filter((d) => d.hod_user_id === user.id || d.manager_user_id === user.id).map((d) => d.id);
    const deptValue = visible
      .filter((v) => scoped.includes(v.department_id ?? -1) && v.status === "paid")
      .reduce((s, v) => s + v.amount, 0);
    return {
      role: user.role, greeting,
      data: {
        headline: queue.length ? `${plural(queue.length)} awaiting your ${signOnly ? "signature" : "decision"}` : "Nothing awaiting you",
        sub: signOnly
          ? "Your step signs only — the approval decision sits with a later step."
          : "Each one has reached your step in the approval workflow.",
        stats: [
          stat("Awaiting you", String(queue.length), "right now", "ph-hourglass-medium"),
          stat("Actioned", String(acted), "signed or approved", "ph-signature", "+6", true),
          stat("Returned", String(db.approvals.filter((a) => a.actor_id === user.id && ["rejected", "changes_requested"].includes(a.action)).length), "all time", "ph-arrow-u-up-left"),
          stat("Department value", compact(deptValue, currency), "paid this quarter", "ph-chart-line-up"),
        ],
        queue: queue.map(detail),
        recent: visible.slice(0, 6).map(detail),
      },
    };
  }

  // Company administrator.
  const pending = visible.filter((v) => ["in_review", "approved"].includes(v.status));
  const paid = visible.filter((v) => v.status === "paid");
  const rejected = visible.filter((v) => v.status === "rejected");
  const month = new Date(); month.setDate(1); month.setHours(0, 0, 0, 0);
  const thisMonth = visible.filter((v) => new Date(v.voucher_date) >= month).reduce((s, v) => s + v.amount, 0);

  const volume: { period: string; label: string; count: number; total: number; is_current: boolean }[] = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(); d.setMonth(d.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const rows = visible.filter((v) => v.voucher_date.startsWith(key));
    volume.push({
      period: key, label: d.toLocaleString("en", { month: "short" }),
      count: rows.length, total: rows.reduce((s, v) => s + v.amount, 0), is_current: i === 0,
    });
  }

  const byDept = db.departments.filter((d) => d.company_id === user.company_id).map((d) => {
    const rows = visible.filter((v) => v.department_id === d.id && v.status === "paid");
    return { id: d.id, name: d.name, count: rows.length, total: rows.reduce((s, v) => s + v.amount, 0), share: "0%" };
  }).sort((a, b) => b.total - a.total);
  const max = Math.max(...byDept.map((d) => d.total), 1);
  byDept.forEach((d) => { d.share = `${Math.round((d.total / max) * 100)}%`; });

  return {
    role: user.role, greeting,
    data: {
      headline: pending.length ? `${plural(pending.length)} in the approval workflow` : "Everything is up to date",
      sub: visible.length ? `${Math.round((paid.length / visible.length) * 100)}% of vouchers have been paid.` : "No vouchers yet.",
      stats: [
        stat("Total vouchers", String(visible.length), "all time", "ph-receipt", "+12%", true),
        stat("In workflow", String(pending.length), "awaiting a step", "ph-hourglass-medium"),
        stat("Paid", String(paid.length), `${visible.length ? Math.round((paid.length / visible.length) * 100) : 0}% of all`, "ph-check-circle", "96%", true),
        stat("Rejected", String(rejected.length), `${visible.length ? Math.round((rejected.length / visible.length) * 100) : 0}% of all`, "ph-x-circle", "3.2%", false),
        stat("Value this month", compact(thisMonth, currency), "requested", "ph-chart-line-up", "+37%", true),
        stat("Awaiting payment", String(visible.filter((v) => v.status === "approved").length), "with the cashier", "ph-wallet"),
      ],
      queue: queue.map(detail),
      volume, by_department: byDept,
      recent: visible.slice(0, 8).map(detail),
    },
  };
}

function reportKinds() {
  return [
    { key: "vouchers", icon: "ph-receipt", title: "Voucher report", title_sw: "Ripoti ya vocha", body: "Every voucher with status, approver and amount", body_sw: "Kila vocha na hali, mwidhinishaji na kiasi" },
    { key: "expenses", icon: "ph-coins", title: "Expense report", title_sw: "Ripoti ya matumizi", body: "Spend by category and cost centre", body_sw: "Matumizi kwa kundi na kituo cha gharama" },
    { key: "departments", icon: "ph-buildings", title: "Department report", title_sw: "Ripoti ya idara", body: "Volume and value per department", body_sw: "Wingi na thamani kwa kila idara" },
    { key: "employees", icon: "ph-user", title: "Employee report", title_sw: "Ripoti ya mfanyakazi", body: "Requests and outcomes per person", body_sw: "Maombi na matokeo kwa kila mtu" },
    { key: "approvals", icon: "ph-list-checks", title: "Approval report", title_sw: "Ripoti ya idhini", body: "Turnaround times and rejection reasons", body_sw: "Muda wa kushughulikia na sababu za kukataa" },
    { key: "payments", icon: "ph-wallet", title: "Payment report", title_sw: "Ripoti ya malipo", body: "Cash and bank releases with references", body_sw: "Malipo ya taslimu na benki na kumbukumbu" },
  ];
}

function report(kind: string, user: MockUser, query: Query) {
  const db = store.db;
  let rows = visibleVouchers(db, user);
  if (query.from) rows = rows.filter((v) => v.voucher_date >= query.from);
  if (query.to) rows = rows.filter((v) => v.voucher_date <= query.to);
  if (query.department_id) rows = rows.filter((v) => v.department_id === Number(query.department_id));
  if (query.voucher_type_id) rows = rows.filter((v) => v.voucher_type_id === Number(query.voucher_type_id));
  if (query.status && query.status !== "all") {
    rows = query.status === "pending" ? rows.filter((v) => v.status === "in_review") : rows.filter((v) => v.status === query.status);
  }

  const name = (id: number | null) => db.users.find((u) => u.id === id)?.name ?? "—";
  const dept = (id: number | null) => db.departments.find((d) => d.id === id)?.name ?? "—";
  const currency = db.companies.find((c) => c.id === user.company_id)?.currency ?? "TZS";

  let headings: string[] = [];
  let data: (string | number | null)[][] = [];
  let title = "Voucher report";

  switch (kind) {
    case "expenses": {
      title = "Expense report";
      headings = ["Category", "Cost centres", "Vouchers", "Value"];
      const groups = new Map<string, MockVoucher[]>();
      rows.filter((v) => v.status === "paid").forEach((v) => {
        const key = v.category ?? "Uncategorised";
        groups.set(key, [...(groups.get(key) ?? []), v]);
      });
      data = [...groups.entries()].map(([cat, list]) => [
        cat, [...new Set(list.map((v) => v.cost_centre).filter(Boolean))].join(", ") || "—",
        list.length, list.reduce((s, v) => s + v.amount, 0),
      ]).sort((a, b) => (b[3] as number) - (a[3] as number));
      break;
    }
    case "departments": {
      title = "Department report";
      headings = ["Department", "Head of department", "Vouchers", "Paid value", "Awaiting payment"];
      data = db.departments.filter((d) => d.company_id === user.company_id).map((d) => {
        const list = rows.filter((v) => v.department_id === d.id);
        return [
          d.name, name(d.hod_user_id), list.length,
          list.filter((v) => v.status === "paid").reduce((s, v) => s + v.amount, 0),
          list.filter((v) => v.status === "approved").reduce((s, v) => s + v.amount, 0),
        ];
      });
      break;
    }
    case "employees": {
      title = "Employee report";
      headings = ["Employee", "Department", "Requests", "Paid", "Rejected", "Total value"];
      const groups = new Map<number, MockVoucher[]>();
      rows.forEach((v) => groups.set(v.requester_id, [...(groups.get(v.requester_id) ?? []), v]));
      data = [...groups.entries()].map(([uid, list]) => [
        name(uid), dept(list[0].department_id), list.length,
        list.filter((v) => v.status === "paid").length,
        list.filter((v) => v.status === "rejected").length,
        list.reduce((s, v) => s + v.amount, 0),
      ]).sort((a, b) => (b[5] as number) - (a[5] as number));
      break;
    }
    case "approvals": {
      title = "Approval report";
      headings = ["Number", "Requester", "Submitted", "Decided", "Decided by", "Outcome", "Days"];
      data = rows.filter((v) => v.submitted_at).map((v) => {
        const decision = [...db.approvals].reverse().find((a) => a.voucher_id === v.id && ["approved", "rejected", "changes_requested"].includes(a.action));
        const days = decision && v.submitted_at
          ? Math.round(((new Date(decision.acted_at).getTime() - new Date(v.submitted_at).getTime()) / 86_400_000) * 100) / 100
          : null;
        return [v.number, name(v.requester_id), v.submitted_at?.slice(0, 10) ?? "—",
          decision?.acted_at.slice(0, 10) ?? "Pending", decision?.actor_name ?? "—",
          presentStatus(db, v).label, days];
      });
      break;
    }
    case "payments": {
      title = "Payment report";
      headings = ["Number", "Format", "Payee", "Amount", "Method", "Reference", "Paid by", "Paid on"];
      data = rows.filter((v) => v.status === "paid").map((v) => [
        v.number, v.kind === "cash" ? "Cash" : "Bank", v.payee, v.amount,
        v.payment_method ?? "—", v.payment_reference ?? "—", v.paid_by ?? "—", v.paid_at?.slice(0, 10) ?? "—",
      ]);
      break;
    }
    default: {
      headings = ["Number", "Date", "Format", "Type", "Department", "Requester", "Payee", "Purpose", "Amount", "Status"];
      data = rows.map((v) => [
        v.number, v.voucher_date, v.kind === "cash" ? "Cash" : "Bank",
        db.voucherTypes.find((t) => t.id === v.voucher_type_id)?.name ?? "—",
        dept(v.department_id), name(v.requester_id), v.payee, v.purpose, v.amount,
        presentStatus(db, v).label,
      ]);
    }
  }

  const total = rows.reduce((s, v) => s + v.amount, 0);
  const paidTotal = rows.filter((v) => v.status === "paid").reduce((s, v) => s + v.amount, 0);

  return {
    kind, headings, rows: data,
    summary: {
      count: rows.length, total, total_text: money(total, currency),
      approved_total: paidTotal, approved_total_text: money(paidTotal, currency), currency,
    },
    filters: query, generated_at: now(),
  };
}
