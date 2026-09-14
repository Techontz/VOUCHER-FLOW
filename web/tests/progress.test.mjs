/**
 * deriveProgress mirrors WorkflowEngine's step rules on the server. If the two
 * disagree, a dashboard tells an approver the wrong thing about where a voucher
 * is — so the rules are pinned here, against a route that is NOT the demo one.
 */
import assert from "node:assert/strict";
import test from "node:test";
import { deriveProgress, applicableSteps } from "../.mocktest/progress.js";

const step = (position, role, role_label, caps = {}, extra = {}) => ({
  position, role, role_label, name: role_label, name_sw: null, label: role_label,
  assigned_user_id: null, assignee_hint: null,
  can_sign: false, can_approve: false, can_reject: false, can_request_changes: false,
  can_pay: false, can_print: true, can_download: true, requires_signature: false,
  min_amount: null, max_amount: null, is_request_step: false,
  ...caps, ...extra,
});

// Employee → Supervisor (sign) → Finance Manager (approve, only above 1M) → CEO (approve) → Cashier (pay)
const workflow = {
  id: 7, name: "Custom", description: null, voucher_type_id: null, is_default: true, is_active: true, version: 1, updated_at: null,
  steps: [
    step(1, "employee", "Employee"),
    step(2, "hod", "Supervisor", { can_sign: true }),
    step(3, "finance", "Finance Manager", { can_approve: true }, { min_amount: 1_000_000 }),
    step(4, "ceo", "CEO", { can_approve: true }),
    step(5, "cashier", "Cashier", { can_pay: true }),
  ],
};

const v = (over) => ({ workflow_id: 7, amount: 5_000_000, status: "in_review", current_step_position: 2, ...over });
const states = (steps) => steps.map((s) => `${s.label}:${s.state}`);

test("a route that is not the demo's is followed as configured", () => {
  assert.deepEqual(states(deriveProgress(v({ current_step_position: 4 }), [workflow])), [
    "Prepared:done", "Supervisor:done", "Finance Manager:done", "CEO:current", "Cashier:pending",
  ]);
});

test("amount thresholds drop steps the voucher never passes through", () => {
  const small = deriveProgress(v({ amount: 250_000, current_step_position: 4 }), [workflow]);
  assert.ok(!small.some((s) => s.label === "Finance Manager"), "Finance Manager applies only above 1M");
  assert.equal(applicableSteps(workflow, 250_000).length, 4);
  assert.equal(applicableSteps(workflow, 5_000_000).length, 5);
});

test("the request and payment steps are not listed as approvals", () => {
  const labels = deriveProgress(v({}), [workflow]).map((s) => s.label);
  assert.ok(!labels.includes("Employee"), "the request step is shown as Prepared");
  assert.equal(labels.at(-1), "Cashier", "payment comes last");
});

test("a draft has not started", () => {
  assert.deepEqual(states(deriveProgress(v({ status: "draft", current_step_position: null }), [workflow])), [
    "Prepared:current", "Supervisor:pending", "Finance Manager:pending", "CEO:pending", "Cashier:pending",
  ]);
});

test("approved means every approval is done and payment is the current step", () => {
  const s = deriveProgress(v({ status: "approved", current_step_position: null }), [workflow]);
  assert.deepEqual(states(s).slice(1, 4), ["Supervisor:done", "Finance Manager:done", "CEO:done"]);
  assert.equal(s.at(-1).state, "current");
});

test("paid is complete end to end", () => {
  assert.ok(deriveProgress(v({ status: "paid", current_step_position: null }), [workflow]).every((s) => s.state === "done"));
});

test("a rejection stops the route where it was made", () => {
  assert.deepEqual(states(deriveProgress(v({ status: "rejected", current_step_position: 3 }), [workflow])), [
    "Prepared:done", "Supervisor:done", "Finance Manager:rejected", "CEO:pending", "Cashier:pending",
  ]);
});

test("a rejection with no recorded position still shows a rejected step", () => {
  const s = deriveProgress(v({ status: "rejected", current_step_position: null }), [workflow]);
  assert.equal(s.filter((x) => x.state === "rejected").length, 1);
});

test("an unknown workflow yields no track rather than a wrong one", () => {
  assert.deepEqual(deriveProgress(v({ workflow_id: 999 }), [workflow]), []);
  assert.deepEqual(deriveProgress(v({}), null), []);
});

import { resolveWorkflow, routeFor } from "../.mocktest/progress.js";

test("a workflow bound to the voucher type beats the general default", () => {
  const general = { ...workflow, id: 1, voucher_type_id: null, is_default: true, is_active: true };
  const specific = { ...workflow, id: 2, voucher_type_id: 5, is_default: false, is_active: true };
  assert.equal(resolveWorkflow([general, specific], 5).id, 2);
  assert.equal(resolveWorkflow([general, specific], 9).id, 1, "other types fall back to the default");
});

test("inactive workflows are never chosen", () => {
  const off = { ...workflow, id: 3, voucher_type_id: 5, is_active: false };
  const general = { ...workflow, id: 1, voucher_type_id: null, is_default: true, is_active: true };
  assert.equal(resolveWorkflow([off, general], 5).id, 1);
  assert.equal(resolveWorkflow([off], 5), null);
});

test("the previewed route respects the amount", () => {
  assert.deepEqual(routeFor(workflow, 250_000), ["Supervisor", "CEO", "Cashier"]);
  assert.deepEqual(routeFor(workflow, 5_000_000), ["Supervisor", "Finance Manager", "CEO", "Cashier"]);
});
