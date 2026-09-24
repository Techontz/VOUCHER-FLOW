"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { API_MODE, download, printBlob, saveBlob } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Icon, type Tone } from "@/components/ui";
import { formatDate, formatDateTime } from "@/lib/format";
import { deriveProgress, type ProgressStep } from "@/lib/progress";
import { useWorkflows } from "@/lib/use-workflows";
import type { MessageKey } from "@/lib/i18n";
import type { TimelineRow, Voucher } from "@/lib/types";

/* ───────────────────────────────────────────────────────────── status ── */

/**
 * The five status tones, keyed on the backend's status_key.
 *
 * Deliberately few. In progress is blue whoever holds it; a finished voucher is
 * green; something that needs the requester back is amber; a refusal is red.
 * The label carries the detail — "Awaiting HOD signature" — the colour only
 * carries the category.
 */
export function statusTone(key: string | null | undefined): Tone {
  switch (key) {
    case "paid":
    case "awaiting_payment":
      return "ok";
    case "changes_requested":
      return "warn";
    case "rejected":
      return "bad";
    case "draft":
    case "cancelled":
      return "neutral";
    default:
      return "info";
  }
}

export function StatusBadge({ voucher, large }: { voucher: Pick<Voucher, "status_key" | "status_label">; large?: boolean }) {
  return (
    <span className={`badge tone-${statusTone(voucher.status_key)}${large ? " badge-lg" : ""}`}>
      {voucher.status_label}
    </span>
  );
}

/** Bank or cash — the two corporate voucher formats. */
export function KindChip({ kind }: { kind: "bank" | "cash"; size?: number }) {
  const { t } = useApp();
  const cash = kind === "cash";
  return (
    <span className="vf-kind">
      <Icon name={cash ? "ph-money" : "ph-bank"} />
      {cash ? t("cash") : t("bank")}
    </span>
  );
}

/* ─────────────────────────────────────────────────────────── progress ── */

const MARK: Record<ProgressStep["state"], string> = {
  done: "ph-check",
  rejected: "ph-x",
  current: "",
  pending: "",
};

/** The approval route on one line: ✓ Prepared — ✓ HOD — ● MD — ○ Finance. */
export function ProgressSteps({ steps }: { steps: ProgressStep[] }) {
  if (!steps.length) return null;
  return (
    <ol className="vf-steps" aria-label="Approval progress">
      {steps.map((step, index) => (
        <li key={step.key} style={{ display: "contents" }}>
          {index > 0 && <span className="vf-step-sep" aria-hidden="true" />}
          <span className="vf-step" data-state={step.state}>
            <span className="vf-step-mark">{MARK[step.state] && <Icon name={MARK[step.state]} size={10} />}</span>
            <span>{step.label}</span>
            <span className="sr-only">
              {step.state === "done" ? "complete" : step.state === "current" ? "in progress" : step.state === "rejected" ? "rejected" : "not started"}
            </span>
          </span>
        </li>
      ))}
    </ol>
  );
}

/**
 * The full approval ladder for one voucher, from the backend's own timeline:
 * who prepared it, who signed, who approved, who paid — and when.
 */
