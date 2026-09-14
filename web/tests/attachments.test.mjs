/**
 * Choosing supporting documents on a new voucher.
 *
 * The files picked must be the files sent: every one of them, each as its own
 * `files[]` part, and anything the server would refuse caught at the picker —
 * before a voucher exists that a failed upload could leave half-saved.
 */
import assert from "node:assert/strict";
import test from "node:test";
import { acceptFiles, attachmentForm, MAX_UPLOAD_MB } from "../.mocktest/attachments.js";

const file = (name, type, size = 1024, lastModified = 1) =>
  new File([new Uint8Array(size)], name, { type, lastModified });

test("PDF, JPG and PNG are all accepted", () => {
  const picked = [file("invoice.pdf", "application/pdf"), file("receipt.jpg", "image/jpeg"), file("scan.png", "image/png")];
  const { files, rejected } = acceptFiles([], picked);
  assert.deepEqual(files.map((f) => f.name), ["invoice.pdf", "receipt.jpg", "scan.png"]);
  assert.equal(rejected.length, 0);
});

test("a second pick adds to the first instead of replacing it", () => {
  const first = acceptFiles([], [file("invoice.pdf", "application/pdf")]).files;
  const { files } = acceptFiles(first, [file("scan.png", "image/png"), file("receipt.jpg", "image/jpeg")]);
  assert.equal(files.length, 3);
});

test("a type the server refuses is rejected at the picker", () => {
  const { files, rejected } = acceptFiles([], [file("logo.gif", "image/gif"), file("setup.exe", "application/x-msdownload")]);
  assert.equal(files.length, 0);
  assert.deepEqual(rejected.map((r) => r.reason), ["type", "type"]);
});

test("a file with no reported type is judged by its extension", () => {
  const { files } = acceptFiles([], [file("photo.heic", ""), file("contract.PDF", "")]);
  assert.equal(files.length, 2);
});

test(`a file over ${MAX_UPLOAD_MB} MB is rejected`, () => {
  const { files, rejected } = acceptFiles([], [file("huge.pdf", "application/pdf", MAX_UPLOAD_MB * 1024 * 1024 + 1)]);
  assert.equal(files.length, 0);
  assert.equal(rejected[0].reason, "size");
});

test("the same file chosen twice is kept once", () => {
  const a = file("invoice.pdf", "application/pdf", 2048, 42);
  const { files, rejected } = acceptFiles([a], [file("invoice.pdf", "application/pdf", 2048, 42)]);
  assert.equal(files.length, 1);
  assert.equal(rejected.length, 0);
});

test("no more than ten files are queued for one upload", () => {
  const picked = Array.from({ length: 12 }, (_, i) => file(`page-${i}.pdf`, "application/pdf", 100, i));
  const { files, rejected } = acceptFiles([], picked);
  assert.equal(files.length, 10);
  assert.deepEqual(rejected.map((r) => r.reason), ["count", "count"]);
});

test("every file becomes its own files[] part — none collapsed", () => {
  const picked = [file("invoice.pdf", "application/pdf"), file("receipt.jpg", "image/jpeg"), file("scan.png", "image/png")];
  const form = attachmentForm(picked);
  const parts = form.getAll("files[]");
  assert.equal(parts.length, 3);
  assert.deepEqual(parts.map((p) => p.name), ["invoice.pdf", "receipt.jpg", "scan.png"]);
  assert.ok(parts.every((p) => p instanceof File));
  assert.deepEqual([...form.keys()], ["files[]", "files[]", "files[]"]);
});
