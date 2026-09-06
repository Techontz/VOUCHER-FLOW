"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { CONTENT } from "@/lib/i18n";
import { money } from "@/lib/format";
import { Icon, LanguageToggle, ThemeToggle } from "@/components/ui";
import type { Plan } from "@/lib/types";

export default function LandingPage() {
  const { t, locale } = useApp();
  const [plans, setPlans] = useState<Plan[]>([]);
  const i = locale === "sw" ? 1 : 0;

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans")
      .then((res) => setPlans(res.data))
      .catch(() => setPlans([]));
  }, [locale]);

  const today = new Date().toLocaleDateString(locale === "sw" ? "sw-TZ" : "en-GB", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  });

  return (
    <div className="vf-page">
      {/* ── masthead ── */}
      <nav style={{ display: "flex", alignItems: "center", gap: "var(--space-4)", padding: "var(--space-6) 0 var(--space-3)", flexWrap: "wrap" }}>
        <span style={{ fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 25, letterSpacing: "-.01em" }}>VouchFlow</span>
        <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-4)", fontSize: 15, color: "var(--color-neutral-700)" }}>
          <a href="#features">{t("features")}</a>
          <a href="#how">{t("solutions")}</a>
          <a href="#pricing">{t("pricing")}</a>
          <a href="#security">{t("security")}</a>
        </div>
        <div style={{ flex: 1 }} />
        <LanguageToggle />
        <ThemeToggle />
        <Link className="btn btn-ghost" href="/login">{t("login")}</Link>
        <Link className="btn btn-primary" href="/register">{t("getStarted")}</Link>
      </nav>

      <div style={{
        borderTop: "4px solid var(--color-text)", borderBottom: "1px solid var(--color-text)", padding: "5px 0",
        display: "flex", flexWrap: "wrap", gap: "var(--space-4)", fontSize: 12,
        letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-700)",
      }}>
        <span>Voucher management for growing businesses</span>
        <span style={{ flex: 1 }} />
        <span>Dar es Salaam</span>
        <span>{today}</span>
      </div>

      {/* ── hero ── */}
      <header style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", gap: "var(--space-8)", alignItems: "start", padding: "var(--space-8) 0" }}>
        <div>
          <div style={{ fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--color-accent-700)", marginBottom: "var(--space-3)" }}>
            {t("heroKicker")}
          </div>
          <h1 style={{ fontWeight: 700, fontSize: "clamp(36px, 5.4vw, 70px)", lineHeight: .99, letterSpacing: "-.022em", margin: "0 0 var(--space-4)", textWrap: "balance" }}>
            {t("heroH1")}
          </h1>
          <p style={{ fontSize: 18.5, lineHeight: 1.5, color: "var(--color-neutral-800)", maxWidth: "46ch", margin: "0 0 var(--space-6)" }}>
            {t("heroSub")}
          </p>
          <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-3)" }}>
            <Link className="btn btn-primary" href="/register" style={{ fontSize: 16, padding: "11px 22px" }}>{t("startFree")}</Link>
            <a className="btn btn-secondary" href="#how" style={{ fontSize: 16, padding: "11px 22px" }}>{t("seeHow")}</a>
          </div>
          <div style={{ marginTop: "var(--space-4)", fontSize: 14, color: "var(--color-neutral-600)" }}>{t("heroNote")}</div>
        </div>

        {/* The approvals card from the design, showing the signing-only step. */}
        <div style={{ border: "1px solid var(--color-divider)", background: "var(--color-neutral-100)", boxShadow: "var(--shadow-lg)", borderRadius: "var(--radius-md)", overflow: "hidden" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", padding: "10px var(--space-3)", borderBottom: "1px solid var(--color-divider)", fontSize: 12.5, color: "var(--color-neutral-700)", flexWrap: "wrap" }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: "var(--color-accent-2-500)" }} />
            <strong style={{ fontWeight: 600, color: "var(--color-text)" }}>{t("approvalsCard")}</strong>
            <span style={{ flex: 1 }} />
            <span style={{ whiteSpace: "nowrap" }}>3 {t("awaitingYou")}</span>
          </div>
          <div style={{ padding: "var(--space-3)" }}>
            {[
              { id: "PV-2026-001245", dept: "Procurement", purpose: "Freight to Arusha — September", amount: 4850000, tag: "tag-outline", status: locale === "sw" ? "Inasubiri sahihi" : "Awaiting signature" },
              { id: "PV-2026-001244", dept: "Finance", purpose: "Office rent — Q4 2026", amount: 21500000, tag: "tag-outline", status: locale === "sw" ? "Imesainiwa — tayari kutumwa" : "Signed — ready to submit" },
              { id: "PC-2026-000318", dept: "IT", purpose: "Replacement laptop batteries", amount: 1450000, tag: "tag-outline", status: locale === "sw" ? "Inasubiri idhini" : "Awaiting approval" },
            ].map((row) => (
              <div key={row.id} style={{ display: "grid", gridTemplateColumns: "minmax(0,1fr) auto", gap: "var(--space-2)", alignItems: "center", padding: "11px 0", borderBottom: "1px solid var(--color-divider)" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontVariantNumeric: "tabular-nums", color: "var(--color-neutral-600)" }}>{row.id} · {row.dept}</div>
                  <div style={{ fontSize: 15, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{row.purpose}</div>
                </div>
                <div style={{ textAlign: "right" }}>
                  <div style={{ fontVariantNumeric: "tabular-nums", fontWeight: 600, fontSize: 15 }}>{money(row.amount)}</div>
                  <span className={`tag ${row.tag}`} style={{ fontSize: 11.5 }}>{row.status}</span>
                </div>
              </div>
            ))}
            <div style={{ display: "flex", gap: "var(--space-2)", paddingTop: "var(--space-3)" }}>
              <Link className="btn btn-primary" style={{ flex: 1 }} href="/login">{t("reviewSign")}</Link>
              <Link className="btn btn-secondary" href="/login">{t("openQueue")}</Link>
            </div>
          </div>
        </div>
      </header>

      {/* ── how it works ── */}
      <section id="how" style={{ padding: "var(--space-8) 0", borderTop: "1px solid var(--color-divider)" }}>
        <h2 style={{ fontSize: "clamp(26px,3.4vw,38px)", letterSpacing: "-.015em", margin: "0 0 var(--space-6)" }}>{t("howItWorks")}</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))", gap: "var(--space-6)" }}>
          {CONTENT.steps.map(([n, title, body]) => (
            <div key={n as string} style={{ borderTop: "2px solid var(--color-text)", paddingTop: "var(--space-3)" }}>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 42, lineHeight: 1, color: "var(--color-accent-500)" }}>{n}</div>
              <h3 style={{ fontSize: 20, margin: "var(--space-2) 0 6px" }}>{title[i]}</h3>
              <p style={{ margin: 0, fontSize: 15.5, lineHeight: 1.5, color: "var(--color-neutral-700)" }}>{body[i]}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ── features ── */}
      <section id="features" style={{ padding: "var(--space-8) 0", borderTop: "1px solid var(--color-divider)" }}>
        <h2 style={{ fontSize: "clamp(26px,3.4vw,38px)", letterSpacing: "-.015em", margin: "0 0 var(--space-2)" }}>{t("featuresH2")}</h2>
        <p style={{ fontSize: 17, color: "var(--color-neutral-700)", maxWidth: "58ch", margin: "0 0 var(--space-6)" }}>{t("featuresSub")}</p>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "var(--space-6) var(--space-8)" }}>
          {CONTENT.features.map(([icon, title, body]) => (
            <div key={title[0]}>
              <Icon name={icon as string} size={26} color="var(--color-accent-600)" />
              <h3 style={{ fontSize: 18.5, margin: "10px 0 5px" }}>{title[i]}</h3>
              <p style={{ margin: 0, fontSize: 15, lineHeight: 1.5, color: "var(--color-neutral-700)" }}>{body[i]}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ── security ── */}
      <section id="security" style={{ padding: "var(--space-8) 0", borderTop: "1px solid var(--color-divider)", display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: "var(--space-8)" }}>
        <div>
          <div style={{ fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--color-accent-2-700)", marginBottom: "var(--space-3)" }}>{t("security")}</div>
          <h2 style={{ fontSize: "clamp(24px,3vw,34px)", letterSpacing: "-.015em", margin: "0 0 var(--space-3)" }}>{t("securityH2")}</h2>
          <p style={{ fontSize: 16.5, lineHeight: 1.55, color: "var(--color-neutral-700)", margin: 0 }}>{t("securitySub")}</p>
        </div>
        <div>
          {CONTENT.security.map(([title, body]) => (
            <div key={title[0]} style={{ display: "flex", gap: "var(--space-3)", padding: "13px 0", borderBottom: "1px solid var(--color-divider)" }}>
              <Icon name="ph-shield-check" size={20} color="var(--color-accent-600)" />
              <div><strong style={{ fontWeight: 600 }}>{title[i]}</strong> <span style={{ color: "var(--color-neutral-700)" }}>— {body[i]}</span></div>
            </div>
          ))}
        </div>
      </section>

      {/* ── pricing ── */}
      <section id="pricing" style={{ padding: "var(--space-8) 0", borderTop: "1px solid var(--color-divider)" }}>
        <h2 style={{ fontSize: "clamp(26px,3.4vw,38px)", letterSpacing: "-.015em", margin: "0 0 var(--space-6)" }}>{t("pricing")}</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(250px, 1fr))", gap: "var(--space-4)" }}>
          {plans.filter((p) => p.is_public).map((plan) => {
            const highlight = plan.code === "business";
            return (
              <div key={plan.id} style={{
                border: `1px solid ${highlight ? "var(--color-accent-500)" : "var(--color-divider)"}`,
                boxShadow: highlight ? "var(--shadow-md)" : "none",
                borderRadius: "var(--radius-md)", padding: "var(--space-4)",
                display: "flex", flexDirection: "column", gap: "var(--space-2)",
              }}>
                {highlight && <div style={{ fontSize: 10, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-accent-700)" }}>{locale === "sw" ? "Inachaguliwa zaidi" : "Most chosen"}</div>}
                <h3 style={{ fontSize: 22, margin: 0 }}>{plan.label}</h3>
                <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 28, fontVariantNumeric: "tabular-nums" }}>
                  {plan.price > 0 ? money(plan.price, plan.currency) : (locale === "sw" ? "Wasiliana nasi" : "Talk to us")}
                  {plan.price > 0 && <span style={{ fontSize: 14, fontWeight: 400, color: "var(--color-neutral-600)" }}> {t("perMonthShort")}</span>}
                </div>
                <p style={{ fontSize: 14.5, color: "var(--color-neutral-700)", margin: 0 }}>{plan.blurb}</p>
                <ul style={{ listStyle: "none", padding: 0, margin: "var(--space-2) 0", display: "grid", gap: 6, flex: 1 }}>
                  {plan.features.map((feature) => (
                    <li key={feature} style={{ display: "flex", gap: 8, fontSize: 14.5 }}>
                      <Icon name="ph-check" size={16} color="var(--color-accent-600)" />{feature}
                    </li>
                  ))}
                </ul>
                <Link className={`btn ${highlight ? "btn-primary" : "btn-secondary"}`} href="/register">
                  {plan.price > 0 ? t("startTrial") : t("contactSales")}
                </Link>
              </div>
            );
          })}
        </div>
      </section>

      {/* ── close ── */}
      <section style={{ padding: "var(--space-8) 0", borderTop: "1px solid var(--color-divider)", textAlign: "center" }}>
        <h2 style={{ fontSize: "clamp(28px,4.4vw,52px)", letterSpacing: "-.02em", margin: "0 0 var(--space-4)" }}>{t("ctaH2")}</h2>
        <Link className="btn btn-primary" href="/register" style={{ fontSize: 16, padding: "12px 26px" }}>{t("startFree")}</Link>
      </section>

      <footer style={{ borderTop: "1px solid var(--color-divider)", padding: "var(--space-6) 0", display: "flex", gap: "var(--space-4)", flexWrap: "wrap", fontSize: 13.5, color: "var(--color-neutral-600)" }}>
        <span style={{ fontFamily: "var(--font-heading)", fontWeight: 600, color: "var(--color-text)" }}>VouchFlow</span>
        <span style={{ flex: 1 }} />
        <span>© {new Date().getFullYear()} VouchFlow</span>
        <span>{locale === "sw" ? "Masharti" : "Terms"}</span>
        <span>{locale === "sw" ? "Faragha" : "Privacy"}</span>
      </footer>
    </div>
  );
}
