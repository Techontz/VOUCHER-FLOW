import type { Role } from "./types";
import type { MessageKey } from "./i18n";

export interface NavItem {
  href: string;
  label: MessageKey;
  /** A one-word label for the mobile tab bar, where two lines do not fit. */
  short?: MessageKey;
  icon: string;
  badge?: "pending" | "payments" | "notifications";
}

/**
 * Navigation per role, following the v2 design's NAV map.
 *
 * An employee is deliberately given no route into other people's data, and a
 * cashier lands on the payment queue rather than a dashboard — the menu matches
 * what the API will actually return for that role.
 */
const NAV: Record<Role, NavItem[]> = {
  employee: [
    { href: "/dashboard", label: "home", icon: "ph-house" },
    { href: "/vouchers", label: "myVouchers", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
  hod: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "deptRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  ceo: [
    { href: "/dashboard", label: "finalApprovals", short: "approvals", icon: "ph-seal-check", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  cashier: [
    { href: "/dashboard", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
  finance: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  director: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  company_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four" },
    { href: "/vouchers", label: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/approvals", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/employees", label: "employees", icon: "ph-users-three" },
    { href: "/departments", label: "departments", icon: "ph-buildings" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/subscription", label: "subscription", icon: "ph-crown-simple" },
    { href: "/branding", label: "branding", icon: "ph-palette" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-scroll" },
    { href: "/settings", label: "settings", icon: "ph-gear" },
  ],
  super_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four" },
    { href: "/platform/companies", label: "companies", short: "companies", icon: "ph-buildings" },
    { href: "/platform/plans", label: "plansSubs", short: "plan", icon: "ph-crown-simple" },
    { href: "/platform/payments", label: "payments", short: "payments", icon: "ph-credit-card" },
    { href: "/platform/users", label: "users", short: "users", icon: "ph-users-three" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-scroll" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
};

export function navFor(role: Role): NavItem[] {
  return NAV[role] ?? NAV.employee;
}

/** The five slots on the mobile tab bar; creating a voucher is the FAB instead. */
export function mobileNavFor(role: Role): NavItem[] {
  const items = navFor(role);
  const home = items[0];
  const rest = items.filter((i) => i !== home && i.href !== "/vouchers/new");
  return [home, ...rest].slice(0, 5);
}

export function isAdminRole(role: Role): boolean {
  return role === "company_admin" || role === "super_admin";
}

/** Roles whose step in a workflow can release money. */
export function isPayingRole(role: Role): boolean {
  return role === "cashier" || role === "finance";
}
