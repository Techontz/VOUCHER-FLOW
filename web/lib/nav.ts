import type { Role } from "./types";
import type { MessageKey } from "./i18n";

export type NavGroup =
  | "overview" | "vouchers" | "organisation" | "finance" | "administration"
  | "workspace" | "insights" | "account"
  | "platform" | "system";

export interface NavItem {
  /** A route, optionally with the #section it opens (Settings is hash-addressed). */
  href: string;
  label: MessageKey;
  /** A one-word label for the mobile tab bar, where two lines do not fit. */
  short?: MessageKey;
  icon: string;
  group: NavGroup;
  badge?: "pending" | "payments" | "notifications";
}

export const NAV_GROUP_LABEL: Record<NavGroup, MessageKey> = {
  overview: "overview",
  vouchers: "vouchers",
  organisation: "navOrganisation",
  finance: "navFinance",
  administration: "navAdministration",
  workspace: "navWorkspace",
  insights: "navInsights",
  account: "navAccount",
  platform: "navPlatform",
  system: "navSystem",
};

/* Account pages every signed-in role has. */
const account = (profileLabel: MessageKey, icon: string): NavItem[] => [
  { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications", group: "account" },
  { href: "/profile", label: profileLabel, short: "profile", icon, group: "account" },
];

/**
 * Navigation per role.
 *
 * An employee is deliberately given no route into other people's data, and a
 * cashier lands on the payment queue rather than a dashboard — the menu matches
 * what the API will actually return for that role. A manager acts for the
 * departments they manage, as a head of department does for theirs.
 */
const NAV: Record<Role, NavItem[]> = {
  employee: [
    { href: "/dashboard", label: "home", icon: "ph-house", group: "workspace" },
    { href: "/vouchers", label: "myVouchers", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "workspace" },
    ...account("profile", "ph-user-circle"),
  ],
  hod: [
    { href: "/dashboard", label: "approvals", icon: "ph-seal-check", badge: "pending", group: "workspace" },
    { href: "/vouchers", label: "deptRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profileSig", "ph-signature"),
  ],
  manager: [
    { href: "/dashboard", label: "approvals", icon: "ph-seal-check", badge: "pending", group: "workspace" },
    { href: "/vouchers", label: "deptRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profileSig", "ph-signature"),
  ],
  ceo: [
    { href: "/dashboard", label: "finalApprovals", short: "approvals", icon: "ph-seal-check", badge: "pending", group: "workspace" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profileSig", "ph-signature"),
  ],
  cashier: [
    { href: "/dashboard", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments", group: "workspace" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profile", "ph-user-circle"),
  ],
  finance: [
    { href: "/dashboard", label: "approvals", icon: "ph-seal-check", badge: "pending", group: "workspace" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments", group: "workspace" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profileSig", "ph-signature"),
  ],
  director: [
    { href: "/dashboard", label: "approvals", icon: "ph-seal-check", badge: "pending", group: "workspace" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt", group: "workspace" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "insights" },
    ...account("profileSig", "ph-signature"),
  ],
  company_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four", group: "overview" },
    { href: "/approvals", label: "approvals", icon: "ph-seal-check", badge: "pending", group: "overview" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments", group: "overview" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt", group: "vouchers" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle", group: "vouchers" },
    { href: "/employees", label: "employees", icon: "ph-users", group: "organisation" },
    { href: "/departments", label: "departments", icon: "ph-buildings", group: "organisation" },
    { href: "/roles", label: "rolesAccess", icon: "ph-shield-check", group: "organisation" },
    { href: "/settings#workflow", label: "approvalWorkflow", icon: "ph-flow-arrow", group: "organisation" },
    { href: "/reports", label: "reports", icon: "ph-chart-bar", group: "finance" },
    { href: "/branding", label: "branding", icon: "ph-palette", group: "administration" },
    { href: "/subscription", label: "subscription", icon: "ph-credit-card", group: "administration" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-clock-counter-clockwise", group: "administration" },
    { href: "/settings#company", label: "settings", icon: "ph-gear-six", group: "administration" },
    ...account("profile", "ph-user-circle"),
  ],
  super_admin: [
    { href: "/dashboard", label: "overview", icon: "ph-squares-four", group: "platform" },
    { href: "/platform/companies", label: "companies", short: "companies", icon: "ph-buildings", group: "platform" },
    { href: "/platform/plans", label: "plansSubs", short: "plan", icon: "ph-stack", group: "platform" },
    { href: "/platform/payments", label: "payments", short: "payments", icon: "ph-receipt", group: "platform" },
    { href: "/platform/users", label: "users", short: "users", icon: "ph-users", group: "platform" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-clock-counter-clockwise", group: "system" },
    ...account("profile", "ph-user-circle"),
  ],
};

export function navFor(role: Role): NavItem[] {
  return NAV[role] ?? NAV.employee;
}

/** Splits "/settings#workflow" into its route and its section. */
export function splitHref(href: string): { path: string; hash: string } {
  const [path, hash = ""] = href.split("#");
  return { path, hash };
}

/**
 * The five slots on the mobile tab bar: home, the role's working lists,
 * alerts, and the profile last. Creating a voucher is the floating button.
 */
export function mobileNavFor(role: Role): NavItem[] {
  const items = navFor(role).filter((i) => !i.href.includes("#"));
  const home = items[0];
  const profile = items.find((i) => i.href === "/profile");
  const alerts = items.find((i) => i.href === "/notifications");
  const work = items.filter((i) => i !== home && i !== profile && i !== alerts && i.href !== "/vouchers/new");
  const middle = work.slice(0, alerts ? 2 : 3);
  return [home, ...middle, ...(alerts ? [alerts] : []), ...(profile ? [profile] : [])].slice(0, 5);
}

export function isAdminRole(role: Role): boolean {
  return role === "company_admin" || role === "super_admin";
}

/** Roles whose step in a workflow can release money. */
export function isPayingRole(role: Role): boolean {
  return role === "cashier" || role === "finance";
}
