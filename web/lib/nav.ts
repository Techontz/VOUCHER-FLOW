import type { Role } from "./types";
import type { MessageKey } from "./i18n";

export interface NavItem {
  href: string;
  label: MessageKey;
  icon: string;
  badge?: "pending" | "notifications";
}

/**
 * Navigation per role. An employee is deliberately given no route into other
 * people's data — the menu matches what the API will actually return.
 */
const NAV: Record<Role, NavItem[]> = {
  employee: [
    { href: "/dashboard", label: "home", icon: "ph-house" },
    { href: "/vouchers", label: "myVouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
  hod: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "deptRegister", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", icon: "ph-signature" },
  ],
  manager: [
    { href: "/dashboard", label: "finalApprovals", icon: "ph-seal-check", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", icon: "ph-signature" },
  ],
  finance: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", icon: "ph-signature" },
  ],
  director: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "voucherRegister", icon: "ph-receipt" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", icon: "ph-signature" },
  ],
  company_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four" },
    { href: "/vouchers", label: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/approvals", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/employees", label: "employees", icon: "ph-users-three" },
    { href: "/departments", label: "departments", icon: "ph-buildings" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/subscription", label: "subscription", icon: "ph-crown-simple" },
    { href: "/branding", label: "branding", icon: "ph-palette" },
    { href: "/audit", label: "auditLogs", icon: "ph-scroll" },
    { href: "/settings", label: "settings", icon: "ph-gear" },
  ],
  super_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four" },
    { href: "/platform/companies", label: "companies", icon: "ph-buildings" },
    { href: "/platform/plans", label: "plansSubs", icon: "ph-crown-simple" },
    { href: "/platform/payments", label: "payments", icon: "ph-credit-card" },
    { href: "/platform/users", label: "users", icon: "ph-users-three" },
    { href: "/audit", label: "auditLogs", icon: "ph-scroll" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
};

export function navFor(role: Role): NavItem[] {
  return NAV[role] ?? NAV.employee;
}

/** The five slots on the mobile tab bar. */
export function mobileNavFor(role: Role): NavItem[] {
  const items = navFor(role);
  const home = items[0];
  const rest = items.filter((i) => i !== home && i.href !== "/vouchers/new");
  return [home, ...rest].slice(0, 5);
}

export function isAdminRole(role: Role): boolean {
  return role === "company_admin" || role === "super_admin";
}
