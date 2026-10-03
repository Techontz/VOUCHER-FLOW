/**
 * Photos taken on a phone, made fit to upload.
 *
 * A phone camera writes 3–12 MB JPEGs (or HEIC on an iPhone). The API caps an
 * avatar at 2 MB and an attachment at 10 MB, and the web server in front of it
 * may cap a request lower still — a body that is too large never reaches
 * Laravel, so the browser sees a dropped connection rather than a message. So
 * images are re-encoded here, in the browser, as JPEG at a sensible size before
 * they leave the device. PDFs, and images already small enough, go untouched.
 *
 * Decoding happens through an <img>, which applies the photo's EXIF rotation,
 * so a portrait shot stays upright once re-encoded. A format this browser
 * cannot decode (HEIC outside Safari) is uploaded as it was picked.
 */

import { ApiError } from "./api";

export interface ImagePrepOptions {
  /** The longest side, in pixels, of the uploaded image. */
  maxSide: number;
  /** JPEG quality, 0–1. */
  quality: number;
  /** A JPEG or PNG under this many bytes is uploaded unchanged. */
  keepBelowBytes: number;
  /** Re-encode even an image that is already small (avatars: always JPEG). */
  always?: boolean;
}

/** Supporting documents and signed acknowledgements: legible, well under 10 MB. */
export const DOCUMENT_IMAGE: ImagePrepOptions = { maxSide: 2000, quality: 0.85, keepBelowBytes: 1.5 * 1024 * 1024 };

/** Profile photos: the server takes an `image` of at most 2 MB. */
export const AVATAR_IMAGE: ImagePrepOptions = { maxSide: 1024, quality: 0.85, keepBelowBytes: 0, always: true };

const IMAGE_EXTENSION = /\.(jpe?g|png|webp|heic|heif|bmp|avif)$/i;

function isImage(file: File): boolean {
  const type = file.type.toLowerCase();
  if (type === "image/gif" || type === "image/svg+xml") return false; // animation / vector: leave alone
  return type.startsWith("image/") || (!type && IMAGE_EXTENSION.test(file.name));
}

function decode(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.decoding = "async";
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("decode")); };
    img.src = url;
  });
}

/**
 * Returns the file to upload in place of `file`: a downscaled JPEG when it is a
 * photo worth shrinking and this browser can read it, otherwise `file` itself.
 * Never throws.
 */
export async function prepareImage(file: File, options: ImagePrepOptions = DOCUMENT_IMAGE): Promise<File> {
  if (typeof document === "undefined" || !isImage(file)) return file;

  const type = file.type.toLowerCase();
  const alreadyFine = type === "image/jpeg" || type === "image/png";
  if (!options.always && alreadyFine && file.size < options.keepBelowBytes) return file;

  try {
    const img = await decode(file);
    const width = img.naturalWidth;
    const height = img.naturalHeight;
    if (!width || !height) return file;

    const scale = Math.min(1, options.maxSide / Math.max(width, height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;

    // JPEG has no transparency: a transparent PNG would otherwise turn black.
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", options.quality));
    if (!blob) return file;

    // Nothing gained: an accepted format that was neither shrunk nor made smaller.
    const accepted = alreadyFine || type === "image/webp";
    if (!options.always && accepted && scale === 1 && blob.size >= file.size) return file;

    const base = file.name.replace(/\.[^./\\]+$/, "") || "photo";
    return new File([blob], `${base}.jpg`, { type: "image/jpeg", lastModified: file.lastModified });
  } catch {
    return file;
  }
}

/** `prepareImage` over a list, preserving order. */
export function prepareImages(files: File[], options: ImagePrepOptions = DOCUMENT_IMAGE): Promise<File[]> {
  return Promise.all(files.map((file) => prepareImage(file, options)));
}

type Translate = (key: "uploadTooLargeServer" | "uploadNoResponse") => string;

/**
 * What to tell someone whose upload failed — the server's own words where
 * there are some, so the real cause is visible rather than a generic line.
 */
export function describeUploadError(err: unknown, t: Translate): string {
  if (err instanceof ApiError) {
    if (err.status === 413) return `${t("uploadTooLargeServer")} (HTTP 413)`;
    const field = Object.values(err.errors)[0]?.[0];
    // A proxy's HTML error page is not a message anyone should read.
    const message = err.message && !/^\s*</.test(err.message) ? err.message : "";
    const text = field ?? message;
    return text ? `${text} (HTTP ${err.status})` : `HTTP ${err.status}`;
  }
  // fetch rejects without a status when the connection drops or the reply
  // carries no CORS headers — which is what an over-size body rejected by the
  // web server in front of the API looks like from the page.
  const detail = err instanceof Error && err.message ? ` (${err.message})` : "";
  return `${t("uploadNoResponse")}${detail}`;
}
