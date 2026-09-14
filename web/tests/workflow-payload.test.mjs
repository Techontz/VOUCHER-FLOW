/**
 * Saving a workflow must never change what the person did not change.
 * Both regressions this guards against were silent: the save succeeded, and
 * the route quietly lost a capability or gained a signature requirement.
 */
import assert from "node:assert/strict";
import test from "node:test";
import { workflowPayload } from "../.mocktest/workflow-payload.js";

const step = (over) => ({
  id: 1, position: 1, name: "Step", name_sw: null, label: "Step", role: "ceo", role_label: "CEO",
  assigned_user_id: null, assignee_hint: null,
  can_sign: false, can_approve: false, can_reject: false, can_request_changes: false,
  can_pay: false, can_print: true, can_download: true, requires_signature: false,
  min_amount: null, max_amount: null, is_request_step: false, ...over,
});
const wf = { name: "Route", description: null, is_default: true, is_active: true };

test("a cashier's payment capability survives a save", () => {
  const body = workflowPayload(wf, [step({ role: "cashier", can_sign: true, can_pay: true })]);
  assert.equal(body.steps[0].can_pay, true);
});

test("a sign-and-approve step keeps requires_signature false", () => {
  const body = workflowPayload(wf, [step({ can_sign: true, can_approve: true, requires_signature: false })]);
  assert.equal(body.steps[0].requires_signature, false, "must not be derived from can_sign");
});

test("an explicit signature requirement is preserved", () => {
  const body = workflowPayload(wf, [step({ can_sign: true, requires_signature: true })]);
  assert.equal(body.steps[0].requires_signature, true);
});

test("every stored capability flag round-trips unchanged", () => {
  const flags = ["can_sign", "can_approve", "can_reject", "can_request_changes", "can_pay", "can_print", "can_download", "requires_signature"];
  // Try every flag on its own, on and off, so no single omission can hide.
  for (const flag of flags) {
    for (const value of [true, false]) {
      const base = Object.fromEntries(flags.map((f) => [f, !value]));
      const body = workflowPayload(wf, [step({ ...base, [flag]: value })]);
      assert.equal(body.steps[0][flag], value, `${flag}=${value} was not sent as loaded`);
    }
  }
});

test("thresholds, assignee and order are kept", () => {
  const body = workflowPayload(wf, [step({ id: 9, min_amount: 1_000_000, max_amount: 5_000_000, assigned_user_id: 42 }), step({ id: 3 })]);
  assert.deepEqual([body.steps[0].min_amount, body.steps[0].max_amount, body.steps[0].assigned_user_id], [1_000_000, 5_000_000, 42]);
  assert.deepEqual(body.steps.map((s) => s.position), [1, 2], "positions follow the edited order");
});
