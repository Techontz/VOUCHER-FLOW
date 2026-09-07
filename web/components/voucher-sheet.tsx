"use client";

import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime, money } from "@/lib/format";
import type { Company, TimelineRow, Voucher } from "@/lib/types";

/* The printed sheet is always light: it represents ink on A4 paper, and the
   generated PDF is white whatever appearance the interface is wearing. These
   are therefore literal colours, not theme tokens. */
const INK = "#0b1220";
const MUTED = "#475467";
const FAINT = "#98a2b3";
const RULE = "#e4e8f0";

const label: React.CSSProperties = {
  fontSize: 9, fontWeight: 700, letterSpacing: ".11em",
  textTransform: "uppercase", color: FAINT,
};

function Cell({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <div style={label}>{title}</div>
      <div style={{ fontSize: 13.5, fontWeight: 500, marginTop: 3 }}>{children}</div>
    </div>
  );
}

/** One authorisation box: signature above, role and timestamp below. */
function SignatureBox({
  row, caption, highlight, locale,
}: { row: TimelineRow | null; caption: string; highlight?: boolean; locale: "en" | "sw" }) {
  const signed = !!row?.when;
  return (
    <div style={{
      border: `1px solid ${highlight ? "#cfe0ff" : RULE}`, borderRadius: 10, padding: 14,
      background: highlight ? "#f5f9ff" : "#fbfcfe", breakInside: "avoid",
    }}>
      <div style={{ height: 44, display: "flex", alignItems: "flex-end" }}>
        {row?.signature ? (
          <img src={row.signature} alt="" style={{ maxHeight: 44, maxWidth: "100%" }} />
        ) : (
          <span style={{
            fontFamily: "var(--font-heading)", fontStyle: "italic", fontWeight: 500,
            fontSize: 19, color: signed ? INK : "transparent",
          }}>{signed ? row?.person : "—"}</span>
        )}
      </div>
      <div style={{
        borderTop: `1px solid ${highlight ? "#b3d0ff" : "#d0d5dd"}`,
        paddingTop: 7, marginTop: 4, fontSize: 10.5, lineHeight: 1.5,
      }}>
        <strong style={{ fontWeight: 600 }}>{caption}</strong><br />
        <span style={{ color: MUTED }}>
          {row?.person_title ?? "—"}<br />
          {row?.when ? formatDateTime(row.when, locale) : (locale === "sw" ? "Inasubiri" : "Pending")}
        </span>
      </div>
    </div>
  );
}

/**
 * The A4 payment/cash voucher exactly as it prints.
 *
 * Rendered on screen as a preview and, in Phase 1, printed straight from the
 * browser — the print stylesheet in globals.css hides everything else. When the
 * backend lands, the same layout is what the server-side PDF reproduces.
 */
