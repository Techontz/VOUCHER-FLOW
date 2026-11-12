"use client";

import { useMemo } from "react";
import { useApp } from "./app-context";
import { AREAS, areaOf, type Area, type AreaKey } from "./areas";
import { useErp } from "./erp";
import { erpEntryVisible, navFor, type NavItem } from "./nav";

/** Account pages live in the user menu, not in any app's menu. */
const ACCOUNT_HREFS = ["/notifications", "/profile"];

/** Billing and branding open inside Settings for a company administrator. */
export const SETTINGS_CHILDREN = ["/branding", "/subscription"];

/**
 * The menu entries this person may open, grouped by app, and the apps that
 * hold at least one of them, in launcher order. Read by the shell and the
 * launcher so both always agree on what someone can reach.
 */
export function useAreas() {
  const { user } = useApp();
  const { config } = useErp();

  return useMemo(() => {
    const items: NavItem[] = (user ? navFor(user.role) : []).filter((item) => {
      if (ACCOUNT_HREFS.includes(item.href)) return false;
      if (!erpEntryVisible(item, config)) return false;
      if (user?.role === "company_admin" && SETTINGS_CHILDREN.includes(item.href)) return false;
      return true;
    });

    const byArea = new Map<AreaKey, NavItem[]>();
    // The platform operator runs one app, the platform: their overview,
    // audit log and settings all belong to it, not to a company's apps.
    const platformOnly = user?.role === "super_admin";
    for (const item of items) {
      const key: AreaKey = platformOnly ? "platform" : areaOf(item);
      byArea.set(key, [...(byArea.get(key) ?? []), item]);
    }

    const open: Area[] = AREAS.filter((a) => byArea.has(a.key));

    // Modules this release ships that the subscription allows but the
    // company has not switched on yet: offered on the launcher to the people
    // who can switch them on. An app outside the subscription is not offered,
    // since switching it on would only be refused.
    const off: Area[] = config && config.permissions.includes("erp.configure")
      ? AREAS.filter((a) => a.module && !byArea.has(a.key)
        && config.live_modules.includes(a.module as never) && !config.modules.includes(a.module as never)
        && (!config.licensed_modules || config.licensed_modules.includes(a.module as never)))
      : [];

    return { items, byArea, open, off };
  }, [user, config]);
}
