"use client";

import Link from "next/link";
import { useState } from "react";
import { API_MODE, download, printBlob, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { formatDate } from "@/lib/format";
import type { Voucher } from "@/lib/types";

/**
 * Print / PDF / Share, offered at every workflow stage the step permits.
 *
 * Phase 1 prints the A4 sheet rendered on the voucher page through the browser
 * — which is also how a reader saves it as a PDF. Once the backend generates
 * the document server-side, `API_MODE === "live"` takes the fetch branch and
 * nothing else here changes.
 */
export function DocumentActions({ voucher, compact }: { voucher: Voucher; compact?: boolean }) {
  const { t, reportError, toast } = useApp();
  const [busy, setBusy] = useState<"print" | "download" | null>(null);

  const canPrint = voucher.actions?.print ?? false;
  const canDownload = voucher.actions?.download ?? false;
  if (!canPrint && !canDownload) return null;

  const onDetailPage = typeof window !== "undefined"
    && window.location.pathname === `/vouchers/${voucher.id}`;

  async function run(kind: "print" | "download") {
    if (API_MODE === "mock") {
      // The sheet only exists on the voucher's own page.
      if (!onDetailPage) {
        window.location.href = `/vouchers/${voucher.id}?print=1`;
        return;
      }
      if (kind === "download") {
        toast(t("downloadPdf"), "Choose “Save as PDF” as the destination in the print dialog.", "warn");
      }
      window.setTimeout(() => window.print(), 120);
      return;
    }

    setBusy(kind);
    try {
      const blob = await download(`/vouchers/${voucher.id}/pdf${kind === "download" ? "/download" : ""}`);
      if (kind === "download") {
        saveBlob(blob, `${voucher.number}.pdf`);
        toast("PDF downloaded", `${voucher.number}.pdf`, "ok");
      } else {
        printBlob(blob);
      }
    } catch (err) {
      reportError(err, "Could not produce the PDF");
    } finally {
      setBusy(null);
    }
  }

  async function share() {
    const url = `${window.location.origin}/vouchers/${voucher.id}`;
    try {
      if (navigator.share) {
        await navigator.share({ title: voucher.number, text: voucher.purpose, url });
        return;
      }
      await navigator.clipboard.writeText(url);
      toast(t("copyLink"), "The voucher link is on your clipboard.", "ok");
    } catch (err) {
      if ((err as Error)?.name !== "AbortError") reportError(err, "Could not share the voucher");
    }
  }

  const size = compact ? "btn-sm" : "";

  return (
    <>
      {canPrint && (
        <button className={`btn btn-secondary ${size}`} onClick={() => run("print")} disabled={busy !== null}>
          <Icon name="ph-printer" size={15} /> {t("print")}
        </button>
      )}
      {canDownload && (
        <button className={`btn btn-secondary ${size}`} onClick={() => run("download")} disabled={busy !== null}>
          <Icon name="ph-file-pdf" size={15} /> PDF
        </button>
      )}
      {canDownload && !compact && (
        <button className="btn btn-secondary" onClick={share}>
          <Icon name="ph-share-network" size={15} /> {t("share")}
        </button>
      )}
    </>
  );
}

/** Bank or cash — the two corporate voucher formats. */
export function KindChip({ kind, size = 11.5 }: { kind: "bank" | "cash"; size?: number }) {
  const { t } = useApp();
  const cash = kind === "cash";
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 4, flex: "none",
      fontSize: size, fontWeight: 600, letterSpacing: ".04em", textTransform: "uppercase",
      padding: "2px 7px", borderRadius: 6,
      background: cash ? "color-mix(in srgb, var(--vf-warn) 15%, transparent)" : "color-mix(in srgb, var(--color-accent-500) 15%, transparent)",
      color: cash ? "var(--vf-warn)" : "var(--color-accent-600)",
    }}>
      <Icon name={cash ? "ph-money" : "ph-bank"} size={size} />
      {cash ? t("cash") : t("bank")}
    </span>
  );
}

