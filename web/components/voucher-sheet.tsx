"use client";

import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime, money } from "@/lib/format";
import { AuthorisationBlock, DocumentStatusMark } from "@/components/stamps";
import type { Company, TimelineRow, Voucher } from "@/lib/types";

/* The document is always ink on paper: it is a preview of what prints, and the
   printed voucher is white whatever appearance the interface is wearing. These
   are therefore literal colours, not theme tokens. */
const INK = "#0b1220";
const BODY = "#33405a";
const MUTED = "#6b7789";
const FAINT = "#98a2b3";
const RULE = "#e2e7ef";
const WASH = "#f6f8fc";

const label: React.CSSProperties = {
  fontSize: 7.5, fontWeight: 800, letterSpacing: ".13em",
  textTransform: "uppercase", color: FAINT,
};

/** One row of the payment-particulars panel. */
function Particular({ term, value, strong }: { term: string; value: React.ReactNode; strong?: boolean }) {
  return (
    <div style={{
      display: "grid", gridTemplateColumns: "82px minmax(0, 1fr)", gap: 8,
      padding: "5px 0", borderBottom: `1px solid ${RULE}`, alignItems: "baseline",
    }}>
      <span style={{ ...label, fontSize: 7, letterSpacing: ".1em" }}>{term}</span>
      <span style={{
        fontSize: strong ? 12 : 10.5,
        fontWeight: strong ? 700 : 500,
        color: strong ? INK : BODY,
        fontVariantNumeric: "tabular-nums",
        overflowWrap: "anywhere",
      }}>{value}</span>
    </div>
  );
}

function MetaCell({ term, value, sub }: { term: string; value: string; sub?: string | null }) {
  return (
    <div style={{ minWidth: 0 }}>
      <div style={label}>{term}</div>
      <div style={{ fontSize: 11.5, fontWeight: 600, color: INK, marginTop: 2, overflowWrap: "anywhere" }}>{value}</div>
      {sub && <div style={{ fontSize: 8.5, color: FAINT, marginTop: 1 }}>{sub}</div>}
    </div>
  );
}

/**
 * The A4 voucher exactly as it prints.
 *
 * The company's own letterhead sits at the top, the narrative runs down the
 * left with the amount immediately beneath the description, and the right
 * column carries the payment particulars — which differ by format, because a
 * bank voucher settles into an account and a cash voucher comes out of a float.
 * The authorisation band closes the page: who prepared, signed, approved and
 * paid, each with their mark.
 */
