import type { Locale } from "./i18n";

export function money(amount: number, currency = "TZS"): string {
  const whole = Number.isInteger(amount);
  return `${currency} ${amount.toLocaleString("en-US", {
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: 2,
  })}`;
}

export function compactMoney(amount: number, currency = "TZS"): string {
  if (Math.abs(amount) >= 1_000_000) return `${currency} ${(amount / 1_000_000).toFixed(1)}M`;
  if (Math.abs(amount) >= 1_000) return `${currency} ${(amount / 1_000).toFixed(0)}K`;
  return money(amount, currency);
}

export function formatDate(value: string | null | undefined, locale: Locale = "en"): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

export function formatDateTime(value: string | null | undefined, locale: Locale = "en"): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return `${formatDate(value, locale)} · ${date.toLocaleTimeString(locale === "sw" ? "sw-TZ" : "en-GB", {
    hour: "2-digit",
    minute: "2-digit",
  })}`;
}

/** "2 hours ago" — used in notification and activity lists. */
export function relativeTime(value: string | null | undefined, locale: Locale = "en"): string {
  if (!value) return "—";
  const date = new Date(value);
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);

  const units: [number, Intl.RelativeTimeFormatUnit][] = [
    [60, "second"], [3600, "minute"], [86400, "hour"], [604800, "day"], [2629800, "week"],
    [31557600, "month"], [Infinity, "year"],
  ];
  const divisors = [1, 60, 3600, 86400, 604800, 2629800, 31557600];

  const rtf = new Intl.RelativeTimeFormat(locale === "sw" ? "sw" : "en", { numeric: "auto" });

  for (let i = 0; i < units.length; i++) {
    if (Math.abs(seconds) < units[i][0]) {
      return rtf.format(-Math.round(seconds / divisors[i]), units[i][1]);
    }
  }
  return formatDate(value, locale);
}

export function dateInputValue(value?: string | null): string {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) return new Date().toISOString().slice(0, 10);
  return date.toISOString().slice(0, 10);
}

export function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
}

/** Groups a list by "Today", "Yesterday", "Earlier". */
export function groupByDay<T>(items: T[], getDate: (item: T) => string | null): Array<{ key: string; items: T[] }> {
  const today = new Date().toDateString();
  const yesterday = new Date(Date.now() - 86_400_000).toDateString();
  const groups: Record<string, T[]> = { today: [], yesterday: [], earlier: [] };

  for (const item of items) {
    const raw = getDate(item);
    const day = raw ? new Date(raw).toDateString() : "";
    if (day === today) groups.today.push(item);
    else if (day === yesterday) groups.yesterday.push(item);
    else groups.earlier.push(item);
  }

  return (["today", "yesterday", "earlier"] as const)
    .filter((key) => groups[key].length > 0)
    .map((key) => ({ key, items: groups[key] }));
}

const STATUS_TAGS: Record<string, string> = {
  draft: "tag-neutral",
  in_review: "tag-outline",
  changes_requested: "tag-accent-2",
  approved: "tag-accent",
  rejected: "tag-accent-2",
  cancelled: "tag-neutral",
};

export function statusTag(status: string): string {
  return STATUS_TAGS[status] ?? "tag-neutral";
}

/** A person's display name, whether the API sent the person or just a name. */
export function personName(person: string | { name: string } | null | undefined): string | null {
  if (!person) return null;
  return typeof person === "string" ? person : person.name ?? null;
}