export function VoucherSheet({ voucher, company }: { voucher: Voucher; company: Company | null }) {
  const { t, locale } = useApp();
  const rows = voucher.timeline ?? [];

  const isCash = voucher.kind === "cash";
  const requestRow = rows.find((r) => r.position === 1) ?? null;
  const signRow = rows.find((r) => r.capabilities?.sign && !r.capabilities?.approve) ?? null;
  const approveRow = rows.find((r) => r.capabilities?.approve) ?? null;
  const payRow = rows.find((r) => r.capabilities?.pay) ?? null;

  const stamp = isCash
    ? { bg: "#fff4e6", fg: "#a5590a", text: t("cashVoucher") }
    : { bg: "#eaf2ff", fg: "#1a4fae", text: t("bankVoucher") };

  const payeeLine = isCash
    ? `${locale === "sw" ? "Fedha taslimu" : "Cash release"} · ${voucher.account_ref || (locale === "sw" ? "Mfuko wa ofisi" : "Petty cash float")}`
    : voucher.account_ref || (locale === "sw" ? "Uhamisho wa benki" : "Bank transfer");

  const initial = (company?.name ?? "V").trim().charAt(0).toUpperCase();

  return (
    <div className="vf-sheet">
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 5,
        background: "linear-gradient(90deg, #0b1220 0%, #1a4fae 42%, #22a7e8 72%, #22d3ee 100%)",
      }} />

      {/* letterhead */}
      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "flex-start",
        gap: 30, paddingBottom: 20, borderBottom: `2px solid ${INK}`,
      }}>
        <div style={{ display: "flex", gap: 15, alignItems: "center", minWidth: 0 }}>
          <div style={{
            width: 50, height: 50, borderRadius: 12, background: INK, color: "#fff",
            display: "grid", placeItems: "center", overflow: "hidden", flex: "none",
            fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 24, letterSpacing: "-.03em",
          }}>
            {company?.logo_url
              ? <img src={company.logo_url} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              : initial}
          </div>
          <div style={{ minWidth: 0 }}>
            <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 21, letterSpacing: "-.032em" }}>
              {company?.name ?? "VouchFlow"}
            </div>
            <div style={{ fontSize: 11, color: "#667085", lineHeight: 1.55, marginTop: 2 }}>
              {company?.address}
              {company?.phone && <><br />{company.phone}{company.email ? ` · ${company.email}` : ""}</>}
            </div>
          </div>
        </div>
        <div style={{ textAlign: "right", flex: "none" }}>
          <div style={{
            display: "inline-block", padding: "5px 11px", borderRadius: 6,
            background: stamp.bg, color: stamp.fg,
            fontSize: 10, fontWeight: 700, letterSpacing: ".13em", textTransform: "uppercase",
          }}>{stamp.text}</div>
          <div style={{
            fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 19,
            fontVariantNumeric: "tabular-nums", marginTop: 7, letterSpacing: "-.025em",
          }}>{voucher.number}</div>
          <div style={{ fontSize: 10.5, color: FAINT, marginTop: 1 }}>{t("originalPage")}</div>
        </div>
      </div>

      {/* who and when */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 18,
        padding: "22px 0", borderBottom: `1px solid ${RULE}`,
      }}>
        <Cell title={t("date")}>{formatDate(voucher.voucher_date, locale)}</Cell>
        <Cell title={t("department")}>{voucher.department?.name ?? "—"}</Cell>
        <Cell title={t("requestedBy")}>
          {voucher.requester?.name ?? "—"}
          <div style={{ fontSize: 10.5, color: FAINT, fontWeight: 400 }}>
            {voucher.requester?.job_title ?? ""}
          </div>
        </Cell>
        <Cell title={t("costCentre")}>{voucher.cost_centre ?? "—"}</Cell>
      </div>

      {/* payee */}
      <div style={{ display: "flex", gap: 30, padding: "22px 0 20px", borderBottom: `1px solid ${RULE}`, flexWrap: "wrap" }}>
        <div style={{ flex: "1 1 260px", minWidth: 0 }}>
          <div style={label}>{t("payee")}</div>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 18, letterSpacing: "-.025em", marginTop: 3 }}>
            {voucher.payee}
          </div>
          <div style={{ fontSize: 11.5, color: MUTED, marginTop: 3 }}>{payeeLine}</div>
        </div>
        <div style={{ flex: "none", textAlign: "right" }}>
          <div style={label}>{t("paymentMethod")}</div>
          <div style={{ fontSize: 13.5, fontWeight: 500, marginTop: 3 }}>
            {voucher.payment_method ?? (isCash ? t("cash") : t("bank"))}
          </div>
        </div>
      </div>

      {/* line items — one line in the prototype, as the design shows */}
      <table style={{ width: "100%", borderCollapse: "collapse", marginTop: 20 }}>
        <thead>
          <tr style={{ background: "#f7f9fc" }}>
            <th style={{ ...label, textAlign: "left", padding: "10px 12px", borderBottom: "1px solid #d0d5dd", color: "#667085" }}>{t("description")}</th>
            <th style={{ ...label, textAlign: "left", padding: "10px 12px", borderBottom: "1px solid #d0d5dd", color: "#667085", width: 110 }}>{t("reference")}</th>
            <th style={{ ...label, textAlign: "right", padding: "10px 12px", borderBottom: "1px solid #d0d5dd", color: "#667085", width: 130 }}>
              {t("amount")} ({voucher.currency})
            </th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td style={{ padding: "14px 12px", verticalAlign: "top", borderBottom: "1px solid #eef1f6", lineHeight: 1.55 }}>
              <strong style={{ fontWeight: 600 }}>{voucher.purpose}</strong>
              {voucher.description && <><br />{voucher.description}</>}
            </td>
            <td style={{ padding: "14px 12px", verticalAlign: "top", borderBottom: "1px solid #eef1f6", fontVariantNumeric: "tabular-nums", color: MUTED }}>
              {voucher.account_ref ?? "—"}
            </td>
            <td style={{ padding: "14px 12px", textAlign: "right", borderBottom: "1px solid #eef1f6", fontVariantNumeric: "tabular-nums", fontWeight: 500 }}>
              {Math.round(voucher.amount).toLocaleString("en-US")}
            </td>
          </tr>
        </tbody>
      </table>

      <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
        <div style={{
          width: 300, maxWidth: "100%", borderRadius: 10, background: INK, color: "#fff",
          padding: "14px 18px", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16,
        }}>
          <span style={{ ...label, color: FAINT, letterSpacing: ".12em", fontSize: 10 }}>{t("totalPayable")}</span>
          <span style={{
            fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 23,
            fontVariantNumeric: "tabular-nums", letterSpacing: "-.035em",
          }}>{Math.round(voucher.amount).toLocaleString("en-US")}</span>
        </div>
      </div>

      <div style={{ padding: "18px 0", marginTop: 6, borderTop: `1px solid ${RULE}`, borderBottom: `1px solid ${RULE}` }}>
        <div style={label}>{t("amountWords")}</div>
        <div style={{ fontStyle: "italic", fontSize: 14, color: "#344054", marginTop: 3 }}>
          {voucher.amount_in_words ?? money(voucher.amount, voucher.currency)}
        </div>
      </div>

      {/* payment record */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginTop: 22,
        padding: "14px 16px", borderRadius: 10, background: "#f7f9fc", border: `1px solid ${RULE}`,
      }}>
        <div>
          <div style={label}>{t("paymentRef")}</div>
          <div style={{ fontSize: 12.5, fontWeight: 500, fontVariantNumeric: "tabular-nums", marginTop: 2 }}>
            {voucher.payment_reference ?? "—"}
          </div>
        </div>
        <div>
          <div style={label}>{t("paidOn")}</div>
          <div style={{ fontSize: 12.5, fontWeight: 500, marginTop: 2 }}>
            {voucher.paid_at ? formatDateTime(voucher.paid_at, locale) : (locale === "sw" ? "Inasubiri" : "Pending")}
          </div>
        </div>
        <div>
          <div style={label}>{t("paidBy")}</div>
          <div style={{ fontSize: 12.5, fontWeight: 500, marginTop: 2 }}>{voucher.paid_by ?? "—"}</div>
        </div>
      </div>

      {/* authorisation */}
      <div style={{ ...label, margin: "26px 0 14px" }}>{t("authorisation")}</div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14 }}>
        <SignatureBox row={requestRow} caption={t("preparedBy")} locale={locale} />
        <SignatureBox row={signRow} caption={t("signedByHod")} locale={locale} />
        <SignatureBox row={approveRow} caption={t("approvedByMgr")} highlight locale={locale} />
        <SignatureBox row={payRow} caption={isCash ? t("receivedBy") : t("cashierSig")} locale={locale} />
      </div>

      <div style={{
        display: "flex", alignItems: "flex-end", justifyContent: "space-between",
        gap: 24, marginTop: 44, borderTop: `1px solid ${RULE}`, paddingTop: 16, flexWrap: "wrap",
      }}>
        <div style={{ fontSize: 10, color: "#667085", maxWidth: "54ch", lineHeight: 1.6 }}>
          {company?.voucher_footer_text
            ?? "This voucher is valid only with the signatures above."}<br />
          {voucher.verification_code && (
            <>Verification code <strong style={{ color: INK }}>{voucher.verification_code}</strong>.</>
          )}
        </div>
        <div style={{ display: "flex", alignItems: "flex-end", gap: 12, flex: "none" }}>
          <div style={{ ...label, textAlign: "right", letterSpacing: ".1em", paddingBottom: 2 }}>
            Scan to<br />verify
          </div>
          <VerificationGlyph seed={voucher.verification_code ?? voucher.number} />
        </div>
      </div>
    </div>
  );
}

/**
 * A deterministic 7×7 glyph standing in for the verification QR code. It is
 * derived from the voucher's own verification code, so it is stable per
 * voucher; the real code is printed beside it and is what actually verifies.
 */
function VerificationGlyph({ seed }: { seed: string }) {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;

  const cells = Array.from({ length: 49 }, (_, i) => {
    const corner = [0, 1, 2, 7, 8, 9, 14, 15, 16, 4, 5, 6, 11, 12, 13, 18, 19, 20, 28, 29, 30, 35, 36, 37, 42, 43, 44]
      .includes(i);
    return corner ? i % 3 !== 1 : ((hash >> (i % 30)) & 1) === 1;
  });

  return (
    <div style={{
      padding: 6, background: "#fff", border: `1px solid ${RULE}`, borderRadius: 8,
      display: "grid", gridTemplateColumns: "repeat(7, 8px)", gridAutoRows: 8, gap: 2,
    }} aria-hidden="true">
      {cells.map((on, i) => (
        <div key={i} style={{ width: 8, height: 8, background: on ? INK : "#fff", borderRadius: 1 }} />
      ))}
    </div>
  );
}
