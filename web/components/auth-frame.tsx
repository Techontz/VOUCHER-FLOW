"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useApp } from "@/lib/app-context";
import { LanguageToggle, ThemeToggle } from "@/components/ui";

/** Shared editorial frame for the public authentication screens. */
export function AuthFrame({
  kicker, title, sub, children, aside, footer,
}: { kicker: string; title: string; sub?: string; children: ReactNode; aside?: ReactNode; footer?: ReactNode }) {
  const { t } = useApp();

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      <nav style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", padding: "var(--space-4) var(--space-6)", flexWrap: "wrap" }}>
        <Link href="/" style={{ fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 22, color: "var(--color-text)", textDecoration: "none" }}>
          VouchFlow
        </Link>
        <div style={{ flex: 1 }} />
        <LanguageToggle />
        <ThemeToggle />
      </nav>

      <div style={{
        flex: 1, display: "grid", gridTemplateColumns: aside ? "repeat(auto-fit, minmax(320px, 1fr))" : "1fr",
        gap: "var(--space-8)", maxWidth: aside ? 1080 : 520, width: "100%", margin: "0 auto",
        padding: "var(--space-6) var(--space-4) var(--space-8)", alignItems: "start",
      }}>
        <div style={{ width: "100%" }}>
          <div style={{ fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--color-accent-700)" }}>{kicker}</div>
          <h1 style={{ fontSize: "clamp(28px, 4vw, 40px)", letterSpacing: "-.02em", margin: "8px 0 6px" }}>{title}</h1>
          {sub && <p style={{ color: "var(--color-neutral-700)", fontSize: 16, margin: "0 0 var(--space-6)", maxWidth: "52ch" }}>{sub}</p>}
          {children}
          {footer && <div style={{ marginTop: "var(--space-4)", fontSize: 14.5, color: "var(--color-neutral-700)" }}>{footer}</div>}
        </div>
        {aside}
      </div>
    </div>
  );
}
