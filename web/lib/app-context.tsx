"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api, ApiError, COMPANY_PENDING_EVENT, DEFAULT_THEME, getLocale, getTheme, getToken,
  setLocale as persistLocale, setTheme as persistTheme, setToken,
} from "./api";
import { translate, type Locale, type MessageKey } from "./i18n";
import type { Theme } from "./api";
import type { Company, LoginChallenge, User } from "./types";

/**
 * What a correct password leads to: straight in (two-step sign-in is off on
 * the server) or a one-time code still to enter.
 */
export type SignInResult =
  | { status: "signed_in"; user: User }
  | { status: "verify"; challenge: LoginChallenge };

export interface Toast {
  id: number;
  title: string;
  body?: string;
  kind: "ok" | "warn" | "bad";
}

interface AppState {
  user: User | null;
  company: Company | null;
  /**
   * The signed-in company registered itself and is waiting for a platform
   * administrator to approve it. The shell shows the awaiting-approval screen
   * instead of the product. Never true for a super admin.
   */
  companyPending: boolean;
  ready: boolean;
  locale: Locale;
  theme: Theme;
  unread: number;
  t: (key: MessageKey) => string;
  setLocale: (locale: Locale) => void;
  toggleTheme: () => void;
  signIn: (email: string, password: string) => Promise<SignInResult>;
  /** Completes a two-step sign-in with the emailed or texted code. */
  verifyLogin: (challenge: string, code: string) => Promise<User>;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
  refreshUnread: () => Promise<void>;
  applySession: (token: string, user: User, company: Company | null) => void;
  toasts: Toast[];
  toast: (title: string, body?: string, kind?: Toast["kind"]) => void;
  dismissToast: (id: number) => void;
  /** Surfaces an API failure as a toast, using the server's own wording. */
  reportError: (error: unknown, fallback?: string) => void;
}

const Ctx = createContext<AppState | null>(null);

