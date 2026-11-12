"use client";

import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { Icon } from "@/components/ui";

/**
 * The VouchFlow brand mark on its tile. The size is a default the stylesheet
 * may override, as an inline width would win over every rule.
 */
export function VouchFlowMark({ size = 36 }: { size?: number }) {
  return (
    <span className="vf-login-mark" style={{ "--vf-mark": `${size}px` } as React.CSSProperties} aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- a fixed brand asset; next/image adds nothing here */}
      <img src="/brand/vouchflow-mark.png" alt="" width={446} height={446} decoding="async" />
    </span>
  );
}

const STEPS: { label: MessageKey; state: "done" | "current" | "next" }[] = [
  { label: "flowCreate", state: "done" },
  { label: "flowSign", state: "done" },
  { label: "flowApprove", state: "done" },
  { label: "flowPay", state: "current" },
];

const BARS = [38, 52, 44, 70, 58, 84, 66];

/**
 * The showcase half of sign-in and registration: the product, shown rather
 * than described. A voucher that has just been approved, the notification
 * that said so, and a glance at stock, floating as glass over a dark,
 * softly lit ground. Purely illustrative, so it is hidden from assistive
 * technology; the headline beside it carries the meaning.
 */
export function AuthShowcase({ children }: { children?: React.ReactNode }) {
  const { t } = useApp();

  return (
    <aside className="au-show">
      <div className="au-show-glow" aria-hidden="true" />

      <div className="au-show-brand">
        <VouchFlowMark size={32} />
        <span>VouchFlow</span>
      </div>

      {children ?? (
        <div className="au-stage" aria-hidden="true">
          <div className="au-float au-float-voucher">
            <div className="au-v-head">
              <span className="au-v-num">PV-2026-000041</span>
              <span className="au-v-badge"><Icon name="ph-seal-check" size={13} /> {t("authPreviewApproved")}</span>
            </div>
            <div className="au-v-payee">Highland Freight Services</div>
            <div className="au-v-amount">TZS 3,200,000</div>
            <ol className="au-v-steps">
              {STEPS.map((s) => (
                <li key={s.label} data-state={s.state}>
                  <span className="au-v-dot">{s.state === "done" && <Icon name="ph-check" size={10} weight="bold" />}</span>
                  {t(s.label)}
                </li>
              ))}
            </ol>
          </div>

          <div className="au-float au-float-notice">
            <span className="au-n-avatar">EM</span>
            <span className="au-n-text"><strong>Emmanuel Massawe</strong> {t("authPreviewNotice")}</span>
          </div>

          <div className="au-float au-float-stock">
            <span className="au-s-label">{t("authPreviewStock")}</span>
            <span className="au-s-value">TZS 29.5M</span>
            <span className="au-s-bars">
              {BARS.map((h, i) => <span key={i} style={{ height: `${h}%` }} />)}
            </span>
          </div>
        </div>
      )}

      <div className="au-show-copy">
        <h2>{t("authHeadline")}</h2>
        <p>{t("authLede")}</p>
      </div>
    </aside>
  );
}
