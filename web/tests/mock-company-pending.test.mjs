/**
 * A self-registered company waits for platform approval: the API refuses the
 * product with 403 company_pending but still lets it sign in, read itself and
 * pay; a super admin approves it with POST platform/companies/{id}/approve.
 *
 * Run with:  node --test tests/
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

function signIn(email) {
  const challenge = handle("POST", "/auth/login", { email, password: "Password123!" }, {}, null);
  return handle("POST", "/auth/login/verify", { challenge: challenge.challenge, code: "418205" }, {}, null).token;
}

function refused(fn) {
  try { fn(); } catch (error) { return error; }
  assert.fail("expected the call to be refused");
}

test("a pending company is gated, can pay, and is let in once approved", () => {
  store.reset();
  const companyId = store.db.users.find((u) => u.email === "admin@watercom.test").company_id;
  store.mutate((d) => { d.companies.find((c) => c.id === companyId).status = "pending"; });

  const admin = signIn("admin@watercom.test");
  assert.equal(handle("GET", "/auth/me", {}, {}, admin).company.status, "pending");

  const error = refused(() => handle("GET", "/dashboard", {}, {}, admin));
  assert.equal(error.status, 403);
  assert.equal(error.code, "company_pending");
  assert.equal(error.details.status, "pending");

  // Still allowed: billing, notifications, own company record.
  assert.ok(handle("GET", "/billing/subscription", {}, {}, admin));
  assert.ok(handle("GET", "/notifications/unread-count", {}, {}, admin));

  const superAdmin = signIn("super@vouchflow.test");
  const pending = handle("GET", "/platform/companies", {}, { status: "pending" }, superAdmin);
  assert.deepEqual(pending.data.map((c) => c.id), [companyId]);

  const approved = handle("POST", `/platform/companies/${companyId}/approve`, {}, {}, superAdmin);
  assert.notEqual(approved.data.status, "pending");

  // Approving twice is refused.
  assert.equal(refused(() => handle("POST", `/platform/companies/${companyId}/approve`, {}, {}, superAdmin)).status, 422);

  // The administrator now reaches the product.
  assert.ok(handle("GET", "/dashboard", {}, {}, signIn("admin@watercom.test")));
  store.reset();
});
