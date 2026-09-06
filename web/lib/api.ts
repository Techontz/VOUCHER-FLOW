/**
 * Typed client for the VouchFlow API.
 *
 * Holds the Sanctum token and the active language, and turns Laravel's error
 * shapes into something the forms can render field by field.
 */

export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8000/api";

const TOKEN_KEY = "vouchflow.token";
const LOCALE_KEY = "vouchflow.locale";

export type Locale = "en" | "sw";

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

export async function request<T = any>(path: string, options: RequestOptions = {}): Promise<T> {
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
