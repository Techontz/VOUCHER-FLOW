"use client";

import Link from "next/link";
import { useState } from "react";
import { download, printBlob, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { formatDate } from "@/lib/format";
import type { Voucher } from "@/lib/types";

/** Print / Download, offered at every workflow stage the step permits. */
export function DocumentActions({ voucher, compact }: { voucher: Voucher; compact?: boolean }) {
  const { t, reportError, toast } = useApp();
  const [busy, setBusy] = useState<"print" | "download" | null>(null);

  const canPrint = voucher.actions?.print ?? false;
  const canDownload = voucher.actions?.download ?? false;
  if (!canPrint && !canDownload) return null;

  async function run(kind: "print" | "download") {
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
    try {
      const blob = await download(`/vouchers/${voucher.id}/pdf/download`);
      const file = new File([blob], `${voucher.number}.pdf`, { type: "application/pdf" });
      const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
      if (nav.share && nav.canShare?.({ files: [file] })) {
        await nav.share({ files: [file], title: voucher.number, text: voucher.purpose });
        return;
      }
      await navigator.clipboard.writeText(window.location.origin + `/vouchers/${voucher.id}`);
      toast("Link copied", "The voucher link is on your clipboard.", "ok");
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

/** A voucher row as used on dashboards and queues. */
export function VoucherCard({ voucher, showActions = true }: { voucher: Voucher; showActions?: boolean }) {
  const { t, locale } = useApp();

  return (
    <div style={{
      border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)",
      padding: "var(--space-4)", display: "grid", gap: "var(--space-3)",
    }}>
      <div style={{ display: "grid", gridTemplateColumns: "minmax(0,1fr) auto", gap: "var(--space-4)", alignItems: "start" }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 13, color: "var(--color-neutral-600)", fontVariantNumeric: "tabular-nums" }}>
            {voucher.number} · {voucher.voucher_type?.label} · {voucher.department?.name ?? "—"} · {formatDate(voucher.voucher_date, locale)}
          </div>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 20, margin: "3px 0" }}>
            <Link href={`/vouchers/${voucher.id}`} style={{ color: "var(--color-text)" }}>{voucher.purpose}</Link>
          </div>
          <div style={{ fontSize: 14.5, color: "var(--color-neutral-700)" }}>
            {voucher.requester?.name} → {voucher.payee}{voucher.payment_method ? ` · ${voucher.payment_method}` : ""}
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 23, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
            {voucher.amount_text}
          </div>
          <span className={`tag ${voucher.status_tag}`} style={{ fontSize: 11.5, marginTop: 4 }}>{voucher.status_label}</span>
        </div>
      </div>

      {showActions && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end", borderTop: "1px solid var(--color-divider)", paddingTop: "var(--space-2)" }}>
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
        </div>
      )}
    </div>
  );
}

/** Compact table used by the list and dashboard "recent" panels. */
export function VoucherTable({ vouchers }: { vouchers: Voucher[] }) {
  const { t, locale } = useApp();

  return (
    <div className="table-wrap">
      <table className="table">
        <thead>
          <tr>
            <th>{t("voucher")}</th>
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
  );
}
