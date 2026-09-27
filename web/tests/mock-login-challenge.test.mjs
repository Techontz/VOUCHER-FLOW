/**
 * Two-step sign-in in the mock API, pinned to the Laravel contract:
 * POST /auth/login → /auth/login/send-code → /auth/login/verify.
 *
 * Run with:  npm test
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle, MockError, MOCK_LOGIN_CODE } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

const PASSWORD = "Password123!";

function login(email) {
  return handle("POST", "/auth/login", { email, password: PASSWORD, device_name: "web" }, {}, null);
}

function rejects(fn, status, reason) {
  try {
    fn();
  } catch (err) {
    assert.ok(err instanceof MockError, "expected a MockError");
    assert.equal(err.status, status);
    if (reason) assert.equal(err.details.reason, reason);
    return err;
  }
  assert.fail(`expected a ${status}${reason ? ` ${reason}` : ""} error`);
}

test("a correct password returns a challenge, not a token", () => {
  store.reset();
  const res = login("frank@watercom.test");

  assert.equal(res.requires_verification, true);
  assert.equal(typeof res.challenge, "string");
  assert.equal(res.token, undefined);
  assert.deepEqual(res.channels.map((c) => c.channel), ["email"]);
  assert.equal(res.channels[0].destination, "f•••@watercom.test");
  // Only one channel, so the code has already gone.
  assert.equal(res.sent_to, "email");
  assert.equal(res.code_expires_in, 600);
  assert.equal(res.resend_in, 30);
  assert.equal(res.expires_in, 900);
  assert.ok(!JSON.stringify(res).includes(MOCK_LOGIN_CODE), "the code is never returned");
});

test("the right code completes sign-in with the usual session payload", () => {
  store.reset();
  const { challenge } = login("frank@watercom.test");
  const res = handle("POST", "/auth/login/verify", { challenge, code: MOCK_LOGIN_CODE, device_name: "web" }, {}, null);

  assert.ok(res.token);
  assert.equal(res.user.email, "frank@watercom.test");
  assert.ok(res.company);

  // The challenge is spent.
  rejects(() => handle("POST", "/auth/login/verify", { challenge, code: MOCK_LOGIN_CODE }, {}, null), 422, "challenge_expired");
});

test("a user with a phone chooses a channel before any code is sent", () => {
  store.reset();
  store.mutate((d) => { d.users.find((u) => u.email === "frank@watercom.test").phone = "+255 713 000 418"; });

  const res = login("frank@watercom.test");
  assert.deepEqual(res.channels.map((c) => c.channel), ["email", "sms"]);
  assert.equal(res.channels[1].destination, "+255 7•• ••• 418");
  assert.equal(res.sent_to, null);
  assert.equal(res.resend_in, null);

  rejects(() => handle("POST", "/auth/login/verify", { challenge: res.challenge, code: MOCK_LOGIN_CODE }, {}, null), 422, "no_code");

  const sent = handle("POST", "/auth/login/send-code", { challenge: res.challenge, channel: "sms" }, {}, null);
  assert.equal(sent.sent_to, "sms");
  assert.equal(sent.resend_in, 30);
  assert.equal(sent.sends_remaining, 4);
  assert.ok(!("code" in sent));

  const again = rejects(() => handle("POST", "/auth/login/send-code", { challenge: res.challenge, channel: "email" }, {}, null), 429, "resend_cooldown");
  assert.ok(again.details.retry_after > 0);

  const ok = handle("POST", "/auth/login/verify", { challenge: res.challenge, code: MOCK_LOGIN_CODE }, {}, null);
  assert.ok(ok.token);
});

test("a channel the user does not have is refused", () => {
  store.reset();
  const { challenge } = login("frank@watercom.test");
  const err = rejects(() => handle("POST", "/auth/login/send-code", { challenge, channel: "sms" }, {}, null), 422);
  assert.ok(err.errors.channel);
});

test("wrong codes count down, then the challenge is closed", () => {
  store.reset();
  const { challenge } = login("frank@watercom.test");

  for (let left = 4; left >= 1; left--) {
    const err = rejects(() => handle("POST", "/auth/login/verify", { challenge, code: "000000" }, {}, null), 422, "invalid_code");
    assert.equal(err.details.attempts_remaining, left);
    assert.ok(err.errors.code);
  }
  rejects(() => handle("POST", "/auth/login/verify", { challenge, code: "000000" }, {}, null), 422, "too_many_attempts");
  rejects(() => handle("POST", "/auth/login/verify", { challenge, code: MOCK_LOGIN_CODE }, {}, null), 422, "challenge_expired");
});

test("wrong password is still refused on the email field", () => {
  store.reset();
  const err = rejects(() => handle("POST", "/auth/login", { email: "frank@watercom.test", password: "nope" }, {}, null), 422);
  assert.ok(err.errors.email);
});

test("otp payloads no longer carry the code", () => {
  store.reset();
  const sent = handle("POST", "/auth/otp/send", { identifier: "a@b.test", purpose: "registration" }, {}, null);
  assert.ok(!("code" in sent.otp));
  const reset = handle("POST", "/auth/forgot-password", { email: "a@b.test" }, {}, null);
  assert.ok(!("code" in reset.otp));
  rejects(() => handle("POST", "/auth/otp/send", { identifier: "a@b.test", purpose: "login" }, {}, null), 422);
});
