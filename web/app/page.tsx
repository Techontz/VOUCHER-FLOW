"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { CONTENT, translate, type MessageKey } from "@/lib/i18n";
import { money } from "@/lib/format";
import { Icon, LanguageToggle, ThemeToggle } from "@/components/ui";
import { VouchFlowMark } from "@/components/login-brand";
import {
  AUDIT, COMPANIES, CONTROLS, FINAL, FOOTER, HERO, NAV, REPORTS, STATEMENT, VOUCHERS, WORKFLOW, pick,
  type L, type VoucherTab,
} from "@/components/landing/copy";
import {
  AuditVisual, BuilderVisual, CompaniesVisual, HeroVisual, ReportsVisual, VoucherVisual,
} from "@/components/landing/mockups";
import type { Plan } from "@/lib/types";

/**
 * The public site.
 *
 * Its job is the first ten seconds: what VouchFlow is (corporate voucher
 * management and approval), who it is for, and what happens to a voucher
 * inside it. So the page leads with the product itself — a voucher on its way
 * to approval — and every later section pairs a claim with a picture of the
 * part of the product that makes it true.
 */

export default function LandingPage() {
  const { locale } = useApp();
  const l = (entry: L) => pick(entry, locale);
  const i = locale === "sw" ? 1 : 0;
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [tab, setTab] = useState<VoucherTab>("payment");
  const root = useReveal();

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  const activeTab = VOUCHERS.tabs.find((x) => x.key === tab) ?? VOUCHERS.tabs[0];

  return (
    <div className="lp" ref={root}>
      <SiteNav />

      {/* ── 1 · hero ── */}
      <header className="lp-hero">
        <div className="lp-wrap lp-hero-grid">
          <div className="lp-hero-copy">
            <p className="lp-eyebrow lp-eyebrow-on-dark">{l(HERO.eyebrow)}</p>
            <h1 className="lp-hero-title">
              <span>{l(HERO.line1)}</span> <span className="lp-hero-accent">{l(HERO.line2)}</span>
            </h1>
            <p className="lp-hero-sub">{l(HERO.sub)}</p>
            <div className="lp-cta-row">
              <Link className="lp-cta lp-cta-primary" href="/register">
                {l(HERO.getStarted)} <Icon name="ph-arrow-right" size={18} />
              </Link>
              <Link className="lp-cta lp-cta-ghost" href="/login">{l(HERO.signIn)}</Link>
            </div>
            <ul className="lp-proof">
              {HERO.proof.map((item) => (
                <li key={item[0]}><Icon name="ph-check-circle" size={17} /> {l(item)}</li>
              ))}
            </ul>
          </div>
          <HeroVisual />
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
      <section id="workflow" className="lp-section lp-tint" aria-labelledby="lp-workflow">
        <div className="lp-wrap">
          <SectionHead id="lp-workflow" eyebrow={l(WORKFLOW.eyebrow)} title={l(WORKFLOW.title)} sub={l(WORKFLOW.sub)} center />
          <ol className="lp-pipeline">
            {WORKFLOW.stages.map((stage, index) => (
              <li key={stage.title[0]} className="lp-stage" data-reveal style={{ transitionDelay: `${index * 60}ms` }}>
                <div className="lp-stage-top">
                  <span className="lp-stage-icon"><Icon name={stage.icon} size={22} /></span>
                  <span className="lp-stage-num tnum">{String(index + 1).padStart(2, "0")}</span>
                </div>
                <h3>{l(stage.title)}</h3>
                <span className="lp-stage-role">{l(stage.role)}</span>
                <p>{l(stage.body)}</p>
              </li>
            ))}
          </ol>
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

      {/* ── 8 · reports ── */}
      <section id="reports" className="lp-section" aria-labelledby="lp-reports">
        <div className="lp-wrap lp-split lp-split-flip">
          <div>
            <SectionHead id="lp-reports" eyebrow={l(REPORTS.eyebrow)} title={l(REPORTS.title)} sub={l(REPORTS.sub)} />
            <ul className="lp-report-list">
              {REPORTS.items.map((item) => (
                <li key={item.title[0]}><span className="lp-icon-tile lp-icon-sm"><Icon name={item.icon} size={17} /></span> {l(item.title)}</li>
              ))}
            </ul>
          </div>
          <div className="lp-stage-visual" data-reveal><ReportsVisual /></div>
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
                  <p>{plan.blurb[i] ?? plan.blurb[0]}</p>
                  <Link className={`lp-cta ${featured ? "lp-cta-primary" : "lp-cta-outline"}`} href="/register">
                    {pickT(locale, plan.cta)}
                  </Link>
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

function SiteNav() {
  const { locale } = useApp();
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <nav className="lp-nav" data-scrolled={scrolled || open || undefined} aria-label="Main">
      <div className="lp-wrap lp-nav-inner">
        <Link href="/" className="lp-brand" aria-label="VouchFlow home">
          <VouchFlowMark size={30} />
          <span>VouchFlow</span>
        </Link>

        <div className="lp-nav-links">
          {NAV.map((item) => <a key={item.href} href={item.href}>{pick(item.label, locale)}</a>)}
        </div>

        <div className="lp-nav-actions">
          <div className="lp-nav-tools"><LanguageToggle /><ThemeToggle /></div>
          <Link className="lp-nav-signin" href="/login">{pick(HERO.signIn, locale)}</Link>
          <Link className="lp-cta lp-cta-primary lp-cta-sm" href="/register">{pick(HERO.getStarted, locale)}</Link>
          <button type="button" className="lp-menu-btn" aria-expanded={open} aria-controls="lp-menu"
            aria-label={open ? "Close menu" : "Open menu"} onClick={() => setOpen((v) => !v)}>
            <Icon name={open ? "ph-x" : "ph-list"} size={22} />
          </button>
        </div>
      </div>

      <div id="lp-menu" className="lp-menu" hidden={!open}>
        {NAV.map((item) => (
          <a key={item.href} href={item.href} onClick={() => setOpen(false)}>{pick(item.label, locale)}</a>
        ))}
        <div className="lp-menu-foot">
          <LanguageToggle />
          <ThemeToggle />
          <Link className="lp-cta lp-cta-outline lp-cta-sm" href="/login">{pick(HERO.signIn, locale)}</Link>
        </div>
      </div>
    </nav>
  );
}

function SiteFooter() {
  const { locale } = useApp();
  const l = (entry: L) => pick(entry, locale);
  return (
    <footer className="lp-footer">
      <div className="lp-wrap lp-footer-grid">
        <div>
          <Link href="/" className="lp-brand lp-brand-ink"><VouchFlowMark size={28} /><span>VouchFlow</span></Link>
          <p>{l(FOOTER.tagline)}</p>
        </div>
        <div>
          <h3>{l(FOOTER.product)}</h3>
          {NAV.map((item) => <a key={item.href} href={item.href}>{l(item.label)}</a>)}
        </div>
        <div>
          <h3>{l(FOOTER.account)}</h3>
          <Link href="/login">{l(HERO.signIn)}</Link>
          <Link href="/register">{l(FOOTER.register)}</Link>
        </div>
      </div>
      <div className="lp-wrap lp-footer-base">
        <Icon name="ph-shield-check" size={15} /> <strong>VouchFlow</strong> · {l(FOOTER.rights)}
      </div>
    </footer>
  );
}

/**
 * Fades sections in the first time they scroll into view.
 *
 * Content is visible by default; only once this runs does the page opt in to
 * the hidden starting state, so a slow script, a crawler or reduced motion
 * never leaves anything invisible.
 */
function useReveal() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const targets = Array.from(node.querySelectorAll<HTMLElement>("[data-reveal]"));
    const below = targets.filter((el) => el.getBoundingClientRect().top > window.innerHeight * 0.92);
    below.forEach((el) => { el.dataset.reveal = "pending"; });

    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          (entry.target as HTMLElement).dataset.reveal = "shown";
          observer.unobserve(entry.target);
        }
      }
    }, { rootMargin: "0px 0px -8% 0px" });

    below.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  return ref;
}
