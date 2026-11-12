"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useApp } from "@/lib/app-context";
import { Icon, LanguageToggle, ThemeToggle } from "@/components/ui";
import { VouchFlowMark } from "@/components/login-brand";
import { FOOTER, HERO, NAV, pick, type L } from "@/components/landing/copy";
import { CONTACT, mailto } from "@/lib/contact";

/** The public site's top bar and footer, shared by every public page. */

export function SiteNav() {
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

export function SiteFooter() {
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
        <div>
          <h3>{l(FOOTER.contact)}</h3>
          <a href={mailto(CONTACT.info)}><span className="lp-footer-note">{l(FOOTER.general)}</span>{CONTACT.info}</a>
          <a href={mailto(CONTACT.support)}><span className="lp-footer-note">{l(FOOTER.support)}</span>{CONTACT.support}</a>
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