export function VoucherSheet({ voucher, company }: { voucher: Voucher; company: Company | null }) {
  const { t, locale } = useApp();
  const rows = voucher.timeline ?? [];
  const isCash = voucher.kind === "cash";

  const requestRow = rows.find((r) => r.position === 1) ?? null;
  const signRow = rows.find((r) => r.capabilities?.sign && !r.capabilities?.approve && r.when) ?? null;
  const approveRow = rows.find((r) => r.capabilities?.approve && r.when) ?? null;
  const payRow = rows.find((r) => r.capabilities?.pay && r.when) ?? null;

  const when = (row: TimelineRow | null) => (row?.when ? formatDateTime(row.when, locale) : null);

  const closed = voucher.status === "paid" ? "paid"
    : voucher.status === "rejected" ? "rejected"
    : voucher.status === "changes_requested" ? "returned"
    : null;

  const initial = (company?.name ?? "V").trim().charAt(0).toUpperCase();

  return (
    <div className="vf-sheet">
      {/* the company's colour, carried onto its own paperwork */}
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 4,
        background: company?.primary_color ?? "#2E3192",
      }} />

      {closed && (
        <DocumentStatusMark
          kind={closed}
          date={voucher.paid_at ? formatDate(voucher.paid_at, locale)
            : voucher.rejected_at ? formatDate(voucher.rejected_at, locale) : null}
          reference={voucher.payment_reference}
        />
      )}

      {/* ── letterhead ── */}
      <header style={{
        display: "flex", justifyContent: "space-between", alignItems: "flex-start",
        gap: 24, paddingBottom: 14, borderBottom: `2px solid ${INK}`,
      }}>
        <div style={{ display: "flex", gap: 14, alignItems: "flex-start", minWidth: 0 }}>
          {company?.logo_url ? (
            <img src={company.logo_url} alt=""
              style={{ height: 52, maxWidth: 210, objectFit: "contain", flex: "none" }} />
          ) : (
            <div style={{
              width: 46, height: 46, borderRadius: 8, flex: "none",
              background: company?.primary_color ?? INK, color: "#fff",
              display: "grid", placeItems: "center",
              fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 22,
            }}>{initial}</div>
          )}
          <div style={{ minWidth: 0 }}>
            <div style={{
              fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 17,
              letterSpacing: "-.02em", color: INK, lineHeight: 1.2,
            }}>{company?.legal_name ?? company?.name ?? "VouchFlow"}</div>
            <div style={{ fontSize: 8.5, color: MUTED, lineHeight: 1.5, marginTop: 3 }}>
              {company?.address}
              {(company?.phone || company?.email) && (
                <><br />{[company?.phone, company?.email].filter(Boolean).join(" · ")}</>
              )}
              {(company?.website || company?.tin) && (
                <><br />{[company?.website, company?.tin ? `TIN ${company.tin}` : null].filter(Boolean).join(" · ")}</>
              )}
            </div>
          </div>
        </div>

        <div style={{ textAlign: "right", flex: "none" }}>
          <div style={{
            fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 13,
            letterSpacing: ".1em", textTransform: "uppercase", color: INK,
          }}>
            {voucher.voucher_type?.label ?? t("paymentVoucherStamp")}
          </div>
          <div style={{
            display: "inline-block", marginTop: 4, padding: "2px 8px", borderRadius: 3,
            border: `1px solid ${isCash ? "#c48a1a" : "#2f6fd0"}`,
            color: isCash ? "#8a5a00" : "#1a4fae",
            background: isCash ? "#fff8ec" : "#eef4ff",
            fontSize: 8, fontWeight: 800, letterSpacing: ".14em",
          }}>
            {isCash ? t("cashVoucher").toUpperCase() : t("bankVoucher").toUpperCase()}
          </div>
          <div style={{
            fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 15,
            fontVariantNumeric: "tabular-nums", marginTop: 6, color: INK,
          }}>{voucher.number}</div>
          <div style={{ fontSize: 8, color: FAINT }}>{t("originalPage")}</div>
        </div>
      </header>

      {/* ── who, when, where it is charged ── */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14,
        padding: "11px 0", borderBottom: `1px solid ${RULE}`,
      }}>
        <MetaCell term={t("date")} value={formatDate(voucher.voucher_date, locale)} />
        <MetaCell term={t("department")} value={voucher.department?.name ?? "—"} sub={voucher.cost_centre} />
        <MetaCell term={t("requestedBy")} value={voucher.requester?.name ?? "—"}
          sub={voucher.requester?.job_title} />
        <MetaCell term={t("category")} value={voucher.category ?? "—"} />
      </div>

      {/* ── the substance, with the particulars alongside ── */}
      <div style={{
        display: "grid", gridTemplateColumns: "minmax(0, 1.55fr) minmax(0, 1fr)",
        gap: 20, padding: "13px 0 0", flex: 1, alignItems: "stretch", minHeight: 0,
      }}>
        {/* The left column is the voucher's ruled particulars, the way a
            voucher book is printed: what is being paid for, then the total,
            then the amount written out. Blank rules carry the form down the
            page rather than leaving a hole in the middle of it. */}
        <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
          <div style={label}>{t("payee")}</div>
          <div style={{
            fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 15,
            letterSpacing: "-.015em", color: INK, margin: "2px 0 10px",
          }}>{voucher.payee}</div>

          <table style={{
            width: "100%", borderCollapse: "collapse", flex: 1,
            border: `1px solid ${RULE}`, tableLayout: "fixed",
          }}>
            <thead>
              <tr style={{ background: WASH }}>
                <th style={{ ...label, textAlign: "left", padding: "6px 9px", borderBottom: `1px solid ${RULE}`, color: MUTED }}>
                  {t("particulars")}
                </th>
                <th style={{ ...label, textAlign: "right", padding: "6px 9px", borderBottom: `1px solid ${RULE}`, color: MUTED, width: 108 }}>
                  {t("amount")} · {voucher.currency}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr style={{ verticalAlign: "top" }}>
                <td style={{ padding: "8px 9px", borderBottom: `1px solid ${RULE}` }}>
                  <div style={{ fontSize: 11.5, fontWeight: 600, color: INK }}>{voucher.purpose}</div>
                  {voucher.description && (
                    <p style={{ fontSize: 10, lineHeight: 1.6, color: BODY, margin: "3px 0 0" }}>
                      {voucher.description}
                    </p>
                  )}
                  {voucher.account_ref && (
                    <div style={{ fontSize: 9, color: MUTED, marginTop: 4 }}>
                      {t("reference")}: <span style={{ fontVariantNumeric: "tabular-nums" }}>{voucher.account_ref}</span>
                    </div>
                  )}
                </td>
                <td style={{
                  padding: "8px 9px", borderBottom: `1px solid ${RULE}`, textAlign: "right",
                  fontSize: 12, fontWeight: 600, color: INK, fontVariantNumeric: "tabular-nums",
                }}>
                  {Math.round(voucher.amount).toLocaleString("en-US")}
                </td>
              </tr>

              {/* The form's remaining rules. They keep the page looking like a
                  voucher rather than a half-filled page. */}
              <tr style={{ height: "100%" }}>
                <td style={{ borderBottom: `1px solid ${RULE}` }} />
                <td style={{ borderBottom: `1px solid ${RULE}` }} />
              </tr>
            </tbody>
            <tfoot>
              <tr style={{ background: WASH }}>
                <td style={{
                  padding: "9px 9px", borderTop: `2px solid ${INK}`,
                  ...label, color: INK, fontSize: 8.5,
                }}>{t("totalPayable")}</td>
                <td style={{
                  padding: "9px 9px", borderTop: `2px solid ${INK}`, textAlign: "right",
                  fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 15,
                  letterSpacing: "-.02em", color: INK, fontVariantNumeric: "tabular-nums",
                }}>{Math.round(voucher.amount).toLocaleString("en-US")}</td>
              </tr>
            </tfoot>
          </table>

          <div style={{
            marginTop: 8, border: `1px solid ${RULE}`, borderLeft: `3px solid ${INK}`,
            borderRadius: 3, background: WASH, padding: "7px 10px",
          }}>
            <span style={{ ...label, fontSize: 7 }}>{t("amountWords")}</span>
            <div style={{ fontSize: 10.5, fontStyle: "italic", color: INK, marginTop: 1 }}>
              {voucher.amount_in_words ?? money(voucher.amount, voucher.currency)}
            </div>
          </div>
        </div>

        {/* The right column earns its place: everything a payments clerk needs
            to actually move the money, and nothing else. */}
        <aside style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{
            border: `1px solid ${RULE}`, borderRadius: 5, overflow: "hidden", background: "#fff",
          }}>
            <div style={{
              background: WASH, borderBottom: `1px solid ${RULE}`, padding: "6px 10px",
              ...label, color: MUTED,
            }}>{t("paymentParticulars")}</div>

            <div style={{ padding: "2px 10px 8px" }}>
              <Particular term={t("amount")} value={voucher.amount_text} strong />
              <Particular term={t("currency")} value={voucher.currency} />
              <Particular term={t("paymentMethod")} value={voucher.payment_method ?? (isCash ? t("cash") : t("bank"))} />
              <Particular term={t("voucherType")} value={voucher.voucher_type?.label ?? "—"} />
              <Particular term={t("reference")} value={voucher.account_ref || "—"} />

              {isCash ? (
                <>
                  <Particular term={t("payFrom")} value={voucher.cash_float ?? "Petty cash float"} />
                  <Particular term={t("receivedBy")} value={voucher.received_by ?? "—"} />
                </>
              ) : (
                <>
                  <Particular term={t("bank")} value={voucher.payee_bank ?? "—"} />
                  <Particular term={t("accountName")} value={voucher.payee_account_name ?? voucher.payee} />
                  <Particular term={t("accountNo")} value={voucher.payee_account_number ?? "—"} />
                  <Particular term={t("branch")} value={voucher.payee_bank_branch ?? "—"} />
                  {voucher.cheque_number && <Particular term={t("chequeNo")} value={voucher.cheque_number} />}
                </>
              )}

              {voucher.payment_reference && (
                <Particular term={t("paymentRef")} value={voucher.payment_reference} />
              )}
            </div>

            {/* A bank voucher is drawn on the company's own account; saying so
                on the document is what makes it a bank voucher. */}
            {!isCash && company?.bank_account_number && (
              <div style={{ borderTop: `1px solid ${RULE}`, background: WASH, padding: "7px 10px" }}>
                <div style={{ ...label, fontSize: 7 }}>{t("drawnOn")}</div>
                <div style={{ fontSize: 9.5, color: BODY, lineHeight: 1.5, marginTop: 2 }}>
                  <strong style={{ color: INK }}>{company.bank_name}</strong><br />
                  {company.bank_account_name}<br />
                  <span style={{ fontVariantNumeric: "tabular-nums" }}>{company.bank_account_number}</span>
                  {company.bank_branch ? ` · ${company.bank_branch}` : ""}
                </div>
              </div>
            )}
          </div>

          {/* Supporting papers belong beside the money they justify. */}
          <div style={{
            border: `1px solid ${RULE}`, borderRadius: 5, background: "#fff",
            padding: "7px 10px", flex: 1, minHeight: 58,
          }}>
            <div style={{ ...label, fontSize: 7 }}>{t("supportingDocs")}</div>
            {voucher.attachments && voucher.attachments.length > 0 ? (
              <ol style={{ margin: "4px 0 0", padding: 0, listStyle: "none", fontSize: 9.5, color: BODY }}>
                {voucher.attachments.map((file, i) => (
                  <li key={file.id} style={{ display: "flex", gap: 5, padding: "2px 0" }}>
                    <span style={{ color: FAINT, fontVariantNumeric: "tabular-nums" }}>{i + 1}.</span>
                    <span style={{ flex: 1, overflowWrap: "anywhere" }}>{file.name}</span>
                  </li>
                ))}
              </ol>
            ) : (
              <div style={{ fontSize: 9.5, color: "#c2c9d6", marginTop: 4 }}>{t("noneAttached")}</div>
            )}
          </div>
        </aside>
      </div>

      {/* ── remarks ── */}
      <div style={{ marginTop: 12 }}>
        <div style={label}>{t("remarks")}</div>
        <div style={{
          marginTop: 3, border: `1px solid ${RULE}`, borderRadius: 4,
          padding: "7px 10px", fontSize: 10, lineHeight: 1.6, color: BODY,
          background: "#fff", minHeight: 34,
        }}>
          {voucher.notes_to_approver
            ?? remarksFromTrail(rows)
            ?? <span style={{ color: "#c2c9d6" }}>—</span>}
        </div>
      </div>

      {/* ── authorisation ── */}
      <div style={{ ...label, margin: "0 0 7px" }}>{t("authorisation")}</div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 9 }}>
        <AuthorisationBlock
          caption={t("preparedBy")}
          name={voucher.requester?.name}
          title={voucher.requester?.job_title}
          date={when(requestRow) ?? (voucher.submitted_at ? formatDateTime(voucher.submitted_at, locale) : null)}
          note={t("notSubmitted")}
        />
        <AuthorisationBlock
          caption={t("signedByName")}
          name={signRow?.person}
          title={signRow?.person_title}
          date={when(signRow)}
          signature={signRow?.signature}
          stamp="signed"
          note={t("awaitingSignature")}
        />
        <AuthorisationBlock
          caption={t("approvedByName")}
          name={approveRow?.person}
          title={approveRow?.person_title}
          date={when(approveRow)}
          signature={approveRow?.signature}
          stamp={voucher.status === "rejected" ? "rejected" : "approved"}
          note={t("awaitingApprovalAct")}
          emphasis
        />
        <AuthorisationBlock
          caption={isCash ? t("paidReceivedBy") : t("paidBy")}
          name={payRow?.person ?? voucher.paid_by}
          title={payRow?.person_title}
          date={when(payRow) ?? (voucher.paid_at ? formatDateTime(voucher.paid_at, locale) : null)}
          signature={payRow?.signature}
          stamp="paid"
          reference={voucher.payment_reference}
          note={t("awaitingPayment")}
        />
      </div>

      {/* ── footer ── */}
      <footer style={{
        display: "flex", alignItems: "flex-end", justifyContent: "space-between",
        gap: 20, marginTop: 14, paddingTop: 12, borderTop: `1px solid ${RULE}`,
      }}>
        <div style={{ fontSize: 8, color: MUTED, maxWidth: "62ch", lineHeight: 1.55 }}>
          {company?.voucher_footer_text ?? "This voucher is valid only with the authorisations above."}
          {voucher.verification_code && (
            <><br />{t("verificationCode")} <strong style={{ color: INK }}>{voucher.verification_code}</strong></>
          )}
        </div>
        <div style={{ display: "flex", alignItems: "flex-end", gap: 9, flex: "none" }}>
          <div style={{ ...label, fontSize: 6.5, textAlign: "right", paddingBottom: 2 }}>
            Scan to<br />verify
          </div>
          <VerificationGlyph seed={voucher.verification_code ?? voucher.number} />
        </div>
      </footer>
    </div>
  );
}

