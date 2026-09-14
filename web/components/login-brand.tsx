"use client";

import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { Icon } from "@/components/ui";

/**
 * The branded half of the sign-in screen.
 *
 * Its job is the five-second read: this is where a company takes a voucher
 * from creation, through signature and approval, to payment. So beyond the
 * headline it shows the route itself rather than describing it.
 *
 * It renders two blocks — the hero, and the detail beneath it — instead of one.
 * On a wide screen they stack inside one navy column. On a phone the column
 * dissolves (display: contents) and the sign-in form is ordered between them,
 * so nobody has to scroll past a feature list to reach the email field.
 *
 * The route shown is the default one, and is illustrative: the note beneath it
 * says each company configures its own.
 */

const FEATURES: { icon: string; title: MessageKey; sub: MessageKey }[] = [
  { icon: "ph-shield-check", title: "loginFeat1", sub: "loginFeat1Sub" },
  { icon: "ph-clock-counter-clockwise", title: "loginFeat2", sub: "loginFeat2Sub" },
  { icon: "ph-flow-arrow", title: "loginFeat3", sub: "loginFeat3Sub" },
];

const FLOW: { icon: string; action: MessageKey; role: MessageKey }[] = [
  { icon: "ph-note-pencil", action: "flowCreate", role: "flowEmployee" },
  { icon: "ph-signature", action: "flowSign", role: "flowHod" },
  { icon: "ph-seal-check", action: "flowApprove", role: "flowCeo" },
  { icon: "ph-hand-coins", action: "flowPay", role: "flowFinance" },
];

export function VouchFlowMark({ size = 36 }: { size?: number }) {
  // A V drawn as a tick: the mark reads as the product's outcome — approved.
  return (
    <svg className="vf-login-mark" width={size} height={size} viewBox="0 0 36 36" aria-hidden="true">
      <rect x="0.5" y="0.5" width="35" height="35" rx="10" />
      <path d="M10.5 12.5 17 24.5 26 10.5" />
    </svg>
  );
}

export function LoginBrand() {
  const { t } = useApp();

  return (
    <div className="vf-login-brand">
      <section className="vf-login-hero">
        <div className="vf-login-wordmark">
          <VouchFlowMark />
          <span>VouchFlow</span>
        </div>

        <p className="vf-login-eyebrow">{t("loginEyebrow")}</p>

        <h2 className="vf-login-headline">
          <span>{t("loginLine1")}</span>{" "}
          <span>{t("loginLine2")}</span>{" "}
          <span className="vf-login-highlight">{t("loginLine3")}</span>
        </h2>

        <p className="vf-login-lede">{t("loginBody")}</p>
      </section>

      <section className="vf-login-detail">
        <ul className="vf-login-features">
          {FEATURES.map((feature, index) => (
            <li key={feature.title} className="vf-login-feature">
              <div className="vf-login-feature-top">
                <Icon name={feature.icon} size={19} />
                <span className="vf-login-feature-num">{String(index + 1).padStart(2, "0")}</span>
              </div>
              <strong>{t(feature.title)}</strong>
              <span>{t(feature.sub)}</span>
            </li>
          ))}
        </ul>

        <div className="vf-login-flow">
          <p className="vf-login-eyebrow">{t("loginFlowTitle")}</p>
          <ol className="vf-login-route">
            {FLOW.map((step, index) => (
              <li key={step.action} className="vf-login-stop" data-state={index < 2 ? "done" : index === 2 ? "current" : "next"}>
                <span className="vf-login-stop-icon">
                  <Icon name={step.icon} size={18} />
                </span>
                <strong>{t(step.action)}</strong>
                <span>{t(step.role)}</span>
              </li>
            ))}
          </ol>
          <p className="vf-login-flow-note">{t("loginFlowNote")}</p>
        </div>

        <div className="vf-login-trust">
          <span className="vf-login-trust-icon"><Icon name="ph-lock-key" size={20} /></span>
          <div>
            <strong>{t("loginTrustTitle")}</strong>
            <span>{t("loginTrustBody")}</span>
          </div>
        </div>
      </section>
    </div>
  );
}
