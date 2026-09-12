/**
 * The mock API has to accept attachments the way Laravel does.
 *
 * POST /vouchers/{id}/attachments fell through the action switch and answered
 * `Unknown action "attachments"`, which is what a build running on the fixture
 * showed when anyone tried to attach a document. These cases pin the action to
 * VoucherAttachmentController@store's contract: the editability gate, the
 * limits from config/vouchflow.php, and every chosen file rather than the last.
 *
 * Run with:  node --test tests/
 */
import assert from "node:assert/strict";
import test from "node:test";
import { handle, MockError } from "../.mocktest/mock/router.js";
import { store } from "../.mocktest/mock/store.js";

const PDF = { name: "invoice.pdf", size: 120_000, type: "application/pdf" };

function signIn(email) {
  store.reset?.();
  const out = handle("POST", "/auth/login", { email, password: "Password123!" }, {}, null);
  return out.token;
}

/** A draft belonging to the signed-in employee — the editable case. */
function ownDraft(token) {
  const list = handle("GET", "/vouchers", {}, { status: "draft", per_page: 50 }, token);
  const draft = list.data.find((v) => v.status === "draft");
  assert.ok(draft, "the fixture should contain a draft to attach to");
  return draft;
}

test("a single attachment is accepted and recorded", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);
  const before = handle("GET", `/vouchers/${draft.id}`, {}, {}, token).data.attachments.length;

  const res = handle("POST", `/vouchers/${draft.id}/attachments`, { "files[]": [PDF] }, {}, token);

  assert.equal(res.data.length, 1);
  assert.equal(res.data[0].name, "invoice.pdf");
  assert.equal(res.data[0].mime_type, "application/pdf");
  assert.equal(res.data[0].size_bytes, 120_000);
  assert.equal(res.data[0].is_image, false);

  const after = handle("GET", `/vouchers/${draft.id}`, {}, {}, token).data.attachments;
  assert.equal(after.length, before + 1, "the voucher should carry the new file");
});

test("every chosen file is stored, not just the last", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  const res = handle("POST", `/vouchers/${draft.id}/attachments`, {
    "files[]": [PDF, { name: "photo.png", size: 40_000, type: "image/png" }],
  }, {}, token);

  assert.equal(res.data.length, 2, "both files should be recorded");
  assert.deepEqual(res.data.map((a) => a.name), ["invoice.pdf", "photo.png"]);
  assert.equal(res.data[1].is_image, true);
});

test("ids are unique across uploads", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  const a = handle("POST", `/vouchers/${draft.id}/attachments`, { "files[]": [PDF] }, {}, token);
  const b = handle("POST", `/vouchers/${draft.id}/attachments`, { "files[]": [PDF] }, {}, token);

  assert.notEqual(a.data[0].id, b.data[0].id);
});

test("a disallowed file type is refused, as Laravel refuses it", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  assert.throws(
    () => handle("POST", `/vouchers/${draft.id}/attachments`, {
      "files[]": [{ name: "payload.exe", size: 1000, type: "application/x-msdownload" }],
    }, {}, token),
    (err) => err instanceof MockError && err.status === 422 && /PDF or an image/.test(err.message),
  );
});

test("a file over the size limit is refused", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  assert.throws(
    () => handle("POST", `/vouchers/${draft.id}/attachments`, {
      "files[]": [{ name: "huge.pdf", size: 11 * 1_048_576, type: "application/pdf" }],
    }, {}, token),
    (err) => err instanceof MockError && err.status === 422 && /under 10 MB/.test(err.message),
  );
});

test("an empty upload is refused", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  assert.throws(
    () => handle("POST", `/vouchers/${draft.id}/attachments`, {}, {}, token),
    (err) => err instanceof MockError && err.status === 422,
  );
});

test("a voucher that is no longer editable refuses attachments", () => {
  const token = signIn("frank@watercom.test");
  const list = handle("GET", "/vouchers", {}, { per_page: 100 }, token);
  const settled = list.data.find((v) => v.status === "paid" || v.status === "approved");
  assert.ok(settled, "the fixture should contain a settled voucher");

  assert.throws(
    () => handle("POST", `/vouchers/${settled.id}/attachments`, { "files[]": [PDF] }, {}, token),
    (err) => err instanceof MockError && err.status === 403 && /editable/.test(err.message),
  );
});

test("the action no longer falls through to Unknown action", () => {
  const token = signIn("frank@watercom.test");
  const draft = ownDraft(token);

  try {
    handle("POST", `/vouchers/${draft.id}/attachments`, { "files[]": [PDF] }, {}, token);
  } catch (err) {
    assert.fail(`attachments should be handled, got: ${err.message}`);
  }

  // A genuinely unknown action must still be reported as one.
  assert.throws(
    () => handle("POST", `/vouchers/${draft.id}/teleport`, {}, {}, token),
    (err) => err instanceof MockError && /Unknown action "teleport"/.test(err.message),
  );
});
