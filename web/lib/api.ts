/**
 * Typed client for the VouchFlow API.
 *
 * Holds the token, the active language and the chosen appearance, and turns the
 * API's error shapes into something the forms can render field by field.
 *
 * PHASE 1 — the transport underneath is an in-browser mock (`lib/mock/`), not
 * HTTP. Every screen calls `api.get` / `api.post` / … exactly as it will against
 * Laravel, and the paths, verbs and payload shapes are the same. Setting
 * `NEXT_PUBLIC_API_MODE=live` switches the transport to `fetch` with no change
 * to a single component.
 */

import { handle, MockError } from "./mock/router";

/** `mock` (default) or `live`, which routes every call over HTTP to Laravel. */
export const API_MODE: "mock" | "live" =
  process.env.NEXT_PUBLIC_API_MODE === "live" ? "live" : "mock";

/** Where `php artisan serve` puts the API. Development convenience only. */
const DEV_FALLBACK = "http://127.0.0.1:8000/api";

const LOOPBACK = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:\d+)?/i;

/**
 * The API's base URL, including the `/api` prefix.
 *
 * Call sites pass paths like `/auth/login`, so the base must carry the prefix;
 * a trailing slash is trimmed so `.../api` and `.../api/` behave the same.
 *
 * The checks below run when the module is evaluated, which during `next build`
 * means they run while pages are being prerendered — so a deployment that is
 * misconfigured fails the build instead of shipping a bundle that quietly
 * dials the visitor's own machine. `NEXT_PUBLIC_*` values are inlined at build
 * time, which is exactly why this cannot be a runtime check.
 *
 * NODE_ENV alone is the wrong signal: `npm run build` sets it to production on
 * a laptop too, where pointing at 127.0.0.1 is correct. So a loopback URL is
 * only fatal where it could actually reach users — a real deployment, which
 * Vercel marks with VERCEL_ENV=production.
 */
function resolveApiUrl(): string {
  const configured = process.env.NEXT_PUBLIC_API_URL?.trim().replace(/\/+$/, "");

  // In mock mode nothing is ever dialled, so the value is inert.
  if (API_MODE === "mock") return configured || DEV_FALLBACK;

  if (!configured) {
    if (process.env.NODE_ENV !== "production") return DEV_FALLBACK;

    throw new Error(
      "NEXT_PUBLIC_API_URL is not set, but NEXT_PUBLIC_API_MODE=live. A production " +
      "build would fall back to " + DEV_FALLBACK + " and every visitor's browser " +
      "would try to reach its own machine. Set NEXT_PUBLIC_API_URL to the API's " +
      "base URL including /api — e.g. https://api.example.com/api.",
    );
  }

  if (!/^https?:\/\//i.test(configured)) {
    throw new Error(
      `NEXT_PUBLIC_API_URL must be an absolute http(s) URL, got "${configured}".`,
    );
  }

  const isLoopback = LOOPBACK.test(configured);

  // A real deployment. Anything that cannot work from a visitor's browser is
  // a build failure here rather than a blank screen later.
  if (process.env.VERCEL_ENV === "production") {
    if (isLoopback) {
      throw new Error(
        `NEXT_PUBLIC_API_URL is ${configured} in a Vercel production build. That ` +
        "address only exists on the machine that opens the page. Point it at the " +
        "deployed API, including /api.",
      );
    }

    if (!configured.toLowerCase().startsWith("https://")) {
      throw new Error(
        `NEXT_PUBLIC_API_URL must use https in production, got "${configured}". A ` +
        "browser on an https page blocks plain-http requests as mixed content.",
      );
    }
  }

  // Plain http to a real host cannot work from an https page anywhere.
  if (process.env.NODE_ENV === "production" && !isLoopback
      && !configured.toLowerCase().startsWith("https://")) {
    throw new Error(
      `NEXT_PUBLIC_API_URL must use https, got "${configured}". A browser on an ` +
      "https page blocks plain-http requests as mixed content.",
    );
  }

  // Legitimate on a laptop, ruinous on a deployment that Vercel has not
  // labelled. Worth saying out loud in the build log either way.
  if (process.env.NODE_ENV === "production" && isLoopback) {
    console.warn(
      `[vouchflow] Building with NEXT_PUBLIC_API_URL=${configured}. Correct for a ` +
      "local production build; wrong for anything you deploy.",
    );
  }

  // Every call site passes a path beginning with a slash, so a base with no
  // path of its own is almost certainly missing the /api prefix.
  if (new URL(configured).pathname === "/") {
    console.warn(
      `[vouchflow] NEXT_PUBLIC_API_URL=${configured} has no path. The base URL is ` +
      "expected to include the API prefix, e.g. https://api.example.com/api.",
    );
  }

  return configured;
}

