/**
 * Part payments and payment acknowledgements in the mock API.
 *
 * A voucher approved for 10,000,000 may be paid 9,000,000 now and 1,000,000
 * later. These cases pin the fixture to VoucherController@pay and
 * VoucherPaymentController: each release is its own payment, the voucher stays
 * approved (status_key partially_paid) while a balance remains, the amount is
 * checked against the balance, and a signed acknowledgement is filed against
 * its payment as a supporting document.
 *
 * Run with:  npm test
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle, MockError } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

const SIGNED = { name: "signed.pdf", size: 80_000, type: "application/pdf" };

function signIn(email) {
  const challenge = handle("POST", "/auth/login", { email, password: "Password123!" }, {}, null);
  const out = handle("POST", "/auth/login/verify", { challenge: challenge.challenge, code: "418205" }, {}, null);
  return out.token;
}

/** A fresh demo, the cashier's token, and one voucher they may pay. */
function payable(kind) {
  store.reset();
  const token = signIn("mwajuma@watercom.test");
  const list = handle("GET", "/vouchers", {}, { status: "approved", per_page: 100 }, token);
  const found = list.data.find((v) => v.actions?.pay && (!kind || v.kind === kind));
  assert.ok(found, `the fixture should contain a ${kind ?? ""} voucher the cashier can pay`);
  return { token, voucher: found };
}

/** The details each format requires, as the pay dialog sends them. */
const details = (voucher) => voucher.kind === "cash"
  ? { payment_method: "Cash — office float", received_by: voucher.payee }
  : { payment_method: "Bank transfer", payment_reference: "CRDB-TRX-1" };

test("a part payment keeps the voucher approved, with a balance", () => {
  const { token, voucher } = payable();
  const part = Math.floor(voucher.amount * 0.9);

  const res = handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: part }, {}, token).data;

  assert.equal(res.status, "approved");
  assert.equal(res.status_key, "partially_paid");
  assert.equal(res.is_partially_paid, true);
  assert.equal(res.amount_paid, part);
  assert.equal(res.balance, voucher.amount - part);
  assert.equal(res.actions.pay, true, "the balance can still be paid");
  assert.equal(res.payments.length, 1);
  assert.equal(res.payments[0].sequence, 1);
  assert.equal(res.payments[0].amount, part);
  assert.equal(res.payments[0].balance_after, voucher.amount - part);
  assert.equal(res.payments[0].reference, `${voucher.number}/1`);
  assert.equal(res.payments[0].acknowledged_at, null);
});

test("paying the balance settles the voucher as a second payment", () => {
  const { token, voucher } = payable();
  const part = Math.floor(voucher.amount / 2);
  handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: part }, {}, token);

  // No amount: the whole remaining balance.
  const res = handle("POST", `/vouchers/${voucher.id}/pay`, details(voucher), {}, token).data;

  assert.equal(res.status, "paid");
  assert.equal(res.status_key, "paid");
  assert.equal(res.balance, 0);
  assert.equal(res.amount_paid, voucher.amount);
  assert.equal(res.is_partially_paid, false);
  assert.deepEqual(res.payments.map((p) => p.sequence), [1, 2]);
  assert.equal(res.payments[1].amount, voucher.amount - part);
  assert.equal(res.payments[1].balance_after, 0);
});

test("a part-paid voucher stays in the payment queue", () => {
  const { token, voucher } = payable();
  handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: 1000 }, {}, token);

  const queue = handle("GET", "/vouchers", {}, { status: "approved", per_page: 100 }, token).data;
  const row = queue.find((v) => v.id === voucher.id);
  assert.ok(row, "still listed as approved");
  assert.equal(row.balance, voucher.amount - 1000);
  assert.equal(row.balance_text.startsWith(voucher.currency), true);
});

test("an amount over the balance, or not above zero, is refused", () => {
  const { token, voucher } = payable();

  for (const amount of [voucher.amount + 1, 0, -5]) {
    assert.throws(
      () => handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount }, {}, token),
      (err) => err instanceof MockError && err.status === 422 && Array.isArray(err.errors.amount),
      `amount ${amount} should be refused`,
    );
  }
});

test("cash needs a receiver and keeps the receiver's ID", () => {
  const { token, voucher } = payable("cash");

  assert.throws(
    () => handle("POST", `/vouchers/${voucher.id}/pay`, { payment_method: "Cash" }, {}, token),
    (err) => err instanceof MockError && err.status === 422 && Array.isArray(err.errors.received_by),
  );

  const res = handle("POST", `/vouchers/${voucher.id}/pay`, {
    payment_method: "Cash", received_by: "Asha Juma", receiver_id_number: "WC-0999", amount: 500,
  }, {}, token).data;
  assert.equal(res.payments[0].received_by, "Asha Juma");
  assert.equal(res.payments[0].receiver_id_number, "WC-0999");
});

test("the printable acknowledgement explains that it needs the server", () => {
  const { token, voucher } = payable();
  const paid = handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: 1000 }, {}, token).data;

  assert.throws(
    () => handle("GET", `/vouchers/${voucher.id}/payments/${paid.payments[0].id}/acknowledgement`, {}, {}, token),
    (err) => err instanceof MockError && err.status === 501,
  );
});

test("the signed copy is filed against its payment", () => {
  const { token, voucher } = payable();
  const paid = handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: 1000 }, {}, token).data;
  const payment = paid.payments[0];

  const res = handle("POST", `/vouchers/${voucher.id}/payments/${payment.id}/acknowledgement`, { file: SIGNED }, {}, token).data;

  const filed = res.payments.find((p) => p.id === payment.id);
  assert.ok(filed.acknowledged_at, "the payment is marked acknowledged");
  assert.equal(filed.acknowledgement_attachment_ids.length, 1);

  const doc = res.attachments.find((a) => a.id === filed.acknowledgement_attachment_ids[0]);
  assert.equal(doc.document_type, "payment_acknowledgement");
  assert.equal(doc.voucher_payment_id, payment.id);
});

test("someone who neither paid nor may pay cannot file the signed copy", () => {
  const { token, voucher } = payable();
  const paid = handle("POST", `/vouchers/${voucher.id}/pay`, { ...details(voucher), amount: 1000 }, {}, token).data;

  // The requester can see the voucher but did not pay it.
  const requester = store.db.users.find((u) => u.id === voucher.requester_id);
  const other = signIn(requester.email);

  assert.throws(
    () => handle("POST", `/vouchers/${voucher.id}/payments/${paid.payments[0].id}/acknowledgement`, { file: SIGNED }, {}, other),
    (err) => err instanceof MockError && err.status === 403,
  );
});
