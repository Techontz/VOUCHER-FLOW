/**
 * Mock mode returns the same dashboard shape as the API: a view, a banner,
 * figures carrying stable keys, and recent activity — per role.
 *
 * Run with:  node --test tests/
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

function dashboardFor(email) {
  store.reset?.();
  const challenge = handle("POST", "/auth/login", { email, password: "Password123!" }, {}, null);
  const { token } = handle("POST", "/auth/login/verify", { challenge: challenge.challenge, code: "418205" }, {}, null);
  return handle("GET", "/dashboard", {}, {}, token);
}

const keys = (payload) => payload.data.stats.map((s) => s.key);

test("each role gets its own view and keyed figures", () => {
  const cases = [
    ["frank@watercom.test", "employee", "dash.stat.myVouchers"],
    ["rehema@watercom.test", "hod", "dash.stat.awaitingSignature"],
    ["emmanuel@watercom.test", "approver", "dash.stat.awaitingApproval"],
    ["mwajuma@watercom.test", "cashier", "dash.stat.awaitingPayment"],
    ["admin@watercom.test", "admin", "dash.stat.activeUsers"],
  ];

  for (const [email, view, firstKey] of cases) {
    const payload = dashboardFor(email);
    assert.equal(payload.data.view, view, email);
    assert.equal(keys(payload)[0], firstKey, email);
    assert.ok(payload.data.banner, `${email} has a banner`);
    assert.equal(payload.data.banner.count, payload.queue.length, `${email}: banner counts the queue`);
    assert.ok(Array.isArray(payload.data.recent_activity), `${email} has activity`);
    for (const stat of payload.data.stats) {
      assert.equal(typeof stat.label, "string");
      assert.equal(typeof stat.value, "string");
    }
  }
});

test("an HOD is never shown approval figures", () => {
  const payload = dashboardFor("rehema@watercom.test");
  assert.ok(!keys(payload).includes("dash.stat.awaitingApproval"));
  assert.ok(Array.isArray(payload.data.recently_signed));
});

test("the admin sees the workflow route and the subscription", () => {
  const payload = dashboardFor("admin@watercom.test");
  assert.ok(payload.data.workflow.steps.length > 0);
  assert.equal(payload.data.workflow.steps[0].action, "request");
  assert.ok(payload.data.subscription.status);
});

test("the platform view still renders", () => {
  const payload = dashboardFor("super@vouchflow.test");
  assert.equal(payload.data.view, "platform");
  assert.equal(payload.data.banner, null);
});