export const API_URL = resolveApiUrl();

const TOKEN_KEY = "vouchflow.token";
const LOCALE_KEY = "vouchflow.locale";
const THEME_KEY = "vouchflow.theme";

export type Locale = "en" | "sw";
export type Theme = "light" | "dark";

/** Dark is the product's default appearance; light is a stored preference. */
export const DEFAULT_THEME: Theme = "dark";

export class ApiError extends Error {
  status: number;
  errors: Record<string, string[]>;
  code?: string;

  constructor(status: number, message: string, errors: Record<string, string[]> = {}, code?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.errors = errors;
    this.code = code;
  }

  /** First message for a field, for inline form errors. */
  field(name: string): string | undefined {
    return this.errors[name]?.[0];
  }
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function setToken(token: string | null) {
  if (typeof window === "undefined") return;
  try {
    if (token) window.localStorage.setItem(TOKEN_KEY, token);
    else window.localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* private browsing — the session simply will not persist */
  }
}

export function getLocale(): Locale {
  if (typeof window === "undefined") return "en";
  try {
    return (window.localStorage.getItem(LOCALE_KEY) as Locale) || "en";
  } catch {
    return "en";
  }
}

export function setLocale(locale: Locale) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LOCALE_KEY, locale);
  } catch {
    /* ignore */
  }
}

/**
 * The appearance chosen on this device. Stored separately from the account so a
 * visitor who has not signed in still gets — and keeps — their choice, and so
 * the pre-paint script in the root layout can read it synchronously.
 */
export function getTheme(): Theme {
  if (typeof window === "undefined") return DEFAULT_THEME;
  try {
    const stored = window.localStorage.getItem(THEME_KEY);
    return stored === "light" || stored === "dark" ? stored : DEFAULT_THEME;
  } catch {
    return DEFAULT_THEME;
  }
}

export function setTheme(theme: Theme) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(THEME_KEY, theme);
  } catch {
    /* private browsing — the choice simply will not outlive the tab */
  }
}

type Query = Record<string, string | number | boolean | null | undefined>;

export interface RequestOptions {
  method?: string;
  body?: unknown;
  query?: Query;
  /** FormData for uploads; Content-Type is then left to the browser. */
  form?: FormData;
  signal?: AbortSignal;
}

function buildUrl(path: string, query?: Query): string {
  const url = new URL(API_URL.replace(/\/$/, "") + path, "http://placeholder");
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null && value !== "") {
        url.searchParams.set(key, String(value));
      }
    }
  }
  const full = API_URL.replace(/\/$/, "") + path;
  const qs = url.searchParams.toString();
  return qs ? `${full}?${qs}` : full;
}

async function parse(response: Response) {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { message: text };
  }
}

/** Network-shaped latency, so loading states are exercised the way they will be. */
const settle = () => new Promise((r) => setTimeout(r, 90 + Math.random() * 160));

/** Reads a FormData body into the plain object the mock router expects. */
function formToBody(form: FormData): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  form.forEach((value, key) => {
    body[key] = value instanceof File
      ? { name: value.name, size: value.size, type: value.type }
      : value;
  });
  return body;
}

