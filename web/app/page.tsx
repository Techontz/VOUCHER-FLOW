"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { CONTENT } from "@/lib/i18n";
import { money } from "@/lib/format";
import { Icon, LanguageToggle, ThemeToggle } from "@/components/ui";
import type { Plan } from "@/lib/types";

/** The companies named on the trust row — neutral demo names, as everywhere else. */
const LOGOS: [string, string][] = [
  ["Acme Tanzania Ltd", "AT"],
  ["Zamani Logistics", "ZL"],
  ["Tembo Holdings", "TH"],
  ["Baobab Business Solutions", "BB"],
  ["Serengeti Supplies", "SS"],
];

/** The queue shown inside the hero card — illustrative, not live data. */
const HERO_QUEUE = [
  { id: "PV-2026-001245", dept: "Procurement", purpose: "Freight to Arusha — September", amount: "TZS 4,850,000", tag: "tag-outline", statusKey: "awaitingSignature" },
  { id: "PV-2026-001244", dept: "Finance", purpose: "Office rent — Q4 2026", amount: "TZS 21,500,000", tag: "tag-outline", statusKey: "signedReadySubmit" },
  { id: "PC-2026-000318", dept: "IT", purpose: "Replacement laptop batteries", amount: "TZS 1,450,000", tag: "tag-outline", statusKey: "awaitingApprovalAct" },
] as const;

const STEP_ICONS = ["ph-note-pencil", "ph-signature", "ph-seal-check", "ph-wallet"];

