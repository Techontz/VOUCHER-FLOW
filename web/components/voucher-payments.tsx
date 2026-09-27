"use client";

import { useState } from "react";
import { ApiError, download, printBlob, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { acceptFiles, ACCEPT_ATTRIBUTE } from "@/lib/attachments";
import { formatDate, formatDateTime, money } from "@/lib/format";
import { Icon } from "@/components/ui";
import type { Voucher, VoucherPayment } from "@/lib/types";

/**
 * Money leaves a voucher in one or more payments, and each cash payment needs
 * a paper trail: an acknowledgement the cashier prints, the receiver signs on
 * taking the money, and the cashier files back on the voucher.
 *
 * The printable acknowledgement is rendered by the server; this module only
 * fetches it, and uploads the signed copy against its payment.
 */
export function usePaymentAcknowledgement(voucher: Voucher | null, onFiled: (fresh: Voucher) => void) {
  const { t, locale, toast, reportError } = useApp();
  const [printing, setPrinting] = useState<number | null>(null);
  const [uploading, setUploading] = useState<number | null>(null);

  /** Opens the print dialog on the acknowledgement, in the reader's language. */
  async function print(payment: VoucherPayment) {
    if (!voucher) return;
    setPrinting(payment.id);
    try {
      const blob = await download(
        `/vouchers/${voucher.id}/payments/${payment.id}/acknowledgement`,
        locale === "sw" ? { lang: "sw" } : undefined,
      );
      printBlob(blob);
    } catch (err) {
      reportError(err, t("ackPrintFailed"));
    } finally {
      setPrinting(null);
    }
  }

  /** Files the receiver's signed copy against its payment. */
  async function upload(payment: VoucherPayment, picked: File[]) {
    if (!voucher || !picked.length) return;
    // The same type and size rules as any attachment, checked before the trip.
    const { files, rejected } = acceptFiles([], picked.slice(0, 1));
    if (!files.length) {
      toast(t("ackUploadFailed"), rejected[0]?.reason === "size" ? `${t("fileTooLarge")} 10 MB` : t("fileWrongType"), "bad");
      return;
    }

    setUploading(payment.id);
    try {
      const form = new FormData();
      form.append("file", files[0], files[0].name);
      const res = await request<{ data: Voucher }>(
        `/vouchers/${voucher.id}/payments/${payment.id}/acknowledgement`,
        { method: "POST", form },
      );
      onFiled(res.data);
      toast(t("signedCopyFiled"), t("signedCopyFiledBody").replace("{n}", String(payment.sequence)), "ok");
    } catch (err) {
      // The button is only offered to people likely to be allowed, but the
      // server has the final word — say plainly who may file it.
      if (err instanceof ApiError && err.status === 403) toast(t("ackUploadFailed"), t("ackUploadForbidden"), "bad");
      else reportError(err, t("ackUploadFailed"));
    } finally {
      setUploading(null);
    }
  }

  return { print, upload, printing, uploading };
}

/** The payment just recorded: the one with the highest sequence. */
export function latestPayment(voucher: Voucher): VoucherPayment | null {
  const payments = voucher.payments ?? [];
  return payments.reduce<VoucherPayment | null>((last, p) => (!last || p.sequence > last.sequence ? p : last), null);
}

/**
 * The voucher's payments: what was approved, what has left, what is still
 * owed, and one row per release with its acknowledgement status.
 */
export function PaymentsPanel({
  voucher, canFile, onOpenAttachment, ack,
}: {
  voucher: Voucher;
  /** Whether this reader is likely allowed to file a signed copy for a payment. */
  canFile: (payment: VoucherPayment) => boolean;
  onOpenAttachment: (attachmentId: number) => void;
  ack: ReturnType<typeof usePaymentAcknowledgement>;
}) {
  const { t, locale } = useApp();
  const payments = voucher.payments ?? [];
  const paid = voucher.amount_paid ?? (voucher.status === "paid" ? voucher.amount : 0);
  const balance = voucher.balance ?? (voucher.status === "paid" ? 0 : voucher.amount);
  const text = (value: number, fallback?: string) => fallback ?? money(value, voucher.currency);

  return (
    <section className="vf-panel no-print app-payments">
      <div className="vf-panel-head">
        <h2 className="app-panel-title">
          {t("payments")}
          {payments.length > 0 && <span className="vf-count">{payments.length}</span>}
        </h2>
      </div>

      <dl className="app-pay-summary">
        <div>
          <dt>{t("approvedAmount")}</dt>
          <dd className="tnum">{voucher.amount_text}</dd>
        </div>
        <div>
          <dt>{t("paidSoFar")}</dt>
          <dd className="tnum">{text(paid, voucher.amount_paid_text)}</dd>
        </div>
        <div data-owing={balance > 0 ? "true" : undefined}>
          <dt>{t("balanceLabel")}</dt>
          <dd className="tnum">{text(balance, voucher.balance_text)}</dd>
        </div>
      </dl>

      {payments.length > 0 ? (
        <ol className="app-pay-list">
          {payments.map((p) => {
            const via = [p.payment_method, p.payment_reference ?? p.cheque_number].filter(Boolean).join(" · ");
            const receiver = [p.received_by, p.receiver_id_number ? `ID ${p.receiver_id_number}` : null].filter(Boolean).join(" · ");
            const signedCopy = p.acknowledgement_attachment_ids[p.acknowledgement_attachment_ids.length - 1];

            return (
              <li key={p.id} className="app-pay-row">
                <div className="app-pay-row-head">
                  <span className="app-pay-seq">#{p.sequence}</span>
                  <strong className="tnum">{p.amount_text}</strong>
                  <span className="app-pay-date">{formatDate(p.payment_date ?? p.paid_at, locale)}</span>
                  <span className="app-pay-ref tnum">{p.reference}</span>
                </div>

                <dl className="app-pay-facts">
                  {via && <div><dt>{t("method")}</dt><dd>{via}</dd></div>}
                  {receiver && <div><dt>{t("receivedBy")}</dt><dd>{receiver}</dd></div>}
                  {p.paid_by && (
                    <div><dt>{t("paidBy")}</dt><dd>{[p.paid_by, p.paid_at ? formatDateTime(p.paid_at, locale) : null].filter(Boolean).join(" · ")}</dd></div>
                  )}
                  <div><dt>{t("balanceAfter")}</dt><dd className="tnum">{p.balance_after_text}</dd></div>
                  {p.note && <div><dt>{t("notes")}</dt><dd>{p.note}</dd></div>}
                </dl>

                <div className="app-pay-ack">
                  {p.acknowledged_at ? (
                    signedCopy ? (
                      <button type="button" className="app-pay-ack-state" data-state="filed"
                        onClick={() => onOpenAttachment(signedCopy)} title={t("openSignedCopy")}>
                        <Icon name="ph-check-circle" size={15} /> {t("signedCopyFiled")}
                        <Icon name="ph-arrow-square-out" size={13} />
                      </button>
                    ) : (
                      <span className="app-pay-ack-state" data-state="filed">
                        <Icon name="ph-check-circle" size={15} /> {t("signedCopyFiled")}
                      </span>
                    )
                  ) : (
                    <span className="app-pay-ack-state" data-state="awaiting">
                      <Icon name="ph-hourglass-medium" size={15} /> {t("awaitingSignedCopy")}
                    </span>
                  )}

                  <div className="app-pay-ack-actions">
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => void ack.print(p)} disabled={ack.printing !== null}>
                      {ack.printing === p.id ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <Icon name="ph-printer" size={15} />}
                      {t("printAcknowledgement")}
                    </button>
                    {canFile(p) && (
                      <label className={`btn btn-secondary btn-sm${ack.uploading === p.id ? " is-busy" : ""}`}>
                        {ack.uploading === p.id ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <Icon name="ph-upload-simple" size={15} />}
                        {t("uploadSignedCopy")}
                        <input type="file" accept={ACCEPT_ATTRIBUTE} hidden disabled={ack.uploading !== null}
                          onChange={(e) => { void ack.upload(p, Array.from(e.target.files ?? [])); e.target.value = ""; }} />
                      </label>
                    )}
                  </div>
                </div>
              </li>
            );
          })}
        </ol>
      ) : (
        <div className="vf-panel-pad">
          <p className="app-muted-line"><Icon name="ph-wallet" size={15} /> {t("noPaymentsYet")}</p>
        </div>
      )}
    </section>
  );
}
