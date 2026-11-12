"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { CONTENT, translate, type MessageKey } from "@/lib/i18n";
import { money } from "@/lib/format";
import { Icon } from "@/components/ui";
import { SiteFooter, SiteNav } from "@/components/landing/site-chrome";
import { AppIcon } from "@/components/app-icon";
import { WorkflowShowcase } from "@/components/landing/workflow";
import { AREAS } from "@/lib/areas";
import { CONTACT, mailto } from "@/lib/contact";
import {
  AUDIT, COMPANIES, CONTROLS, FINAL, HERO, REPORTS, STATEMENT, VOUCHERS, WORKFLOW, pick,
  type L, type VoucherTab,
} from "@/components/landing/copy";
import {
  AuditVisual, BuilderVisual, CompaniesVisual, VoucherVisual,
} from "@/components/landing/mockups";
import { AppStrip, planApps, usePlanAppsLabel } from "@/components/app-picker";
import type { Plan } from "@/lib/types";

/**
 * The public site.
 *
 * Its job is the first ten seconds: what VouchFlow is (corporate voucher
 * management and approval), who it is for, and what happens to a voucher
 * inside it. So the page leads with the product itself, a voucher on its way
 * to approval, and every later section pairs a claim with a picture of the
 * part of the product that makes it true.
 */