/** The most recent decision note, which is what a remarks box would carry. */
function remarksFromTrail(rows: TimelineRow[]): string | null {
  const withComment = rows.filter((r) => r.comment && r.when);
  return withComment.length ? withComment[withComment.length - 1].comment : null;
}

/**
 * A deterministic glyph standing in for the verification QR code, derived from
 * the voucher's own code so it is stable per voucher. The code itself is
 * printed beside it and is what actually verifies.
 */
function VerificationGlyph({ seed }: { seed: string }) {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;

  const finder = new Set([0, 1, 2, 7, 8, 9, 14, 15, 16, 4, 5, 6, 11, 12, 13, 18, 19, 20, 28, 29, 30, 35, 36, 37, 42, 43, 44]);
  const cells = Array.from({ length: 49 }, (_, i) =>
    finder.has(i) ? i % 3 !== 1 : ((hash >> (i % 30)) & 1) === 1);

  return (
    <div aria-hidden="true" style={{
      padding: 4, background: "#fff", border: `1px solid ${RULE}`, borderRadius: 4,
      display: "grid", gridTemplateColumns: "repeat(7, 5px)", gridAutoRows: 5, gap: 1.5,
    }}>
      {cells.map((on, i) => (
        <div key={i} style={{ width: 5, height: 5, background: on ? INK : "#fff" }} />
      ))}
    </div>
  );
}