export function AppProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [company, setCompany] = useState<Company | null>(null);
  const [ready, setReady] = useState(false);
  const [locale, setLocaleState] = useState<Locale>("en");
  const [theme, setTheme] = useState<Theme>(DEFAULT_THEME);
  const [unread, setUnread] = useState(0);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  const t = useCallback((key: MessageKey) => translate(key, locale), [locale]);

  const dismissToast = useCallback((id: number) => {
    setToasts((current) => current.filter((item) => item.id !== id));
  }, []);

  const toast = useCallback((title: string, body?: string, kind: Toast["kind"] = "ok") => {
    const id = ++toastId.current;
    setToasts((current) => [...current, { id, title, body, kind }]);
    window.setTimeout(() => dismissToast(id), 4200);
  }, [dismissToast]);

  const reportError = useCallback((error: unknown, fallback = "Something went wrong") => {
    if (error instanceof ApiError) {
      const first = Object.values(error.errors)[0]?.[0];
      toast(error.message || fallback, first && first !== error.message ? first : undefined, "bad");
      return;
    }
    toast(fallback, error instanceof Error ? error.message : undefined, "bad");
  }, [toast]);

  /** Sets the appearance and remembers it on this device. */
  const applyTheme = useCallback((next: Theme) => {
    setTheme(next);
    persistTheme(next);
  }, []);

  const refreshUnread = useCallback(async () => {
    if (!getToken()) return;
    try {
      const data = await api.get<{ unread_count: number }>("/notifications/unread-count");
      setUnread(data.unread_count ?? 0);
    } catch {
      /* a failed badge poll should never surface to the user */
    }
  }, []);

  const refresh = useCallback(async () => {
    if (!getToken()) {
      setUser(null);
      setCompany(null);
      setReady(true);
      return;
    }
    try {
      const data = await api.get<{ user: User; company: Company | null }>("/auth/me");
      setUser(data.user);
      setCompany(data.company);
      if (data.user.locale) {
        setLocaleState(data.user.locale);
        persistLocale(data.user.locale);
      }
      // The account's saved preference wins once we know who this is.
      if (data.user.theme) applyTheme(data.user.theme);
      void refreshUnread();
    } catch {
      setToken(null);
      setUser(null);
      setCompany(null);
    } finally {
      setReady(true);
    }
  }, [refreshUnread, applyTheme]);

  // Read the device's stored preferences after mount, not during render: the
  // server has no localStorage, so seeding state from it up front would render
  // a different tree than it hydrates. The inline script in the root layout has
  // already painted the right theme, so this only catches React up.
  useEffect(() => {
    /* eslint-disable react-hooks/set-state-in-effect */
    setLocaleState(getLocale());
    setTheme(getTheme());
    /* eslint-enable react-hooks/set-state-in-effect */
    void refresh();
  }, [refresh]);

  // Reflect the theme on the document so the CSS token overrides apply.
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  // The company's interface palette. Remembered on the device so the pre-paint
  // script can apply it before the first frame; a signed-out page keeps the
  // last value, which only the signed-in shell reads.
  const colorTheme = company?.color_theme;
  useEffect(() => {
    if (!colorTheme) return;
    document.documentElement.dataset.accent = colorTheme;
    try {
      window.localStorage.setItem("vouchflow.accent", colorTheme);
    } catch {
      /* private browsing — the palette arrives with the company instead */
    }
  }, [colorTheme]);

  // Any call refused with 403 company_pending means the company is (again)
  // awaiting approval, whatever /auth/me said earlier: show the gate.
  useEffect(() => {
    const onPending = () => setCompany((current) =>
      current && current.status !== "pending" ? { ...current, status: "pending", is_usable: false } : current);
    window.addEventListener(COMPANY_PENDING_EVENT, onPending);
    return () => window.removeEventListener(COMPANY_PENDING_EVENT, onPending);
  }, []);

  const companyPending = !!user && user.role !== "super_admin" && company?.status === "pending";

  // Keep the notification badge current while the tab is open.
  useEffect(() => {
    if (!user) return;
    const id = window.setInterval(refreshUnread, 45_000);
    return () => window.clearInterval(id);
  }, [user, refreshUnread]);

  const setLocale = useCallback((next: Locale) => {
    setLocaleState(next);
    persistLocale(next);
    if (getToken()) {
      void api.put("/profile", { locale: next }).catch(() => undefined);
    }
  }, []);

  const toggleTheme = useCallback(() => {
    setTheme((current) => {
      const next: Theme = current === "light" ? "dark" : "light";
      // Persist on the device first, so the choice survives a signed-out reload,
      // then mirror it onto the account when there is one.
      persistTheme(next);
      if (getToken()) void api.put("/profile", { theme: next }).catch(() => undefined);
      return next;
    });
  }, []);

  const applySession = useCallback((token: string, nextUser: User, nextCompany: Company | null) => {
    setToken(token);
    setUser(nextUser);
    setCompany(nextCompany);
    setReady(true);
    if (nextUser.locale) {
      setLocaleState(nextUser.locale);
      persistLocale(nextUser.locale);
    }
    if (nextUser.theme) applyTheme(nextUser.theme);
    void refreshUnread();
  }, [refreshUnread, applyTheme]);

  const signIn = useCallback(async (email: string, password: string) => {
    const data = await api.post<{ token: string; user: User; company: Company | null } | LoginChallenge>("/auth/login", {
      email,
      password,
      device_name: "web",
    });
    if ("requires_verification" in data && data.requires_verification) {
      return { status: "verify", challenge: data } as SignInResult;
    }
    const session = data as { token: string; user: User; company: Company | null };
    applySession(session.token, session.user, session.company);
    return { status: "signed_in", user: session.user } as SignInResult;
  }, [applySession]);

  const verifyLogin = useCallback(async (challenge: string, code: string) => {
    const data = await api.post<{ token: string; user: User; company: Company | null }>("/auth/login/verify", {
      challenge,
      code,
      device_name: "web",
    });
    applySession(data.token, data.user, data.company);
    return data.user;
  }, [applySession]);

  const signOut = useCallback(async () => {
    try {
      await api.post("/auth/logout");
    } catch {
      /* the local session is cleared regardless */
    }
    setToken(null);
    setUser(null);
    setCompany(null);
    setUnread(0);
    router.push("/login");
  }, [router]);

  const value = useMemo<AppState>(() => ({
    user, company, companyPending, ready, locale, theme, unread, t,
    setLocale, toggleTheme, signIn, verifyLogin, signOut, refresh, refreshUnread, applySession,
    toasts, toast, dismissToast, reportError,
  }), [
    user, company, companyPending, ready, locale, theme, unread, t,
    setLocale, toggleTheme, signIn, verifyLogin, signOut, refresh, refreshUnread, applySession,
    toasts, toast, dismissToast, reportError,
  ]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useApp(): AppState {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useApp must be used inside <AppProvider>");
  return ctx;
}
