/**
 * Mock mode has to configure approvers the way the API does: create, bind to
 * a voucher type, make default, delete, and show who acts per department —
 * refusing the same things, and never crossing into another company.
 *
 * Run with:  node --test tests/
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle, MockError } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

function signIn(email) {
  store.reset?.();
  const challenge = handle("POST", "/auth/login", { email, password: "Password123!" }, {}, null);
  const out = handle("POST", "/auth/login/verify", { challenge: challenge.challenge, code: "418205" }, {}, null);
  return out.token;
}

const refused = (fn, status) => assert.throws(fn, (e) => e instanceof MockError && e.status === status);

test("create, bind, make default and delete follow the API's rules", () => {
  const token = signIn("admin@watercom.test");
  const list = handle("GET", "/workflows", {}, {}, token).data;
  const def = list.find((w) => w.is_default);
  const type = handle("GET", "/voucher-types", {}, {}, token).data[1];

  const created = handle("POST", "/workflows", { name: "Petty cash", voucher_type_id: type.id, from_preset: "single" }, {}, token).data;
  assert.equal(created.voucher_type_id, type.id);
  assert.equal(created.is_default, false);

  // The binding survives a save that does not mention it.
  const saved = handle("PUT", `/workflows/${created.id}`, { name: "Petty cash route", steps: created.steps }, {}, token).data;
  assert.equal(saved.voucher_type_id, type.id);

  // A type-bound workflow cannot become the default; the default cannot be deleted.
  refused(() => handle("POST", `/workflows/${created.id}/make-default`, {}, {}, token), 422);
  refused(() => handle("DELETE", `/workflows/${def.id}`, {}, {}, token), 422);

  handle("DELETE", `/workflows/${created.id}`, {}, {}, token);
  assert.ok(!handle("GET", "/workflows", {}, {}, token).data.some((w) => w.id === created.id));
});

test("an unworkable route is refused", () => {
  const token = signIn("admin@watercom.test");
  const def = handle("GET", "/workflows", {}, {}, token).data.find((w) => w.is_default);
  const noPayer = def.steps.map((s) => ({ ...s, can_pay: false }));
  refused(() => handle("PUT", `/workflows/${def.id}`, { name: def.name, steps: noPayer }, {}, token), 422);
  const badBand = def.steps.map((s, i) => (i === 2 ? { ...s, min_amount: 500, max_amount: 100 } : s));
  refused(() => handle("PUT", `/workflows/${def.id}`, { name: def.name, steps: badBand }, {}, token), 422);
});

test("the routing matrix covers the company's own departments only", () => {
  const token = signIn("admin@watercom.test");
  const def = handle("GET", "/workflows", {}, {}, token).data.find((w) => w.is_default);
  const routing = handle("GET", `/workflows/${def.id}/routing`, {}, {}, token).data;
  const own = handle("GET", "/departments", {}, {}, token).data.map((d) => d.id).sort();
  assert.deepEqual(routing.departments.map((d) => d.id).sort(), own);
  assert.ok(routing.departments.every((d) => d.cells.length === def.steps.length - 1));

  const other = signIn("admin@zamani.test");
  refused(() => handle("GET", `/workflows/${def.id}/routing`, {}, {}, other), 404);
});
