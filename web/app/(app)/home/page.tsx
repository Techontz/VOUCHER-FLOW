"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { CATEGORIES, type Area, type AreaKey } from "@/lib/areas";
import { useErp } from "@/lib/erp";
import { useAreas } from "@/lib/use-areas";
import type { Voucher } from "@/lib/types";
import { AppIcon } from "@/components/app-icon";
import { Icon, LoadingBlock } from "@/components/ui";

/**
 * The launcher: every app this person can open, as an icon with its name,
 * grouped the way a business thinks about its work, with a count on any app
 * where something is waiting for them. Someone with one app skips straight in.
 */
export default function LauncherPage() {
  const { t, user, locale } = useApp();
  const { loading } = useErp();
  const router = useRouter();
  const { open, off, byArea } = useAreas();
  const [waiting, setWaiting] = useState<Partial<Record<AreaKey, number>>>({});
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (!user || user.role === "super_admin") return;
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setWaiting((w) => ({ ...w, vouchflow: r.data.length })))
      .catch(() => undefined);
  }, [user]);

  // One app is not a choice: open it.
  const only = !loading && open.length === 1 ? byArea.get(open[0].key)?.[0]?.href : undefined;
  useEffect(() => { if (only) router.replace(only); }, [only, router]);

  if (!user || loading || only) return <LoadingBlock rows={4} />;

  const hour = new Date().getHours();
  const greeting = t(hour < 12 ? "erpGreetingMorning" : hour < 17 ? "erpGreetingAfternoon" : "erpGreetingEvening");
  const today = new Date().toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", { weekday: "long", day: "numeric", month: "long" });

  const q = query.trim().toLowerCase();
  const matches = (a: Area) => !q || t(a.label).toLowerCase().includes(q) || t(a.blurb).toLowerCase().includes(q);
  const groups = CATEGORIES
    .map((c) => ({ ...c, apps: open.filter((a) => a.category === c.key && matches(a)) }))
    .filter((g) => g.apps.length > 0);
  const offShown = off.filter(matches);

  const app = (area: Area, href: string, state?: "off") => (
    <Link key={area.key} href={href} className="lx-app" data-state={state}
      title={state === "off" ? t("launcherOffAdmin") : t(area.blurb)}>
      <AppIcon area={area} size={92} badge={waiting[area.key]} />
      <span className="lx-app-name">{t(area.label)}</span>
    </Link>
  );

  return (
    <div className="lx">
      <header className="lx-head">
        <div>
          <p className="lx-date">{today}</p>
          <h1 className="lx-title">{greeting}, {user.name.split(" ")[0]}</h1>
        </div>
        <label className="lx-search">
          <Icon name="ph-magnifying-glass" size={18} />
          <input type="search" value={query} onChange={(e) => setQuery(e.target.value)}
            placeholder={t("launcherSearch")} aria-label={t("launcherSearch")} />
        </label>
      </header>

      {/* One grid, ordered by the part of the business each app serves. */}
      <div className="lx-apps lx-apps-main">
        {groups.flatMap((g) => g.apps).map((a) => app(a, byArea.get(a.key)?.[0]?.href ?? "/home"))}
      </div>

      {offShown.length > 0 && (
        <section className="lx-group lx-more" aria-labelledby="lx-more">
          <h2 id="lx-more" className="lx-section">{t("launcherMore")} <span className="lx-section-note">{t("launcherOffAdmin")}</span></h2>
          <div className="lx-apps">
            {offShown.map((a) => app(a, "/erp/setup", "off"))}
          </div>
        </section>
      )}

      {groups.length === 0 && offShown.length === 0 && <p className="lx-none">{t("launcherNone")}</p>}
    </div>
  );
}