export default function LandingPage() {
  const { locale } = useApp();
  const l = (entry: L) => pick(entry, locale);
  const i = locale === "sw" ? 1 : 0;
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const planAppsLabel = usePlanAppsLabel();
  const [tab, setTab] = useState<VoucherTab>("payment");
  const root = useReveal();

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  const activeTab = VOUCHERS.tabs.find((x) => x.key === tab) ?? VOUCHERS.tabs[0];

  return (
    <div className="lp" ref={root}>
      <SiteNav />

      {/* ── 1 · hero: the whole business, as a grid of apps ── */}
      <header className="st-home-hero">
        <div className="lp-wrap">
          <h1 className="st-home-title">{pickT(locale, "siteHeroTitle")}</h1>
          <p className="st-home-sub">{pickT(locale, "siteHeroSub")}</p>
          <div className="st-home-cta">
            <Link className="lp-cta lp-cta-primary" href="/register">{pickT(locale, "siteStart")} <Icon name="ph-arrow-right" size={18} /></Link>
            <Link className="lp-cta lp-cta-outline" href="/login">{l(HERO.signIn)}</Link>
          </div>
          <ul className="st-home-apps">
            {AREAS.filter((a) => a.category !== "admin").map((a, index) => (
              <li key={a.key} style={{ animationDelay: `${index * 45}ms` }}>
                <Link href="/apps" className="st-home-app">
                  <AppIcon area={a} size={96} />
                  <span>{pickT(locale, a.label)}</span>
                </Link>
              </li>
            ))}
          </ul>
          <Link className="st-home-all" href="/apps">{pickT(locale, "siteSeeApps")} <Icon name="ph-arrow-right" size={16} /></Link>
        </div>
      </header>

      {/* ── 2 · statement ── */}
      <section className="lp-section lp-statement" aria-labelledby="lp-statement">
        <div className="lp-wrap">
          <h2 id="lp-statement" className="lp-statement-title" data-reveal>
            {STATEMENT.lines.map((line) => <span key={line[0]}>{l(line)}</span>)}
            <span className="lp-statement-accent">{l(STATEMENT.closing)}</span>
          </h2>
          <div className="lp-pillars">
            {STATEMENT.pillars.map((p) => (
              <div key={p.title[0]} className="lp-pillar" data-reveal>
                <span className="lp-icon-tile"><Icon name={p.icon} size={21} /></span>
                <h3>{l(p.title)}</h3>
                <p>{l(p.body)}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── 3 · workflow ── */}
      <section id="workflow" className="lp-section wf-section" aria-labelledby="lp-workflow">
        <div className="lp-wrap">
          <SectionHead id="lp-workflow" eyebrow={l(WORKFLOW.eyebrow)} title={l(WORKFLOW.title)} sub={l(WORKFLOW.sub)} />
          <WorkflowShowcase />
        </div>
      </section>

      {/* ── 4 · voucher management ── */}
      <section id="vouchers" className="lp-section" aria-labelledby="lp-vouchers">
        <div className="lp-wrap lp-split">
          <div>
            <SectionHead id="lp-vouchers" eyebrow={l(VOUCHERS.eyebrow)} title={l(VOUCHERS.title)} sub={l(VOUCHERS.sub)} />
            <div className="lp-tabs" role="tablist" aria-label={l(VOUCHERS.eyebrow)}>
              {VOUCHERS.tabs.map((t) => (
                <button key={t.key} type="button" role="tab" id={`lp-tab-${t.key}`} aria-controls="lp-tabpanel"
                  aria-selected={tab === t.key} className="lp-tab" onClick={() => setTab(t.key)}>
                  <span className="lp-tab-icon"><Icon name={t.icon} size={19} /></span>
                  <span className="lp-tab-text">
                    <strong>{l(t.title)}</strong>
                    <span>{l(t.body)}</span>
                  </span>
                </button>
              ))}
            </div>
          </div>
          <div id="lp-tabpanel" role="tabpanel" aria-labelledby={`lp-tab-${activeTab.key}`} className="lp-stage-visual" key={tab}>
            <VoucherVisual tab={tab} />
          </div>
        </div>
      </section>

      {/* ── 5 · approval controls ── */}
      <section id="controls" className="lp-section lp-tint" aria-labelledby="lp-controls">
        <div className="lp-wrap lp-split lp-split-flip">
          <div>
            <SectionHead id="lp-controls" eyebrow={l(CONTROLS.eyebrow)} title={l(CONTROLS.title)} sub={l(CONTROLS.sub)} />
            <ul className="lp-feature-grid">
              {CONTROLS.items.map((item) => (
                <li key={item.title[0]} data-reveal>
                  <span className="lp-icon-tile lp-icon-sm"><Icon name={item.icon} size={18} /></span>
                  <div><strong>{l(item.title)}</strong><p>{l(item.body)}</p></div>
                </li>
              ))}
            </ul>
          </div>
          <div className="lp-stage-visual" data-reveal><BuilderVisual /></div>
        </div>
      </section>

      {/* ── 6 · audit ── */}
      <section id="audit" className="lp-section" aria-labelledby="lp-audit">
        <div className="lp-wrap lp-split">
          <div>
            <SectionHead id="lp-audit" eyebrow={l(AUDIT.eyebrow)} title={l(AUDIT.title)} sub={l(AUDIT.sub)} />
            <ul className="lp-checks">
              {AUDIT.items.map((item) => (
                <li key={item[0]}><Icon name="ph-check" size={16} /> {l(item)}</li>
              ))}
            </ul>
          </div>
          <div className="lp-stage-visual" data-reveal><AuditVisual /></div>
        </div>
      </section>

      {/* ── 7 · companies ── */}
      <section id="companies" className="lp-section lp-tint" aria-labelledby="lp-companies">
        <div className="lp-wrap">
          <div className="lp-split lp-split-top">
            <SectionHead id="lp-companies" eyebrow={l(COMPANIES.eyebrow)} title={l(COMPANIES.title)} sub={l(COMPANIES.sub)} />
            <div className="lp-stage-visual" data-reveal><CompaniesVisual /></div>
          </div>
          <ul className="lp-card-grid">
            {COMPANIES.items.map((item) => (
              <li key={item.title[0]} className="lp-mini-card" data-reveal>
                <span className="lp-icon-tile lp-icon-sm"><Icon name={item.icon} size={18} /></span>
                <strong>{l(item.title)}</strong>
                <p>{l(item.body)}</p>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* ── 8 · reports: a two-tone headline, big figures, a wall of report tiles ── */}
      <section id="reports" className="lp-section rp-section" aria-labelledby="lp-reports">
        <div className="lp-wrap rp-grid">
          <div className="rp-copy">
            <p className="lp-eyebrow" data-reveal>{l(REPORTS.eyebrow)}</p>
            <h2 id="lp-reports" className="rp-title" data-reveal>
              {l(REPORTS.titleLead)} <span className="rp-accent">{l(REPORTS.titleAccent)}</span>
            </h2>
            <p className="rp-sub" data-reveal>{l(REPORTS.sub)}</p>
            <div className="rp-stats" data-reveal data-stagger>
              {REPORTS.stats.map((stat) => (
                <div key={stat.label[0]} className="rp-stat">
                  <span className="rp-stat-value tnum"><span data-count={stat.value}>{stat.value}</span>{stat.suffix}</span>
                  <span className="rp-stat-label">{l(stat.label)}</span>
                  <span className="rp-stat-body">{l(stat.body)}</span>
                </div>
              ))}
            </div>
          </div>
          <ul className="rp-tiles" data-reveal data-stagger>
            {REPORTS.tiles.map((tile) => (
              <li key={tile.title[0]} className="rp-tile">
                <Icon name={tile.icon} size={30} />
                <span>{l(tile.title)}</span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* ── pricing, from the live plan list ── */}
      <section id="pricing" className="lp-section lp-tint" aria-labelledby="lp-pricing">
        <div className="lp-wrap">
          <SectionHead id="lp-pricing" eyebrow={locale === "sw" ? "Bei" : "Pricing"} title={pickT(locale, "pricing")} sub={pickT(locale, "pricingSub")} center />
          <div className="lp-plans">
            {CONTENT.plans.map((plan, index) => {
              const featured = index === 1;
              const live = plans?.find((p) => p.name === plan.name);
              return (
                <div key={plan.name} className="lp-plan" data-featured={featured || undefined} data-reveal>
                  <span className="lp-plan-kicker">{plan.kicker[i] ?? plan.kicker[0]}</span>
                  <h3>{plan.name}</h3>
                  <div className="lp-plan-price tnum">
                    {live && live.price > 0 ? money(live.price, live.currency) : (plan.price[i] ?? plan.price[0])}
                    {live && live.price > 0 && <span>{pickT(locale, "perMonthShort")}</span>}
                  </div>
                  {live && (
                    // What the plan includes, from the live catalogue: a few app icons and the count.
                    <div className="lp-plan-apps" style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", margin: "4px 0 2px", fontSize: 13.5, fontWeight: 600 }}>
                      <AppStrip apps={planApps(live)} max={5} size={24} />
                      <span>{planAppsLabel(live)}</span>
                    </div>
                  )}
                  <p>{plan.blurb[i] ?? plan.blurb[0]}</p>
                  {plan.name === "Enterprise" ? (
                    // A quoted plan: the conversation starts with an email, not a sign-up.
                    <a className="lp-cta lp-cta-outline" href={mailto(CONTACT.info, "VouchFlow Enterprise")}>
                      {plan.price[i] ?? plan.price[0]}
                    </a>
                  ) : (
                    <Link className={`lp-cta ${featured ? "lp-cta-primary" : "lp-cta-outline"}`} href="/register">
                      {pickT(locale, plan.cta)}
                    </Link>
                  )}
                  <ul>
                    {plan.items.map((item) => (
                      <li key={item[0]}><Icon name="ph-check" size={15} /> {item[i] ?? item[0]}</li>
                    ))}
                  </ul>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* ── 9 · final call to action ── */}
      <section className="lp-final" aria-labelledby="lp-final">
        <div className="lp-wrap lp-final-inner" data-reveal>
          <h2 id="lp-final">{l(FINAL.title)}</h2>
          <p>{l(FINAL.sub)}</p>
          <div className="lp-cta-row lp-cta-center">
            <Link className="lp-cta lp-cta-primary" href="/register">{l(HERO.getStarted)} <Icon name="ph-arrow-right" size={18} /></Link>
            <Link className="lp-cta lp-cta-ghost" href="/login">{l(HERO.signIn)}</Link>
          </div>
        </div>
      </section>

      <SiteFooter />
    </div>
  );
}

/* The app dictionary still owns a few shared words (pricing, plan CTAs). */
function pickT(locale: "en" | "sw", key: MessageKey) {
  return translate(key, locale);
}

function SectionHead({ id, eyebrow, title, sub, center }: { id: string; eyebrow: string; title: string; sub: string; center?: boolean }) {
  return (
    <div className={`lp-head${center ? " lp-head-center" : ""}`} data-reveal>
      <p className="lp-eyebrow">{eyebrow}</p>
      <h2 id={id}>{title}</h2>
      <p className="lp-head-sub">{sub}</p>
    </div>
  );
}

/** Figures marked data-count run up from zero when their section comes into view. */
function countUp(root: HTMLElement) {
  root.querySelectorAll<HTMLElement>("[data-count]").forEach((el) => {
    const target = Number(el.dataset.count);
    if (!Number.isFinite(target)) return;
    const began = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - began) / 1100);
      el.textContent = String(Math.round(target * (1 - Math.pow(1 - p, 3))));
      if (p < 1) requestAnimationFrame(tick);
    };
    el.textContent = "0";
    requestAnimationFrame(tick);
  });
}

function useReveal() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    // Every block of every section arrives as it scrolls into view, not
    // just the ones marked by hand; pictures slide in from their side.
    node.querySelectorAll<HTMLElement>(".lp-section .lp-wrap > *, .lp-section .lp-split > *, .lp-pillars, .lp-plans, .st-home-apps")
      .forEach((el) => { if (!el.dataset.reveal && !el.querySelector("[data-reveal]")) el.dataset.reveal = ""; });
    node.querySelectorAll<HTMLElement>(".lp-pillars, .lp-plans, .lp-report-list").forEach((el) => { el.dataset.stagger = ""; });

    // Lists marked data-stagger bring their items in one after another.
    node.querySelectorAll<HTMLElement>("[data-stagger]").forEach((list) => {
      Array.from(list.children).forEach((child, i) => (child as HTMLElement).style.setProperty("--i", String(i)));
    });
    const targets = Array.from(node.querySelectorAll<HTMLElement>("[data-reveal]"));
    const below = targets.filter((el) => el.getBoundingClientRect().top > window.innerHeight * 0.92);
    // Anything already in view or scrolled past is shown at once, even if an
    // earlier mount had left it waiting.
    targets.filter((el) => !below.includes(el)).forEach((el) => { if (el.dataset.reveal === "pending") el.dataset.reveal = "shown"; });
    below.forEach((el) => { if (el.dataset.reveal !== "shown") el.dataset.reveal = "pending"; });

    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          const el = entry.target as HTMLElement;
          el.dataset.reveal = "shown";
          countUp(el);
          observer.unobserve(el);
        }
      }
    }, { rootMargin: "0px 0px -8% 0px" });

    below.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  return ref;
}
