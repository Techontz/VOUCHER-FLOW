/**
 * Supporting documents, before they reach the server.
 *
 * The server is the authority (VoucherAttachmentController: PDF or image,
 * config('vouchflow.max_upload_mb') each, at most ten per request). These
 * mirror those rules so a file the server would refuse is caught when it is
 * picked, not after the voucher has already been created — at which point a
 * refused upload used to fail the whole save and a retry made a second voucher.
 */

/** config('vouchflow.allowed_upload_mimes'). */
export const ACCEPTED_TYPES = ["application/pdf", "image/jpeg", "image/png", "image/webp", "image/heic"] as const;

/** For the file input: what the picker offers. Extensions cover browsers that report no type. */
export const ACCEPT_ATTRIBUTE = [...ACCEPTED_TYPES, ".pdf", ".jpg", ".jpeg", ".png", ".webp", ".heic"].join(",");

export const MAX_UPLOAD_MB = 10;
export const MAX_FILES_PER_UPLOAD = 10;

const EXTENSION_TYPES: Record<string, string> = {
  pdf: "application/pdf", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", heic: "image/heic",
};

export type RejectReason = "type" | "size" | "count";

export interface Rejected {
  name: string;
  reason: RejectReason;
}

/** Some platforms (HEIC on Windows, files from certain apps) arrive with an empty type. */
function typeOf(file: Pick<File, "name" | "type">): string {
  if (file.type) return file.type.toLowerCase();
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  return EXTENSION_TYPES[ext] ?? "";
}

/** The same file chosen twice is one document, not two. */
function sameFile(a: File, b: File): boolean {
  return a.name === b.name && a.size === b.size && a.lastModified === b.lastModified;
}

/**
 * Merges newly picked files into those already chosen.
 *
 * `picked` must be a real array captured while the change or drop event is
 * still running: an input's FileList empties when its value is reset, and a
 * drop's DataTransfer empties when the event ends.
 */
export function acceptFiles(existing: File[], picked: File[]): { files: File[]; rejected: Rejected[] } {
  const files = [...existing];
  const rejected: Rejected[] = [];

  for (const file of picked) {
    if (!(ACCEPTED_TYPES as readonly string[]).includes(typeOf(file))) {
      rejected.push({ name: file.name, reason: "type" });
    } else if (file.size > MAX_UPLOAD_MB * 1024 * 1024) {
      rejected.push({ name: file.name, reason: "size" });
    } else if (files.some((f) => sameFile(f, file))) {
      continue;
    } else if (files.length >= MAX_FILES_PER_UPLOAD) {
      rejected.push({ name: file.name, reason: "count" });
    } else {
      files.push(file);
    }
  }

  return { files, rejected };
}

/** One `files[]` part per file — never collapsed into a single value. */
export function attachmentForm(files: File[]): FormData {
  const form = new FormData();
  for (const file of files) form.append("files[]", file, file.name);
  return form;
}