/** A voucher row as used on dashboards and queues. */
export function VoucherCard({ voucher, showActions = true }: { voucher: Voucher; showActions?: boolean }) {
  const { t, locale } = useApp();

  return (
    <div className="vf-panel" style={{ padding: "var(--space-4)", display: "grid", gap: "var(--space-3)" }}>
      <div style={{ display: "grid", gridTemplateColumns: "minmax(0,1fr) auto", gap: "var(--space-4)", alignItems: "start" }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", fontSize: 13, color: "var(--color-neutral-600)", fontVariantNumeric: "tabular-nums" }}>
            <KindChip kind={voucher.kind} />
            <span>{voucher.number} · {voucher.department?.name ?? "—"} · {formatDate(voucher.voucher_date, locale)}</span>
          </div>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 20, margin: "5px 0 3px", letterSpacing: "-.02em" }}>
            <Link href={`/vouchers/${voucher.id}`} style={{ color: "var(--color-text)" }}>{voucher.purpose}</Link>
          </div>
          <div style={{ fontSize: 14.5, color: "var(--color-neutral-700)" }}>
            {voucher.requester?.name} → {voucher.payee}{voucher.payment_method ? ` · ${voucher.payment_method}` : ""}
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 23, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap", letterSpacing: "-.03em" }}>
            {voucher.amount_text}
          </div>
          <span className={`tag ${voucher.status_tag}`} style={{ fontSize: 11.5, marginTop: 4 }}>{voucher.status_label}</span>
        </div>
      </div>

      {showActions && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end", borderTop: "1px solid var(--vf-line)", paddingTop: "var(--space-2)" }}>
          <DocumentActions voucher={voucher} compact />
          <Link className="btn btn-secondary btn-sm" href={`/vouchers/${voucher.id}`}>{t("review")}</Link>
          {voucher.actions?.sign && (
            <Link className="btn btn-primary btn-sm" href={`/vouchers/${voucher.id}`}>
              <Icon name="ph-signature" size={14} /> {t("sign")}
            </Link>
          )}
          {voucher.actions?.submit_signed && (
            <Link className="btn btn-primary btn-sm" href={`/vouchers/${voucher.id}`}>
              <Icon name="ph-paper-plane-tilt" size={14} /> {t("submitSigned")}
            </Link>
          )}
          {voucher.actions?.approve && (
            <Link className="btn btn-primary btn-sm" href={`/vouchers/${voucher.id}`}>
              <Icon name="ph-seal-check" size={14} /> {t("approve")}
            </Link>
          )}
          {voucher.actions?.pay && (
            <Link className="btn btn-primary btn-sm" href={`/vouchers/${voucher.id}`}>
              <Icon name="ph-wallet" size={14} /> {t("recordPayment")}
            </Link>
          )}
        </div>
      )}
    </div>
  );
}

/** Compact table used by the list and dashboard "recent" panels. */
export function VoucherTable({ vouchers }: { vouchers: Voucher[] }) {
  const { t, locale } = useApp();

  return (
    <div className="vf-panel" style={{ overflow: "hidden" }}>
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>{t("voucher")}</th>
              <th>{t("voucherKind")}</th>
              <th>{t("purpose")}</th>
              <th>{t("payee")}</th>
              <th style={{ textAlign: "right" }}>{t("amount")}</th>
              <th>{t("status")}</th>
              <th>{t("date")}</th>
            </tr>
          </thead>
          <tbody>
            {vouchers.map((voucher) => (
              <tr key={voucher.id} className="is-clickable"
                onClick={(e) => {
                  if ((e.target as HTMLElement).closest("a")) return;
                  window.location.href = `/vouchers/${voucher.id}`;
                }}>
                <td style={{ fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                  <Link href={`/vouchers/${voucher.id}`}>{voucher.number}</Link>
                </td>
                <td><KindChip kind={voucher.kind} size={11} /></td>
                <td style={{ minWidth: 180 }}>{voucher.purpose}</td>
                <td style={{ color: "var(--color-neutral-700)" }}>{voucher.payee}</td>
                <td style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{voucher.amount_text}</td>
                <td><span className={`tag ${voucher.status_tag}`}>{voucher.status_label}</span></td>
                <td style={{ whiteSpace: "nowrap", color: "var(--color-neutral-700)" }}>{formatDate(voucher.voucher_date, locale)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
