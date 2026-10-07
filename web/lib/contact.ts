/**
 * VouchFlow's own addresses. `info` is for general enquiries (sales, plans,
 * partnerships); `support` is for urgent help and customer care.
 */
export const CONTACT = {
  info: "info@vouchflow.co.tz",
  support: "support@vouchflow.co.tz",
} as const;

export const mailto = (address: string, subject?: string) =>
  `mailto:${address}${subject ? `?subject=${encodeURIComponent(subject)}` : ""}`;