export function ApprovalTrack({ rows, youActHere }: { rows: TimelineRow[]; youActHere?: boolean }) {
  const { t, locale } = useApp();

  return (
    <ol className="vf-track">
      {rows.map((row, index) => {
        const name = locale === "sw" && row.name_sw ? row.name_sw : row.name;
        const act = locale === "sw" ? row.act_sw : row.act;
        const when = row.when ? formatDateTime(row.when, locale) : null;

        return (
          <li key={`${row.position}-${index}`} className="vf-track-row" data-state={row.state}>
            <span className="vf-track-mark" aria-hidden="true">
              {row.state === "done" && <Icon name="ph-check" size={14} />}
              {row.state === "rejected" && <Icon name="ph-x" size={14} />}
            </span>
            <div style={{ minWidth: 0 }}>
              <div className="vf-track-name">{name}</div>
              {row.person && row.person !== "—" && row.person !== "VouchFlow" && (
                <div className="vf-track-who">
                  {row.person}{row.person_title ? ` · ${row.person_title}` : ""}
                </div>
              )}
              <div className="vf-track-when">
                {row.state === "done" || row.state === "rejected"
                  ? [act, when].filter(Boolean).join(" · ")
                  : row.state === "current"
                    ? (youActHere ? t("waitingForYou") : act || t("inProgress"))
                    : t("notStarted")}
              </div>
              {row.state === "current" && youActHere && <span className="vf-track-you">{t("yourTurn")}</span>}
              {row.comment && <div className="vf-track-note">“{row.comment}”</div>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/* ─────────────────────────────────────────────────────────── the rows ── */

/**
 * What this person can do with the voucher, as one call to action.
 *
 * Every path leads to the voucher, never straight to a decision. Approving,
 * signing and paying all happen on the voucher, behind a confirmation — a
 * one-click Approve on a list is exactly how the wrong voucher gets approved.
 */
export function primaryAction(voucher: Voucher): { label: MessageKey; icon: string; strong: boolean } | null {
  const a = voucher.actions;
  if (!a) return null;
  if (a.pay) return { label: "recordPayment", icon: "ph-wallet", strong: true };
  if (a.approve) return { label: "reviewApprove", icon: "ph-seal-check", strong: true };
  if (a.sign) return { label: "reviewSign", icon: "ph-signature", strong: true };
  if (a.submit_signed) return { label: "submitSigned", icon: "ph-paper-plane-tilt", strong: true };
  if (a.edit && voucher.status === "changes_requested") return { label: "reviseVoucher", icon: "ph-pencil-simple", strong: true };
  if (a.edit) return { label: "continueDraft", icon: "ph-pencil-simple", strong: false };
  return null;
}

export function VoucherRow({
  voucher, progress, showCta = true,
}: { voucher: Voucher; progress?: ProgressStep[]; showCta?: boolean }) {
  const { t, locale } = useApp();
  const cta = showCta ? primaryAction(voucher) : null;
  const who = voucher.requester?.name;
  const meta = [who, voucher.department?.name, formatDate(voucher.voucher_date, locale)].filter(Boolean).join(" · ");

  return (
    <div className="vf-row">
      <div className="vf-row-main">
        <div className="vf-row-top">
          <span className="vf-row-number">{voucher.number}</span>
          <KindChip kind={voucher.kind} />
          <StatusBadge voucher={voucher} />
        </div>
        <Link href={`/vouchers/${voucher.id}`} className="vf-row-title vf-row-link">{voucher.purpose}</Link>
        <div className="vf-row-meta">
          <span>{voucher.payee}</span>{meta ? ` · ${meta}` : ""}
        </div>
        {progress && progress.length > 0 && <div className="vf-row-steps"><ProgressSteps steps={progress} /></div>}
      </div>
      <div className="vf-row-side">
        <div className="vf-row-amount">{voucher.amount_text}</div>
        {cta && (
          <Link href={`/vouchers/${voucher.id}`} className={`btn btn-sm ${cta.strong ? "btn-primary" : "btn-secondary"}`}>
            <Icon name={cta.icon} size={15} /> {t(cta.label)}
          </Link>
        )}
      </div>
    </div>
  );
}

/** A panel of voucher rows, with each voucher's route derived from its workflow. */
export function VoucherList({
  vouchers, showCta = true, withProgress = true, bare = false,
}: { vouchers: Voucher[]; showCta?: boolean; withProgress?: boolean; /** Rows only, for a list that already sits inside a panel. */ bare?: boolean }) {
  const workflows = useWorkflows();
  const { locale } = useApp();

  return (
    <div className={bare ? "vf-list" : "vf-panel vf-list"}>
      {vouchers.map((voucher) => (
        <VoucherRow
          key={voucher.id}
          voucher={voucher}
          showCta={showCta}
          progress={withProgress ? deriveProgress(voucher, workflows, locale) : undefined}
        />
      ))}
    </div>
  );
}

/** Kept for existing callers: a dashboard card is now a single row. */
export function VoucherCard({ voucher, showActions = true }: { voucher: Voucher; showActions?: boolean }) {
  return <VoucherList vouchers={[voucher]} showCta={showActions} />;
}

/**
 * The voucher register. A table where there is room to compare columns; the
 * same vouchers as rows on a phone, where a seven-column table is unusable.
 */
export function VoucherTable({ vouchers, bare = false }: { vouchers: Voucher[]; /** Inside a panel that already draws the frame. */ bare?: boolean }) {
  const { t, locale } = useApp();
  const router = useRouter();

  const table = (
    <div className="table-wrap">
      <table className="table app-voucher-table">
        <thead>
          <tr>
            <th>{t("voucher")}</th>
            <th>{t("purpose")}</th>
            <th>{t("payee")}</th>
            <th className="num">{t("amount")}</th>
            <th>{t("status")}</th>
            <th>{t("date")}</th>
          </tr>
        </thead>
        <tbody>
          {vouchers.map((voucher) => (
            <tr key={voucher.id} className="is-clickable"
              onClick={(e) => {
                if ((e.target as HTMLElement).closest("a, button")) return;
                router.push(`/vouchers/${voucher.id}`);
              }}>
              <td className="app-vt-number">
                <Link href={`/vouchers/${voucher.id}`} className="tnum">{voucher.number}</Link>
                <KindChip kind={voucher.kind} />
              </td>
              <td className="app-vt-purpose">
                <div className="app-vt-title">{voucher.purpose}</div>
                <div className="app-vt-meta">{[voucher.requester?.name, voucher.department?.name].filter(Boolean).join(" · ")}</div>
              </td>
              <td className="app-vt-payee">{voucher.payee}</td>
              <td className="num app-vt-amount">{voucher.amount_text}</td>
              <td><StatusBadge voucher={voucher} /></td>
              <td className="app-vt-date">{formatDate(voucher.voucher_date, locale)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  return (
    <>
      {bare ? <div className="vf-only-wide">{table}</div> : <div className="vf-panel vf-only-wide" style={{ overflow: "hidden" }}>{table}</div>}
      <div className="vf-only-narrow">
        <VoucherList vouchers={vouchers} showCta={false} withProgress={false} bare={bare} />
      </div>
    </>
  );
}

/* ─────────────────────────────────────────────────────── document ops ── */

/**
 * Print / PDF / Share, offered at every workflow stage the step permits.
 * Visibility comes from the backend's actions, never from the viewer's role.
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

  const size = compact ? "btn-sm" : "btn-sm";

  return (
    <>
      {canPrint && (
        <button className={`btn btn-secondary ${size}`} onClick={() => run("print")} disabled={busy !== null}>
          {busy === "print" ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <Icon name="ph-printer" size={15} />} {t("print")}
        </button>
      )}
      {canDownload && (
        <button className={`btn btn-secondary ${size}`} onClick={() => run("download")} disabled={busy !== null}>
          {busy === "download" ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <Icon name="ph-download-simple" size={15} />} PDF
        </button>
      )}
      {canDownload && !compact && (
        <button className="btn btn-ghost btn-sm" onClick={share} title={t("share")}>
          <Icon name="ph-share-network" size={15} /> <span className="vf-hide-sm">{t("share")}</span>
        </button>
      )}
    </>
  );
}
