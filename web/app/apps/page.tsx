"use client";

import Link from "next/link";
import { useApp } from "@/lib/app-context";
import { AREAS, CATEGORIES } from "@/lib/areas";
import { AppIcon } from "@/components/app-icon";
import { SiteFooter, SiteNav } from "@/components/landing/site-chrome";
import { Icon } from "@/components/ui";

/**
 * Every app VouchFlow offers, by the part of the business it serves, each
 * with one line on what it is for. Public: it is how a company decides what
 * to switch on.
 */
export default function AllAppsPage() {
  const { t } = useApp();
  const groups = CATEGORIES
    .filter((c) => c.key !== "admin")
    .map((c) => ({ ...c, apps: AREAS.filter((a) => a.category === c.key) }));

  return (
    <div className="lp st">
      <SiteNav />

      <header className="st-hero">
        <div className="lp-wrap">
          <h1 className="st-title">{t("siteAppsTitle")}</h1>
          <p className="st-sub">{t("siteAppsSub")}</p>
        </div>
      </header>

      <main className="lp-wrap st-catalogue">
        {groups.map((g) => (
          <section key={g.key} className="st-group" aria-labelledby={`st-${g.key}`}>
            <h2 id={`st-${g.key}`} className="st-group-title">{t(g.label)}</h2>
            <ul className="st-apps">
              {g.apps.map((a) => (
                <li key={a.key} className="st-app">
                  <AppIcon area={a} size={52} />
                  <div>
                    <h3>{t(a.label)}</h3>
                    <p>{t(a.blurb)}</p>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </main>

      <section className="st-closing">
        <div className="lp-wrap">
          <h2>{t("siteClosing")}</h2>
          <p>{t("siteClosingSub")}</p>
          <Link className="lp-cta lp-cta-primary" href="/register">{t("siteStart")} <Icon name="ph-arrow-right" size={18} /></Link>
        </div>
      </section>

      <SiteFooter />
    </div>
  );
}
