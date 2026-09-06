"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api, ApiError, getLocale, getToken, setLocale as persistLocale, setToken } from "./api";
import { translate, type Locale, type MessageKey } from "./i18n";
import type { Company, User } from "./types";

type Theme = "light" | "dark";

export interface Toast {
  id: number;
  title: string;
  body?: string;
  kind: "ok" | "warn" | "bad";
}

interface AppState {
  user: User | null;
  company: Company | null;
  ready: boolean;
  locale: Locale;
  theme: Theme;
  unread: number;
  t: (key: MessageKey) => string;
  setLocale: (locale: Locale) => void;
  toggleTheme: () => void;
  signIn: (email: string, password: string) => Promise<User>;
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
  const [theme, setTheme] = useState<Theme>("light");
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
      if (data.user.theme) setTheme(data.user.theme);
      void refreshUnread();
    } catch {
      setToken(null);
      setUser(null);
      setCompany(null);
    } finally {
      setReady(true);
    }
  }, [refreshUnread]);

  useEffect(() => {
    setLocaleState(getLocale());
    void refresh();
  }, [refresh]);

  // Reflect the theme on the document so the CSS token overrides apply.
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

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
      const next = current === "light" ? "dark" : "light";
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
    if (nextUser.theme) setTheme(nextUser.theme);
    void refreshUnread();
  }, [refreshUnread]);

  const signIn = useCallback(async (email: string, password: string) => {
    const data = await api.post<{ token: string; user: User; company: Company | null }>("/auth/login", {
      email,
      password,
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
    user, company, ready, locale, theme, unread, t,
    setLocale, toggleTheme, signIn, signOut, refresh, refreshUnread, applySession,
    toasts, toast, dismissToast, reportError,
  }), [
    user, company, ready, locale, theme, unread, t,
    setLocale, toggleTheme, signIn, signOut, refresh, refreshUnread, applySession,
    toasts, toast, dismissToast, reportError,
  ]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useApp(): AppState {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useApp must be used inside <AppProvider>");
  return ctx;
}