export default function LandingPage() {
  const { t, locale } = useApp();
  const i = locale === "sw" ? 1 : 0;
  const [plans, setPlans] = useState<Plan[] | null>(null);

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  return (
    <div style={{ position: "relative", overflow: "hidden" }}>
      {/* ambient glow behind the hero */}
      <div aria-hidden="true" style={{
        position: "absolute", top: -140, left: "50%", transform: "translateX(-50%)",
        width: "min(1200px, 150%)", height: 620, pointerEvents: "none",
        background: "radial-gradient(50% 50% at 50% 50%, rgba(47,123,246,.20), transparent 70%)",
      }} />
      <div aria-hidden="true" style={{
        position: "absolute", top: 60, right: -80, width: "min(620px, 80%)", height: 620, pointerEvents: "none",
        background: "radial-gradient(50% 50% at 50% 50%, rgba(34,211,238,.11), transparent 70%)",
      }} />

      <div style={{ position: "relative", maxWidth: 1200, margin: "0 auto", padding: "0 28px" }}>
        {/* ── nav ── */}
        <nav style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, padding: "22px 0" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 26, minWidth: 0, flex: "1 1 auto" }}>
            <Wordmark />
            <div className="vf-lp-nav">
              {([["#features", "product"], ["#features", "features"], ["#how", "solutions"], ["#pricing", "pricing"], ["#security", "security"]] as const)
                .map(([href, key], index) => (
                  <a key={`${key}-${index}`} href={href}>{t(key)}</a>
                ))}
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 10, flex: "none" }}>
            <div className="vf-lp-nav"><LanguageToggle /></div>
            <ThemeToggle />
            <Link className="btn btn-ghost" href="/login">{t("login")}</Link>
            <Link className="btn btn-primary" href="/register">{t("getStarted")}</Link>
          </div>
        </nav>

        {/* ── hero ── */}
        <header style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 380px), 1fr))",
          gap: 48, alignItems: "center", padding: "56px 0 76px",
        }}>
          <div style={{ animation: "vf-rise .6s ease both" }}>
            <div style={{
              display: "inline-flex", alignItems: "center", gap: 8, padding: "5px 12px 5px 6px",
              borderRadius: 99, border: "1px solid var(--vf-line-strong)", background: "var(--vf-elev-2)",
              fontSize: 12.5, fontWeight: 500, color: "var(--color-neutral-700)", marginBottom: 26,
            }}>
              <span style={{ padding: "2px 8px", borderRadius: 99, background: "var(--vf-grad)", color: "#04121f", fontWeight: 600, fontSize: 11.5 }}>New</span>
              {t("heroKicker")}
            </div>

            <h1 style={{
              fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: "clamp(38px, 4.9vw, 66px)",
              lineHeight: 1.03, letterSpacing: "-.042em", margin: "0 0 20px", textWrap: "balance",
            }}>{t("heroH1")}</h1>

            <p style={{ fontSize: 18, lineHeight: 1.62, color: "var(--color-neutral-700)", maxWidth: "48ch", margin: "0 0 32px", textWrap: "pretty" }}>
              {t("heroSub")}
            </p>

            <div style={{ display: "flex", flexWrap: "wrap", gap: 11 }}>
              <Link className="btn btn-primary" href="/register" style={{ fontSize: 15.5, padding: "13px 24px", borderRadius: 11 }}>
                {t("startFree")} <Icon name="ph-arrow-right" size={16} />
              </Link>
              <a className="btn btn-secondary" href="#how" style={{ fontSize: 15.5, padding: "13px 22px", borderRadius: 11 }}>
                {t("seeHow")}
              </a>
            </div>

            <div style={{ marginTop: 22, display: "flex", alignItems: "center", gap: 8, fontSize: 13.5, color: "var(--color-neutral-600)" }}>
              <Icon name="ph-shield-check" size={17} color="var(--vf-ok)" /> {t("heroNote")}
            </div>
          </div>

          {/* approvals card */}
          <div style={{ position: "relative", animation: "vf-rise .7s .1s ease both" }}>
            <div aria-hidden="true" style={{
              position: "absolute", inset: -1, borderRadius: 19, pointerEvents: "none",
              background: "linear-gradient(150deg, rgba(61,139,255,.55), rgba(34,211,238,.18) 45%, transparent 75%)",
            }} />
            <div style={{
              position: "relative", border: "1px solid var(--vf-line)", background: "var(--vf-glass)",
              backdropFilter: "blur(18px)", WebkitBackdropFilter: "blur(18px)",
              boxShadow: "var(--shadow-lg)", borderRadius: 18, overflow: "hidden",
            }}>
              <div style={{
                display: "flex", alignItems: "center", gap: 9, padding: "13px 16px",
                borderBottom: "1px solid var(--vf-line)", fontSize: 12.5, color: "var(--color-neutral-600)",
                background: "linear-gradient(180deg, rgba(148,170,214,.06), transparent)", flexWrap: "wrap",
              }}>
                <span style={{ width: 7, height: 7, borderRadius: "50%", background: "var(--vf-warn)", boxShadow: "0 0 0 3px color-mix(in srgb, var(--vf-warn) 20%, transparent)" }} />
                <strong style={{ fontWeight: 600, color: "var(--color-text)", fontSize: 13.5 }}>{t("approvalsCard")}</strong>
                <span>Acme Tanzania Ltd</span>
                <span style={{ flex: 1 }} />
                <span style={{ whiteSpace: "nowrap", padding: "2px 8px", borderRadius: 6, background: "var(--vf-elev-3)", border: "1px solid var(--vf-line)" }}>
                  3 {t("awaitingYou")}
                </span>
              </div>

              <div style={{ padding: "6px 16px 16px" }}>
                {HERO_QUEUE.map((row) => (
                  <div key={row.id} style={{
                    display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", gap: 12,
                    alignItems: "center", padding: "13px 0", borderBottom: "1px solid var(--vf-line)",
                  }}>
                    <div style={{ minWidth: 0 }}>
                      <div style={{ fontSize: 12, fontVariantNumeric: "tabular-nums", color: "var(--color-neutral-600)", letterSpacing: ".02em" }}>
                        {row.id} · {row.dept}
                      </div>
                      <div style={{ fontSize: 14.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", marginTop: 2 }}>
                        {row.purpose}
                      </div>
                    </div>
                    <div style={{ textAlign: "right", display: "grid", gap: 5, justifyItems: "end" }}>
                      <div style={{ fontVariantNumeric: "tabular-nums", fontWeight: 600, fontSize: 15, letterSpacing: "-.02em" }}>{row.amount}</div>
                      <span className={`tag ${row.tag}`} style={{ fontSize: 11 }}>{t(row.statusKey)}</span>
                    </div>
                  </div>
                ))}
                <div style={{ display: "flex", gap: 9, paddingTop: 16 }}>
                  <Link className="btn btn-primary" href="/login" style={{ flex: 1 }}>
                    <Icon name="ph-signature" size={15} /> {t("reviewSign")}
                  </Link>
                  <Link className="btn btn-secondary" href="/login">{t("openQueue")}</Link>
                </div>
              </div>
            </div>
          </div>
        </header>

        {/* ── trust row ── */}
        <section style={{ padding: "30px 0 70px", borderTop: "1px solid var(--vf-line)" }}>
          <div style={{ fontSize: 11.5, fontWeight: 500, letterSpacing: ".13em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 22, paddingTop: 30 }}>
            {t("trustedBy")}
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 14 }}>
            {LOGOS.map(([name, ini]) => (
              <div key={name} className="vf-logo-chip">
                <span style={{
                  width: 24, height: 24, borderRadius: 6, background: "var(--vf-elev-3)",
                  border: "1px solid var(--vf-line)", display: "grid", placeItems: "center",
                  fontSize: 11, fontWeight: 700, color: "var(--color-accent-600)", flex: "none",
                }}>{ini}</span>
                {name}
              </div>
            ))}
          </div>
        </section>

        {/* ── how it works ── */}
        <section id="how" style={{ padding: "70px 0", borderTop: "1px solid var(--vf-line)" }}>
          <h2 style={{ fontSize: "clamp(28px, 3.1vw, 40px)", margin: "0 0 8px" }}>{t("howItWorks")}</h2>
          <p style={{ fontSize: 16.5, color: "var(--color-neutral-600)", margin: "0 0 40px", maxWidth: "54ch" }}>{t("howSub")}</p>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(228px, 1fr))", gap: 16 }}>
            {CONTENT.steps.map(([n, title, body], index) => (
              <div key={n} className="vf-step-card">
                <span aria-hidden="true" className="vf-step-ghost">{n}</span>
                <div style={{
                  position: "relative", width: 38, height: 38, borderRadius: 11,
                  background: "var(--color-accent-100)", border: "1px solid var(--vf-line)",
                  display: "grid", placeItems: "center", marginBottom: 16,
                }}>
                  <Icon name={STEP_ICONS[index] ?? "ph-circle"} size={20} color="var(--color-accent-600)" />
                </div>
                <h3 style={{ position: "relative", fontSize: 17.5, margin: "0 0 7px", letterSpacing: "-.02em" }}>{title[i] ?? title[0]}</h3>
                <p style={{ position: "relative", margin: 0, fontSize: 14.5, lineHeight: 1.6, color: "var(--color-neutral-600)" }}>
                  {body[i] ?? body[0]}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* ── features ── */}
        <section id="features" style={{ padding: "70px 0", borderTop: "1px solid var(--vf-line)" }}>
          <h2 style={{ fontSize: "clamp(28px, 3.1vw, 40px)", margin: "0 0 10px", maxWidth: "26ch" }}>{t("featuresH2")}</h2>
          <p style={{ fontSize: 16.5, color: "var(--color-neutral-600)", maxWidth: "58ch", margin: "0 0 40px" }}>{t("featuresSub")}</p>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(252px, 1fr))", gap: 14 }}>
            {CONTENT.features.map(([icon, title, body]) => (
              <div key={title[0]} className="vf-feature-card">
                <div style={{
                  width: 34, height: 34, borderRadius: 10, background: "var(--vf-elev-3)",
                  border: "1px solid var(--vf-line)", display: "grid", placeItems: "center", marginBottom: 14,
                }}>
                  <Icon name={icon} size={18} color="var(--color-accent-600)" />
                </div>
                <h3 style={{ fontSize: 16, margin: "0 0 6px", letterSpacing: "-.015em" }}>{title[i] ?? title[0]}</h3>
                <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: "var(--color-neutral-600)" }}>{body[i] ?? body[0]}</p>
              </div>
            ))}
          </div>
        </section>

        {/* ── security ── */}
        <section id="security" style={{ padding: "70px 0", borderTop: "1px solid var(--vf-line)" }}>
          <div style={{
            position: "relative", overflow: "hidden", border: "1px solid var(--vf-line)",
            borderRadius: 20, background: "var(--vf-elev-1)", padding: 40,
            display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(290px, 1fr))", gap: 44,
          }}>
            <div aria-hidden="true" style={{ position: "absolute", inset: 0, background: "var(--vf-grad-soft)", pointerEvents: "none" }} />
            <div style={{ position: "relative" }}>
              <div style={{
                display: "inline-flex", alignItems: "center", gap: 7, fontSize: 11.5, fontWeight: 600,
                letterSpacing: ".11em", textTransform: "uppercase", color: "var(--color-accent-700)", marginBottom: 16,
              }}>
                <Icon name="ph-lock-key" size={15} /> {t("security")}
              </div>
              <h2 style={{ fontSize: "clamp(24px, 2.4vw, 32px)", margin: "0 0 14px", maxWidth: "24ch" }}>{t("securityH2")}</h2>
              <p style={{ fontSize: 15.5, lineHeight: 1.65, color: "var(--color-neutral-600)", margin: 0, maxWidth: "52ch" }}>
                {t("securitySub")}
              </p>
            </div>
            <div style={{ position: "relative", display: "grid", gap: 9, alignContent: "start" }}>
              {CONTENT.security.map(([title, body]) => (
                <div key={title[0]} style={{
                  display: "flex", gap: 12, alignItems: "flex-start", padding: "13px 15px",
                  border: "1px solid var(--vf-line)", borderRadius: 11, background: "var(--vf-elev-2)",
                }}>
                  <Icon name="ph-check-circle" size={19} color="var(--vf-ok)" style={{ flex: "none" }} />
                  <div style={{ fontSize: 14.5, lineHeight: 1.5 }}>
                    <strong style={{ fontWeight: 600 }}>{title[i] ?? title[0]}</strong>{" "}
                    <span style={{ color: "var(--color-neutral-600)" }}>— {body[i] ?? body[0]}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── pricing ── */}
        <section id="pricing" style={{ padding: "70px 0", borderTop: "1px solid var(--vf-line)" }}>
          <h2 style={{ fontSize: "clamp(28px, 3.1vw, 40px)", margin: "0 0 10px" }}>{t("pricing")}</h2>
          <p style={{ fontSize: 16.5, color: "var(--color-neutral-600)", margin: "0 0 40px" }}>{t("pricingSub")}</p>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(268px, 1fr))", gap: 16, alignItems: "start" }}>
            {CONTENT.plans.map((plan, index) => {
              const featured = index === 1;
              const live = plans?.find((p) => p.name === plan.name);
              return (
                <div key={plan.name} style={{
                  position: "relative", display: "flex", flexDirection: "column", gap: 12,
                  padding: "26px 24px", borderRadius: 18, overflow: "hidden",
                  border: `1px solid ${featured ? "var(--color-accent-500)" : "var(--vf-line)"}`,
                  background: "var(--vf-elev-1)",
                  boxShadow: featured ? "var(--shadow-md)" : "none",
                }}>
                  {featured && (
                    <>
                      <div aria-hidden="true" style={{ position: "absolute", inset: 0, background: "var(--vf-grad-soft)", pointerEvents: "none" }} />
                      <div aria-hidden="true" style={{
                        position: "absolute", top: 0, left: 24, right: 24, height: 1,
                        background: "linear-gradient(90deg, transparent, var(--color-accent-500), transparent)",
                      }} />
                    </>
                  )}
                  <span style={{ position: "relative", fontSize: 11.5, fontWeight: 600, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-accent-700)" }}>
                    {plan.kicker[i] ?? plan.kicker[0]}
                  </span>
                  <div style={{ position: "relative", fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 21, letterSpacing: "-.025em" }}>
                    {plan.name}
                  </div>
                  <div style={{ position: "relative", display: "flex", alignItems: "baseline", gap: 6, flexWrap: "wrap" }}>
                    <span style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 32, letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums" }}>
                      {live && live.price > 0 ? money(live.price, live.currency) : (plan.price[i] ?? plan.price[0])}
                    </span>
                    {live && live.price > 0 && (
                      <span style={{ fontSize: 13.5, color: "var(--color-neutral-600)" }}>{t("perMonthShort")}</span>
                    )}
                  </div>
                  <div style={{ position: "relative", fontSize: 14, lineHeight: 1.55, color: "var(--color-neutral-600)", minHeight: 44 }}>
                    {plan.blurb[i] ?? plan.blurb[0]}
                  </div>
                  <Link className={`btn ${featured ? "btn-primary" : "btn-secondary"}`} href="/register" style={{ position: "relative", marginTop: 2 }}>
                    {t(plan.cta)}
                  </Link>
                  <div style={{ position: "relative", borderTop: "1px solid var(--vf-line)", marginTop: 10, paddingTop: 14, display: "grid", gap: 9 }}>
                    {plan.items.map((item) => (
                      <div key={item[0]} style={{ display: "flex", gap: 9, alignItems: "flex-start", fontSize: 14, color: "var(--color-neutral-700)" }}>
                        <Icon name="ph-check-circle" size={17} color="var(--vf-ok)" style={{ flex: "none" }} />
                        <span>{item[i] ?? item[0]}</span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        {/* ── closing call to action ── */}
        <section style={{ padding: "40px 0 80px" }}>
          <div style={{
            position: "relative", overflow: "hidden", border: "1px solid var(--vf-line)",
            borderRadius: 22, background: "var(--vf-elev-1)", padding: "62px 32px", textAlign: "center",
          }}>
            <div aria-hidden="true" style={{
              position: "absolute", inset: 0, pointerEvents: "none",
              background: "radial-gradient(60% 120% at 50% 0%, rgba(47,123,246,.22), transparent 70%)",
            }} />
            <div aria-hidden="true" style={{
              position: "absolute", top: 0, left: "20%", right: "20%", height: 1,
              background: "linear-gradient(90deg, transparent, var(--color-accent-500), transparent)",
            }} />
            <h2 style={{ position: "relative", fontSize: "clamp(28px, 3.8vw, 48px)", letterSpacing: "-.038em", margin: "0 0 14px", textWrap: "balance" }}>
              {t("ctaH2")}
            </h2>
            <p style={{ position: "relative", fontSize: 16.5, color: "var(--color-neutral-600)", margin: "0 auto 28px", maxWidth: "46ch" }}>
              {t("ctaSub")}
            </p>
            <div style={{ position: "relative", display: "flex", gap: 11, justifyContent: "center", flexWrap: "wrap" }}>
              <Link className="btn btn-primary" href="/register" style={{ fontSize: 15.5, padding: "13px 26px", borderRadius: 11 }}>
                {t("startFree")} <Icon name="ph-arrow-right" size={16} />
              </Link>
              <Link className="btn btn-secondary" href="/login" style={{ fontSize: 15.5, padding: "13px 22px", borderRadius: 11 }}>
                {t("signIn")}
              </Link>
            </div>
          </div>
        </section>

        {/* ── footer ── */}
        <footer style={{
          borderTop: "1px solid var(--vf-line)", padding: "46px 0 60px",
          display: "grid", gridTemplateColumns: "minmax(220px, 1.3fr) repeat(auto-fit, minmax(140px, 1fr))",
          gap: 32, fontSize: 14,
        }}>
          <div>
            <Wordmark size={18} />
            <div style={{ color: "var(--color-neutral-600)", marginTop: 12, lineHeight: 1.65, fontSize: 13.5 }}>
              {t("productSub")}<br />Mikocheni, Dar es Salaam
            </div>
            <div style={{ display: "flex", gap: 7, marginTop: 16 }}>
              {["ph-linkedin-logo", "ph-x-logo", "ph-envelope-simple"].map((icon) => (
                <span key={icon} className="btn btn-icon" style={{ border: "1px solid var(--vf-line)" }}>
                  <Icon name={icon} />
                </span>
              ))}
            </div>
          </div>
          {CONTENT.footer.map(([title, items]) => (
            <div key={title[0]}>
              <div style={{ fontSize: 11.5, fontWeight: 600, letterSpacing: ".11em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: 13 }}>
                {title[i] ?? title[0]}
              </div>
              {items.map((item) => (
                <div key={item[0]} style={{ padding: "5px 0", color: "var(--color-neutral-700)", fontSize: 13.5 }}>
                  {item[i] ?? item[0]}
                </div>
              ))}
            </div>
          ))}
        </footer>
      </div>
    </div>
  );
}

function Wordmark({ size = 20 }: { size?: number }) {
  const box = Math.round(size * 1.4);
  return (
    <Link href="/" style={{
      display: "flex", alignItems: "center", gap: 9, flex: "none", color: "var(--color-text)",
      fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: size, letterSpacing: "-.03em",
    }}>
      <span className="vf-mark" style={{
        width: box, height: box, fontSize: Math.round(size * .75),
        boxShadow: "0 6px 18px -6px rgba(47,123,246,.9)",
      }}>V</span>
      VouchFlow
    </Link>
  );
}