async function mockRequest<T>(path: string, options: RequestOptions): Promise<T> {
  await settle();

  const [cleanPath, inlineQuery] = path.split("?");
  const query: Record<string, string> = {};
  new URLSearchParams(inlineQuery ?? "").forEach((v, k) => { query[k] = v; });
  if (options.query) {
    for (const [key, value] of Object.entries(options.query)) {
      if (value !== undefined && value !== null && value !== "") query[key] = String(value);
    }
  }

  const body = options.form
    ? formToBody(options.form)
    : ((options.body as Record<string, unknown>) ?? {});
  const method = options.method ?? (options.body || options.form ? "POST" : "GET");

  try {
    return handle(method, cleanPath, body, query, getToken()) as T;
  } catch (error) {
    if (error instanceof MockError) {
      if (error.status === 401 && typeof window !== "undefined") {
        setToken(null);
        if (!window.location.pathname.startsWith("/login")) window.location.href = "/login";
      }
      throw new ApiError(error.status, error.message, error.errors, error.code);
    }
    throw error;
  }
}

export async function request<T = any>(path: string, options: RequestOptions = {}): Promise<T> {
  if (API_MODE === "mock") return mockRequest<T>(path, options);

  const headers: Record<string, string> = {
    Accept: "application/json",
    "X-Locale": getLocale(),
  };

  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;

  let body: BodyInit | undefined;
  if (options.form) {
    body = options.form;
  } else if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(options.body);
  }

  const response = await fetch(buildUrl(path, options.query), {
    method: options.method ?? (body ? "POST" : "GET"),
    headers,
    body,
    signal: options.signal,
    cache: "no-store",
  });

  if (response.status === 204) return null as T;

  const payload = await parse(response);

  if (!response.ok) {
    // A revoked or expired token should drop the session rather than loop.
    if (response.status === 401 && typeof window !== "undefined") {
      setToken(null);
      if (!window.location.pathname.startsWith("/login")) {
        window.location.href = "/login";
      }
    }

    throw new ApiError(
      response.status,
      payload?.message || `Request failed (${response.status})`,
      payload?.errors ?? {},
      payload?.code,
    );
  }

  return payload as T;
}

/** Fetches a file (PDF, spreadsheet) as a blob, carrying auth headers. */
export async function download(path: string, query?: Query): Promise<Blob> {
  if (API_MODE === "mock") {
    throw new ApiError(
      501,
      "File export is generated server-side and arrives with the backend. Use Print to produce a PDF from this page in the meantime.",
      {},
      "phase_one_frontend_only",
    );
  }

  const token = getToken();
  const response = await fetch(buildUrl(path, query), {
    headers: {
      Accept: "application/octet-stream",
      "X-Locale": getLocale(),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    cache: "no-store",
  });

  if (!response.ok) {
    const payload = await parse(response);
    throw new ApiError(response.status, payload?.message || "Download failed", payload?.errors ?? {});
  }

  return response.blob();
}

/** Triggers a browser download for a blob returned by the API. */
export function saveBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

/** Opens a blob in a new tab and invokes the print dialog once it has loaded. */
export function printBlob(blob: Blob) {
  const url = URL.createObjectURL(blob);
  const frame = document.createElement("iframe");
  frame.style.position = "fixed";
  frame.style.right = "0";
  frame.style.bottom = "0";
  frame.style.width = "0";
  frame.style.height = "0";
  frame.style.border = "0";
  frame.src = url;
  frame.onload = () => {
    try {
      frame.contentWindow?.focus();
      frame.contentWindow?.print();
    } catch {
      window.open(url, "_blank");
    }
  };
  document.body.appendChild(frame);
  // Chromium keeps the print dialog alive after the frame is detached.
  window.setTimeout(() => {
    frame.remove();
    URL.revokeObjectURL(url);
  }, 60_000);
}

export const api = {
  get: <T = any>(path: string, query?: Query) => request<T>(path, { method: "GET", query }),
  post: <T = any>(path: string, body?: unknown, query?: Query) => request<T>(path, { method: "POST", body, query }),
  put: <T = any>(path: string, body?: unknown) => request<T>(path, { method: "PUT", body }),
  patch: <T = any>(path: string, body?: unknown) => request<T>(path, { method: "PATCH", body }),
  delete: <T = any>(path: string) => request<T>(path, { method: "DELETE" }),
  upload: <T = any>(path: string, form: FormData) => request<T>(path, { method: "POST", form }),
};
