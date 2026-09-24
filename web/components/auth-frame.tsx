"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { LanguageToggle, ThemeToggle } from "@/components/ui";

/**
 * The frame for sign-in, registration and verification.
 *
 * One focused card, centred, with nothing competing for attention — the only
 * job on these screens is to get someone in, or set a company up. When a page
 * passes an aside (the demo accounts, in development only) it sits beside the
 * card rather than above it.
 */
export function AuthFrame({
  kicker, title, sub, children, aside, footer,
}: { kicker: string; title: string; sub?: string; children: ReactNode; aside?: ReactNode; footer?: ReactNode }) {
  return (
    <div className="vf-auth">
      <header className="vf-auth-bar">
        <Link href="/" className="vf-auth-brand" aria-label="VouchFlow home">
          <span className="vf-auth-mark" aria-hidden="true">V</span>
          VouchFlow
        </Link>
        <div className="vf-auth-bar-tools">
          <LanguageToggle />
          <ThemeToggle />
        </div>
      </header>

      <main className="vf-auth-main" data-has-aside={aside ? "true" : undefined}>
        <section className="vf-auth-card vf-rise">
          {kicker && <div className="vf-eyebrow">{kicker}</div>}
          <h1 className="vf-auth-title">{title}</h1>
          {sub && <p className="vf-auth-sub">{sub}</p>}
          <div className="vf-auth-body">{children}</div>
          {footer && <div className="vf-auth-footer">{footer}</div>}
        </section>
        {aside && <div className="vf-auth-aside">{aside}</div>}
      </main>

      <footer className="vf-auth-legal">
        <Icon />
        Vouchers, signatures and payments — every company isolated, every action on the record.
      </footer>
    </div>
  );
}

function Icon() {
  return <i className="ph ph-shield-check" aria-hidden="true" style={{ fontSize: 15 }} />;
}
