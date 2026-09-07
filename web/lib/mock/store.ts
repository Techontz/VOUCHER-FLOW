/**
 * In-memory dataset for the Phase 1 prototype, mirrored into localStorage so a
 * demo survives a reload. Nothing here talks to a network.
 */

import { buildSeed, type MockDataset, type MockUser } from "./seed";

const KEY = "vouchflow.mock.v2";
const SESSION_KEY = "vouchflow.mock.session";

let db: MockDataset | null = null;

function load(): MockDataset {
  if (db) return db;

  if (typeof window !== "undefined") {
    try {
      const raw = window.localStorage.getItem(KEY);
      if (raw) {
        db = JSON.parse(raw) as MockDataset;
        return db;
      }
    } catch {
      /* corrupt or unavailable storage — fall through to a fresh seed */
    }
  }

  db = buildSeed();
  persist();
  return db;
}

function persist() {
  if (typeof window === "undefined" || !db) return;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(db));
  } catch {
    /* private browsing — the demo simply will not survive a reload */
  }
}

export const store = {
  get db(): MockDataset {
    return load();
  },

  /** Applies a mutation and writes it back. */
  mutate<T>(fn: (db: MockDataset) => T): T {
    const data = load();
    const result = fn(data);
    persist();
    return result;
  },

  nextId(key: keyof MockDataset["sequences"]): number {
    const data = load();
    const id = data.sequences[key];
    data.sequences[key] = id + 1;
    return id;
  },

  /** Wipes the demo back to its opening state. */
  reset(): MockDataset {
    db = buildSeed();
    persist();
    return db;
  },

  /* ---------------------------------------------------------- session ---- */

  signIn(userId: number): string {
    const token = `mock-${userId}-${Date.now().toString(36)}`;
    if (typeof window !== "undefined") {
      try {
        window.localStorage.setItem(SESSION_KEY, String(userId));
      } catch { /* ignore */ }
    }
    return token;
  },

  signOut() {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.removeItem(SESSION_KEY);
    } catch { /* ignore */ }
  },

  /** The signed-in user, resolved from the token the client holds. */
  currentUser(token: string | null): MockUser | null {
    const data = load();

    const fromToken = token?.startsWith("mock-") ? Number(token.split("-")[1]) : NaN;
    if (!Number.isNaN(fromToken)) {
      return data.users.find((u) => u.id === fromToken) ?? null;
    }

    if (typeof window !== "undefined") {
      try {
        const stored = window.localStorage.getItem(SESSION_KEY);
        if (stored) return data.users.find((u) => u.id === Number(stored)) ?? null;
      } catch { /* ignore */ }
    }
    return null;
  },
};
