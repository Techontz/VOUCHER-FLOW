"use client";

import Link from "next/link";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { api, download, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { ACCEPT_ATTRIBUTE, attachmentForm } from "@/lib/attachments";
import { formatDate, formatDateTime } from "@/lib/format";
import {
  Dialog, Disclosure, EmptyState, Field, Icon, Note, Spinner, type SummaryRow,
} from "@/components/ui";
import { Stamp } from "@/components/stamps";
import { ApprovalTrack, DocumentActions, KindChip, StatusBadge } from "@/components/voucher-bits";
import { VoucherSheet } from "@/components/voucher-sheet";
import { SignaturePad } from "@/components/signature-pad";
import type { Voucher } from "@/lib/types";

type Action = "sign" | "submit_signed" | "approve" | "reject" | "request_changes" | "submit" | "cancel" | "pay";

/**
 * One voucher, arranged around the decision in front of the reader.
 *
 *   header      what it is, what it costs, where it stands
 *   decision    what this person may do now — straight from the workflow engine
 *   progress    who prepared, signed, approved and paid, and when
 *   details     the request itself, then attachments and discussion
 *   document    the printed A4 voucher, exactly as it prints
 *
 * Every action a person can take comes from `voucher.actions`, which the
 * backend computes from the configured workflow. Nothing here is decided by
 * role. And every consequential action goes through a confirmation that
 * restates the voucher and amount, so nobody signs, approves or pays the wrong
 * one by accident.
 */
export default function VoucherDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { t, locale, user, company, toast, reportError, refreshUnread } = useApp();
  const search = useSearchParams();

  const [voucher, setVoucher] = useState<Voucher | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<Action | "delete" | null>(null);
  const [busy, setBusy] = useState(false);
  const [paidReceipt, setPaidReceipt] = useState<Voucher | null>(null);
  const [showDocument, setShowDocument] = useState(false);

  const [signature, setSignature] = useState<string | null>(null);
  const [savedSignature, setSavedSignature] = useState<string | null>(null);
  const [saveSignature, setSaveSignature] = useState(true);
  const [statement, setStatement] = useState(false);
  const [comment, setComment] = useState("");
  const [newComment, setNewComment] = useState("");
  const [payReference, setPayReference] = useState("");
  const [payMethod, setPayMethod] = useState("");
  const [receivedBy, setReceivedBy] = useState("");
  const [uploading, setUploading] = useState(false);
  const [signedAt, setSignedAt] = useState<string>("");

  // The sticky phone action bar only earns its place once the decision panel
  // has scrolled away — showing both at once is the same button twice.
  const decisionRef = useRef<HTMLElement | null>(null);
  const [decisionVisible, setDecisionVisible] = useState(true);
  const hasVoucher = !!voucher;

  useEffect(() => {
    const node = decisionRef.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => setDecisionVisible(entry.isIntersecting), { threshold: 0 });
    observer.observe(node);
    return () => observer.disconnect();
  }, [hasVoucher]);

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher }>(`/vouchers/${params.id}`)
      .then((r) => setVoucher(r.data))
      .catch((err) => setError(err.message));
  }, [params.id]);

  useEffect(load, [load, locale]);

  // Arriving from a Print button elsewhere: show the sheet and open the dialog.
  useEffect(() => {
    if (search.get("print") !== "1" || !voucher) return;
    setShowDocument(true);
    const timer = window.setTimeout(() => window.print(), 350);
    return () => window.clearTimeout(timer);
  }, [search, voucher]);

  useEffect(() => {
    if (user?.has_signature) {
      api.get<{ signature: string | null }>("/profile/signature")
        .then((r) => setSavedSignature(r.signature))
        .catch(() => undefined);
    }
  }, [user?.has_signature]);

  function openDialog(action: Action | "delete") {
    setDialog(action);
    setStatement(false);
    setComment("");
    setSignedAt(formatDateTime(new Date().toISOString(), locale));
    if (action === "pay") {
      setPayReference("");
      setReceivedBy(voucher?.kind === "cash" ? voucher.payee : "");
      setPayMethod(voucher?.kind === "cash" ? "Cash — office float" : "Bank transfer");
    }
    // A person may reuse only their OWN saved signature — it is fetched from
    // their profile, never from anyone else's.
    setSignature(action === "sign" || action === "approve" ? (user?.has_signature ? savedSignature : null) : null);
  }

  const closeDialog = useCallback(() => setDialog(null), []);

  async function run(action: Action) {
    if (!voucher) return;
    setBusy(true);
    try {
      const endpoint: Record<Action, string> = {
        sign: "sign", submit_signed: "submit-signed", approve: "approve",
        reject: "reject", request_changes: "request-changes", submit: "submit",
        cancel: "cancel", pay: "pay",
      };

      const body: Record<string, unknown> = { comment: comment || undefined };
      if (action === "sign") {
        body.signature = signature;
        body.save_signature = saveSignature && !!signature;
      }
      if (action === "approve" && signature) body.signature = signature;
      if (action === "pay") {
        const isCash = voucher.kind === "cash";
        body.payment_method = payMethod || (isCash ? "Cash" : "Bank Transfer");
        // A bank transfer is reconciled against its reference; cash is
        // acknowledged by the person who took it. Each format sends what it
        // actually has, and the API requires exactly that.
        if (isCash) body.received_by = receivedBy.trim();
        else body.payment_reference = payReference.trim();
        if (payReference.trim() && /cheque/i.test(payMethod)) body.cheque_number = payReference.trim();
      }

      const res = await api.post<{ data: Voucher }>(`/vouchers/${voucher.id}/${endpoint[action]}`, body);
      setVoucher(res.data);
      setDialog(null);
      void refreshUnread();

      // Payment is the one act that closes a voucher; it gets a receipt, not a toast.
      if (action === "pay") {
        setPaidReceipt(res.data);
        return;
      }

      const messages: Record<Exclude<Action, "pay">, [string, string]> = {
        sign: ["Voucher signed", `${res.data.number} carries your signature. Submit it onward when ready.`],
        submit_signed: ["Signed voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        approve: ["Voucher approved", `${res.data.number} is ${res.data.status_label.toLowerCase()}.`],
        reject: ["Voucher rejected", `${res.data.number} was returned to ${res.data.requester?.name ?? "the requester"}.`],
        request_changes: ["Changes requested", `${res.data.requester?.name ?? "The requester"} has been notified.`],
        submit: ["Voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        cancel: ["Voucher withdrawn", res.data.number],
      };
      const [title, bodyText] = messages[action];
      toast(title, bodyText, action === "reject" || action === "cancel" ? "bad" : action === "request_changes" ? "warn" : "ok");
    } catch (err) {
      reportError(err, "That action could not be completed");
    } finally {
      setBusy(false);
    }
  }

  async function postComment() {
    if (!voucher || !newComment.trim()) return;
    try {
      await api.post(`/vouchers/${voucher.id}/comments`, { body: newComment.trim() });
      setNewComment("");
      load();
    } catch (err) {
      reportError(err, "Could not post the comment");
    }
  }

  async function removeVoucher() {
    if (!voucher) return;
    setBusy(true);
    try {
      await api.delete(`/vouchers/${voucher.id}`);
      toast("Draft deleted", voucher.number, "warn");
      router.push("/vouchers");
    } catch (err) {
      reportError(err, "Could not delete the draft");
      setBusy(false);
    }
  }

  async function attach(files: File[]) {
    if (!voucher || !files.length) return;
    setUploading(true);
    try {
      await request(`/vouchers/${voucher.id}/attachments`, { method: "POST", form: attachmentForm(files) });
      toast("Attached", `${files.length} file(s) added.`, "ok");
      load();
    } catch (err) {
      reportError(err, "Upload failed");
    } finally {
      setUploading(false);
    }
  }

  if (error) {
    return (
      <div className="vf-panel" style={{ maxWidth: 620 }}>
        <EmptyState tone="bad" icon="ph-lock-key" title={t("notAuthorised")} body={error}
          action={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-arrow-left" size={16} /> {t("register")}</Link>} />
      </div>
    );
  }
  if (!voucher) return <VoucherSkeleton />;

  const a = voucher.actions;
  const step = voucher.current_step;
  const rows = voucher.timeline ?? [];
  const decisionActions = a && (a.submit || a.sign || a.submit_signed || a.approve || a.reject || a.request_changes || a.pay);
  const signValid = statement && !!signature;
  const isCash = voucher.kind === "cash";

  /** The same statement of what is being acted on, in every dialog. */
  const summary: SummaryRow[] = [
    { label: t("voucher"), value: voucher.number },
    { label: t("payee"), value: voucher.payee },
    { label: t("amount"), value: <strong>{voucher.amount_text}</strong> },
  ];

  const primary = a?.pay
    ? { action: "pay" as const, label: isCash ? t("releaseFunds") : t("recordPayment"), icon: "ph-wallet" }
    : a?.approve ? { action: "approve" as const, label: t("approveVoucher"), icon: "ph-seal-check" }
    : a?.sign ? { action: "sign" as const, label: t("signVoucher"), icon: "ph-signature" }
    : a?.submit_signed ? { action: "submit_signed" as const, label: t("submitSigned"), icon: "ph-paper-plane-tilt" }
    : a?.submit ? { action: "submit" as const, label: t("submitApproval"), icon: "ph-paper-plane-tilt" }
    : null;

  return (
    <div className="vf-voucher">
      {/* ── header ── */}
      <header className="vf-voucher-head">
        <Link className="vf-back no-print" href="/vouchers">
          <Icon name="ph-arrow-left" size={15} /> {t("register")}
        </Link>

        <div className="vf-voucher-head-row">
          <div className="vf-voucher-head-main">
            <div className="vf-voucher-kicker">
              <span className="vf-eyebrow">{voucher.voucher_type?.label ?? t("voucher")}</span>
              <KindChip kind={voucher.kind} />
            </div>
            <h1 className="vf-voucher-title">{voucher.purpose}</h1>
            <div className="vf-voucher-meta">
              <span className="tnum">{voucher.number}</span>
              {voucher.department?.name && <span>{voucher.department.name}</span>}
              <span>{formatDate(voucher.voucher_date, locale)}</span>
            </div>
          </div>

          <div className="vf-voucher-head-side">
            <StatusBadge voucher={voucher} large />
            <div className="vf-voucher-amount tnum">{voucher.amount_text}</div>
          </div>
        </div>

        <div className="vf-voucher-tools no-print">
          <DocumentActions voucher={voucher} />
          {a?.edit && (
            <button className="btn btn-secondary btn-sm" onClick={() => router.push(`/vouchers/${voucher.id}/edit`)}>
              <Icon name="ph-pencil-simple" size={15} /> {t("edit")}
            </button>
          )}
          <div style={{ flex: 1 }} />
          {a?.cancel && (
            <button className="btn btn-ghost btn-sm vf-text-bad" onClick={() => openDialog("cancel")}>
              <Icon name="ph-prohibit" size={15} /> {t("cancelVoucher")}
            </button>
          )}
          {a?.delete && (
            <button className="btn btn-ghost btn-sm vf-text-bad" onClick={() => openDialog("delete")}>
              <Icon name="ph-trash" size={15} /> {t("delete")}
            </button>
          )}
        </div>
      </header>

      <div className="vf-voucher-grid">
        {/* ── decision & progress: first on a phone, alongside on a desk ── */}
        <aside className="vf-voucher-aside no-print">
          {decisionActions ? (
            <section className="vf-panel vf-decision" ref={decisionRef}>
              <div className="vf-decision-head">
                <span className="vf-decision-icon"><Icon name={primary?.icon ?? "ph-hand-pointing"} size={20} /></span>
                <div style={{ minWidth: 0 }}>
                  <div className="vf-eyebrow">{t("yourDecision")}</div>
                  <h2 className="vf-decision-title">{step?.name ?? voucher.status_label}</h2>
                </div>
              </div>

              {a?.submit_signed && (
                <div className="vf-decision-signed">
                  <Stamp kind="signed" scale={.7} tilt={-3} />
                  <span>{t("signedByYou")}</span>
                </div>
              )}

              <div className="vf-decision-actions">
                {primary && (
                  <button className="btn btn-primary btn-lg btn-block" onClick={() => openDialog(primary.action)}>
                    <Icon name={primary.icon} size={18} /> {primary.label}
                  </button>
                )}
                {/* A step that both signs and approves offers signing as its own act. */}
                {a?.sign && primary?.action !== "sign" && (
                  <button className="btn btn-secondary btn-block" onClick={() => openDialog("sign")}>
                    <Icon name="ph-signature" size={17} /> {t("signVoucher")}
                  </button>
                )}
                {(a?.request_changes || a?.reject) && (
                  <div className="vf-decision-secondary">
                    {a?.request_changes && (
                      <button className="btn btn-secondary" onClick={() => openDialog("request_changes")}>
                        <Icon name="ph-arrow-u-up-left" size={16} /> {t("requestChanges")}
                      </button>
                    )}
                    {a?.reject && (
                      <button className="btn btn-danger" onClick={() => openDialog("reject")}>
                        <Icon name="ph-x" size={16} /> {t("reject")}
                      </button>
                    )}
                  </div>
                )}
              </div>

              {a?.sign && !step?.capabilities.approve && <p className="vf-decision-hint">{t("signNoApprove")}</p>}
              {a?.pay && <p className="vf-decision-hint">{t("payNote")}</p>}
            </section>
          ) : (
            <section className="vf-panel vf-decision vf-decision-idle">
              <div className="vf-decision-head">
                <span className={`vf-decision-icon tone-${voucher.status === "paid" ? "ok" : "neutral"}`}>
                  <Icon name={voucher.status === "paid" ? "ph-check-circle" : voucher.is_terminal ? "ph-archive" : "ph-hourglass-medium"} size={20} />
                </span>
                <div style={{ minWidth: 0 }}>
                  <h2 className="vf-decision-title">{voucher.is_terminal ? voucher.status_label : t("noAction")}</h2>
                  <p className="vf-decision-hint" style={{ marginTop: 2 }}>
                    {voucher.is_terminal ? t("historyInReports") : voucher.status_label}
                  </p>
                </div>
              </div>
            </section>
          )}

          <section className="vf-panel">
            <div className="vf-panel-head"><h2>{t("approvalProgress")}</h2></div>
            <div className="vf-panel-pad">
              {rows.length > 0
                ? <ApprovalTrack rows={rows} youActHere={!!decisionActions && voucher.status !== "draft"} />
                : <p className="text-muted" style={{ margin: 0 }}>{t("notStarted")}</p>}
            </div>
          </section>
        </aside>

        {/* ── the request ── */}
        <div className="vf-voucher-main">
          <section className="vf-panel no-print">
            <div className="vf-panel-head"><h2>{t("requestDetails")}</h2></div>
            <div className="vf-panel-pad" style={{ paddingTop: 4, paddingBottom: 8 }}>
              <dl className="vf-dl">
                <Row label={t("payee")} value={voucher.payee} />
                {voucher.description && <Row label={t("description")} value={voucher.description} />}
                <Row label={t("requestedBy")} value={[voucher.requester?.name, voucher.requester?.job_title].filter(Boolean).join(" · ")} />
                <Row label={t("department")} value={[voucher.department?.name, voucher.cost_centre].filter(Boolean).join(" · ")} />
                <Row label={t("voucherType")} value={voucher.voucher_type?.label} />
                <Row label={t("voucherFormat")} value={isCash ? t("cash") : t("bank")} />
                <Row label={t("paymentMethod")} value={voucher.payment_method} />
                {voucher.category && <Row label={t("category")} value={voucher.category} />}
                {voucher.account_ref && <Row label={t("accountRef")} value={voucher.account_ref} mono />}

                {!isCash && (voucher.payee_bank || voucher.payee_account_number) && (
                  <>
                    <Row label={t("bank")} value={[voucher.payee_bank, voucher.payee_bank_branch].filter(Boolean).join(" · ")} />
                    <Row label={t("accountName")} value={voucher.payee_account_name} />
                    <Row label={t("accountNumber")} value={voucher.payee_account_number} mono />
                  </>
                )}
                {isCash && voucher.cash_float && <Row label={t("payFrom")} value={voucher.cash_float} />}

                <Row label={t("requestedOn")} value={formatDate(voucher.voucher_date, locale)} />
                {voucher.notes_to_approver && <Row label={t("notes")} value={voucher.notes_to_approver} />}

                {voucher.status === "paid" && (
                  <>
                    <Row label={t("paidByOn")} value={[voucher.paid_by, formatDateTime(voucher.paid_at, locale)].filter(Boolean).join(" · ")} />
                    {voucher.payment_reference && <Row label={t("paymentRef")} value={voucher.payment_reference} mono />}
                    {voucher.received_by && <Row label={t("receivedBy")} value={voucher.received_by} />}
                  </>
                )}
              </dl>
            </div>
          </section>

          {/* ── attachments ── */}
          <section className="vf-panel no-print">
            <div className="vf-panel-head">
              <h2>{t("attachments")}{voucher.attachments && voucher.attachments.length > 0 && <span className="vf-count" style={{ marginLeft: 8 }}>{voucher.attachments.length}</span>}</h2>
              {a?.edit && (
                <label className={`btn btn-secondary btn-sm${uploading ? " is-busy" : ""}`}>
                  {uploading ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <Icon name="ph-paperclip" size={15} />}
                  {t("add")}
                  <input type="file" multiple accept={ACCEPT_ATTRIBUTE} hidden disabled={uploading}
                    onChange={(e) => { void attach(Array.from(e.target.files ?? [])); e.target.value = ""; }} />
                </label>
              )}
            </div>
            <div className="vf-panel-pad">
              {voucher.attachments && voucher.attachments.length > 0 ? (
                <ul className="vf-files">
                  {voucher.attachments.map((file) => (
                    <li key={file.id}>
                      <button className="vf-file"
                        onClick={async () => {
                          try {
                            const blob = await download(`/vouchers/${voucher.id}/attachments/${file.id}`);
                            window.open(URL.createObjectURL(blob), "_blank");
                          } catch (err) { reportError(err, "Could not open the attachment"); }
                        }}>
                        <span className="vf-file-icon"><Icon name={file.icon || "ph-file"} size={20} /></span>
                        <span className="vf-file-text">
                          <span className="vf-file-name">{file.name}</span>
                          <span className="vf-file-size">{file.size}</span>
                        </span>
                        <Icon name="ph-arrow-square-out" size={16} style={{ color: "var(--color-neutral-500)" }} />
                      </button>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-muted" style={{ margin: 0 }}>{t("noneAttached")}</p>
              )}
            </div>
          </section>

          {/* ── discussion ── */}
          <section className="vf-panel no-print">
            <div className="vf-panel-head">
              <h2>{t("comments")}{voucher.comments && voucher.comments.length > 0 && <span className="vf-count" style={{ marginLeft: 8 }}>{voucher.comments.length}</span>}</h2>
            </div>
            <div className="vf-panel-pad">
              {voucher.comments && voucher.comments.length > 0 && (
                <ul className="vf-comments">
                  {voucher.comments.map((c) => (
                    <li key={c.id} className="vf-comment">
                      <span className="vf-avatar" aria-hidden="true">{c.user?.initials}</span>
                      <div style={{ minWidth: 0 }}>
                        <div className="vf-comment-meta">
                          <strong>{c.user?.name}</strong>
                          <span>{c.user?.department ?? c.user?.role_label} · {formatDateTime(c.created_at, locale)}</span>
                        </div>
                        <div className="vf-comment-body">{c.body}</div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
              <div className="vf-comment-form">
                <input className="input" placeholder={t("addComment")} value={newComment} aria-label={t("addComment")}
                  onChange={(e) => setNewComment(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void postComment(); } }} />
                <button className="btn btn-secondary" onClick={postComment} disabled={!newComment.trim()}>{t("post")}</button>
              </div>
            </div>
          </section>

          {/* ── the printed document ──
              Never removed from the page, only folded away on screen: the print
              stylesheet prints this sheet, so it must always be in the DOM. */}
          <section className="vf-panel vf-document-panel" data-open={showDocument ? "true" : "false"}>
            <button type="button" className="vf-disclosure-head no-print" onClick={() => setShowDocument((v) => !v)} aria-expanded={showDocument}>
              <Icon name="ph-file-text" size={18} style={{ color: "var(--color-neutral-600)" }} />
              <span className="vf-disclosure-title">{t("voucherDocument")}</span>
              <span className="vf-document-toggle-label">{showDocument ? t("hideDocument") : t("showDocument")}</span>
              <Icon name="ph-caret-down" size={16} style={{ color: "var(--color-neutral-600)", transform: showDocument ? "rotate(180deg)" : "none", transition: "transform var(--dur) var(--ease-out)" }} />
            </button>
            <div className="vf-document-body">
              <div className="vf-document-frame">
                <VoucherSheet voucher={voucher} company={company} />
              </div>
            </div>
          </section>

          <Disclosure title={t("auditTrail")} icon="ph-scroll">
            <dl className="vf-dl">
              <Row label="Created" value={formatDateTime(voucher.created_at, locale)} mono />
              {voucher.submitted_at && <Row label="Submitted" value={formatDateTime(voucher.submitted_at, locale)} mono />}
              {voucher.approved_at && <Row label="Approved" value={formatDateTime(voucher.approved_at, locale)} mono />}
              {voucher.rejected_at && <Row label="Rejected" value={formatDateTime(voucher.rejected_at, locale)} mono />}
              {voucher.paid_at && <Row label="Paid" value={`${formatDateTime(voucher.paid_at, locale)} · ${voucher.paid_by ?? ""}`} mono />}
              {voucher.verification_code && <Row label={t("verificationCode")} value={voucher.verification_code} mono />}
            </dl>
          </Disclosure>
        </div>
      </div>

      {/* ── on a phone the decision stays one thumb away ── */}
      {primary && !decisionVisible && (
        <div className="vf-actionbar no-print">
          {a?.reject && (
            <button className="btn btn-danger" style={{ flex: "0 0 auto" }} onClick={() => openDialog("reject")} aria-label={t("reject")}>
              <Icon name="ph-x" size={18} />
            </button>
          )}
          <button className="btn btn-primary" onClick={() => openDialog(primary.action)}>
            <Icon name={primary.icon} size={18} /> {primary.label}
          </button>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────── dialogs ── */}

      {/* Sign — serious, deliberate, and only ever with your own signature. */}
      <Dialog
        open={dialog === "sign"}
        icon="ph-signature"
        tone="info"
        title={t("confirmSignature")}
        sub={<>{t("signingAs")} <strong>{user?.name}</strong>{user?.job_title ? ` — ${user.job_title}` : ""}.</>}
        summary={[...summary, { label: t("dateTime"), value: signedAt }]}
        onClose={closeDialog}
        busy={busy}
        wide
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" disabled={busy || !signValid} onClick={() => run("sign")}>
              {busy ? <Spinner /> : <><Icon name="ph-signature" size={17} /> {t("confirmSign")}</>}
            </button>
          </>
        }
      >
        <div className="vf-stack">
          <SignaturePad value={signature} onChange={setSignature} hasSaved={!!user?.has_signature} savedSignature={savedSignature} />
          <label className="radio">
            <input type="checkbox" checked={saveSignature} onChange={(e) => setSaveSignature(e.target.checked)} />
            <span className="dot" />
            Save this signature for next time
          </label>
          <Field label={t("commentOptional")} htmlFor="sign-comment">
            <textarea id="sign-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 64 }} />
          </Field>
          <label className="radio vf-statement">
            <input type="checkbox" checked={statement} onChange={(e) => setStatement(e.target.checked)} />
            <span className="dot" />
            <span>{t("signStatement")}</span>
          </label>
          <Note>{t("signatureRecorded")}{!step?.capabilities.approve ? ` ${t("signNoApprove")}` : ""}</Note>
        </div>
      </Dialog>

      {/* Approve */}
      <Dialog
        open={dialog === "approve"}
        icon="ph-seal-check"
        tone="ok"
        title={t("approveVoucherQ")}
        sub={t("approvingForPayment")}
        summary={summary}
        onClose={closeDialog}
        busy={busy}
        wide={!!step?.capabilities.sign}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" disabled={busy || !statement} onClick={() => run("approve")}>
              {busy ? <Spinner /> : <><Icon name="ph-seal-check" size={17} /> {t("approveVoucher")}</>}
            </button>
          </>
        }
      >
        <div className="vf-stack">
          {step?.capabilities.sign && (
            <SignaturePad value={signature} onChange={setSignature} hasSaved={!!user?.has_signature} savedSignature={savedSignature} />
          )}
          <Field label={t("approvalNote")} htmlFor="approve-comment">
            <textarea id="approve-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 64 }} />
          </Field>
          <label className="radio vf-statement">
            <input type="checkbox" checked={statement} onChange={(e) => setStatement(e.target.checked)} />
            <span className="dot" />
            <span>{t("approveStatement")}</span>
          </label>
        </div>
      </Dialog>

      {/* Reject · Request changes */}
      <Dialog
        open={dialog === "reject" || dialog === "request_changes"}
        icon={dialog === "reject" ? "ph-x-circle" : "ph-arrow-u-up-left"}
        tone={dialog === "reject" ? "bad" : "warn"}
        title={dialog === "reject" ? t("rejectVoucherQ") : t("requestChangesQ")}
        sub={dialog === "reject" ? t("rejectingNote") : t("requestChangesNote")}
        summary={summary}
        onClose={closeDialog}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className={`btn ${dialog === "reject" ? "btn-danger-solid" : "btn-primary"}`}
              disabled={busy || comment.trim().length < 3} onClick={() => run(dialog as Action)}>
              {busy ? <Spinner /> : dialog === "reject" ? t("rejectVoucher") : t("requestChanges")}
            </button>
          </>
        }
      >
        <Field label={dialog === "reject" ? t("rejectReason") : t("changesNeeded")} htmlFor="reason" required
          hint={comment.trim().length < 3 ? (dialog === "reject" ? "Explain why this cannot be approved." : "Tell the requester exactly what to change.") : undefined}>
          <textarea id="reason" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 104 }} />
        </Field>
      </Dialog>

      {/* Submit · Submit signed */}
      <Dialog
        open={dialog === "submit" || dialog === "submit_signed"}
        icon="ph-paper-plane-tilt"
        tone="info"
        title={dialog === "submit_signed" ? t("submitSigned") : t("submitVoucherQ")}
        sub={dialog === "submit_signed" ? t("submitSignedNote") : t("submitNote")}
        summary={summary}
        onClose={closeDialog}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={() => run(dialog as Action)} disabled={busy}>
              {busy ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={17} /> {dialog === "submit_signed" ? t("submitSigned") : t("submitApproval")}</>}
            </button>
          </>
        }
      >
        <Field label={t("commentOptional")} htmlFor="submit-comment">
          <textarea id="submit-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 64 }} />
        </Field>
      </Dialog>

      {/* Pay */}
      <Dialog
        open={dialog === "pay"}
        icon="ph-wallet"
        tone="ok"
        title={t("confirmPayment")}
        sub={t("markAsPaidNote")}
        summary={[...summary, { label: t("voucherFormat"), value: isCash ? t("cash") : t("bank") }]}
        onClose={closeDialog}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={() => run("pay")}
              disabled={busy || (isCash ? !receivedBy.trim() : !payReference.trim())}>
              {busy ? <Spinner /> : <><Icon name="ph-check" size={17} /> {t("confirmPayment")}</>}
            </button>
          </>
        }
      >
        <div className="vf-stack">
          <Field label={t("payFrom")} htmlFor="pay-method">
            <select id="pay-method" className="input" value={payMethod} onChange={(e) => setPayMethod(e.target.value)}>
              {(isCash ? ["Cash — office float", "Cash — branch float"] : ["Bank transfer", "Cheque", "Mobile money"])
                .map((option) => <option key={option} value={option}>{option}</option>)}
            </select>
          </Field>

          {!isCash && (
            <Field label={/cheque/i.test(payMethod) ? t("chequeNo") : t("paymentRef")} htmlFor="pay-ref" required
              hint={/cheque/i.test(payMethod) ? "e.g. 004471" : "e.g. CRDB-TRX-8841207"}>
              <input id="pay-ref" className="input" value={payReference} onChange={(e) => setPayReference(e.target.value)} />
            </Field>
          )}

          {isCash && (
            <Field label={t("receivedBy")} htmlFor="pay-received" required hint="Printed on the voucher as the acknowledgement of receipt">
              <input id="pay-received" className="input" value={receivedBy} onChange={(e) => setReceivedBy(e.target.value)} />
            </Field>
          )}

          <Field label={t("commentOptional")} htmlFor="pay-comment">
            <textarea id="pay-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 60 }} />
          </Field>
        </div>
      </Dialog>

      {/* Payment receipt — the close of the voucher's life. */}
      <Dialog
        open={!!paidReceipt}
        icon="ph-check-circle"
        tone="ok"
        title={t("paymentCompleted")}
        summary={paidReceipt ? [
          { label: t("voucher"), value: paidReceipt.number },
          { label: t("amount"), value: <strong>{paidReceipt.amount_text}</strong> },
          { label: t("paidByOn"), value: paidReceipt.paid_by ?? user?.name ?? "—" },
          { label: t("dateTime"), value: formatDateTime(paidReceipt.paid_at, locale) },
          ...(paidReceipt.payment_reference ? [{ label: t("paymentRef"), value: paidReceipt.payment_reference }] : []),
        ] : []}
        onClose={() => setPaidReceipt(null)}
        actions={
          <>
            <Link className="btn btn-secondary" href="/dashboard">{t("home")}</Link>
            <button className="btn btn-primary" onClick={() => setPaidReceipt(null)}>{t("done")}</button>
          </>
        }
      />

      {/* Withdraw */}
      <Dialog
        open={dialog === "cancel"}
        icon="ph-prohibit"
        tone="bad"
        title={t("cancelVoucherQ")}
        sub={t("cancelNote")}
        summary={summary}
        onClose={closeDialog}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-danger-solid" onClick={() => run("cancel")} disabled={busy}>
              {busy ? <Spinner /> : t("cancelVoucher")}
            </button>
          </>
        }
      >
        <Field label={t("commentOptional")} htmlFor="cancel-comment">
          <textarea id="cancel-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 64 }} />
        </Field>
      </Dialog>

      {/* Delete draft — used to happen on a single click. */}
      <Dialog
        open={dialog === "delete"}
        icon="ph-trash"
        tone="bad"
        title={t("deleteDraftQ")}
        sub={t("cannotBeUndone")}
        summary={summary}
        onClose={closeDialog}
        busy={busy}
        actions={
          <>
            <button className="btn btn-secondary" onClick={closeDialog} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-danger-solid" onClick={removeVoucher} disabled={busy}>
              {busy ? <Spinner /> : <><Icon name="ph-trash" size={17} /> {t("deleteDraft")}</>}
            </button>
          </>
        }
      />
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string | null | undefined; mono?: boolean }) {
  if (!value) return null;
  return (
    <div className="vf-dl-row">
      <dt>{label}</dt>
      <dd className={mono ? "tnum" : undefined}>{value}</dd>
    </div>
  );
}

function VoucherSkeleton() {
  return (
    <div className="vf-voucher" aria-busy="true">
      <span className="sr-only">Loading</span>
      <div style={{ display: "grid", gap: 10, marginBottom: 24 }}>
        <div className="skeleton" style={{ height: 14, width: 120 }} />
        <div className="skeleton" style={{ height: 30, width: "min(520px, 80%)" }} />
        <div className="skeleton" style={{ height: 14, width: 260 }} />
      </div>
      <div className="vf-voucher-grid">
        <div className="vf-voucher-aside">
          <div className="skeleton" style={{ height: 200, borderRadius: 14 }} />
          <div className="skeleton" style={{ height: 260, borderRadius: 14 }} />
        </div>
        <div className="vf-voucher-main">
          <div className="skeleton" style={{ height: 380, borderRadius: 14 }} />
        </div>
      </div>
    </div>
  );
}
