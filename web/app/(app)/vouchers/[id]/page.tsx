"use client";

import Link from "next/link";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, download, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime } from "@/lib/format";
import {
  Dialog, Disclosure, EmptyState, ErrorState, Field, Icon, LoadingBlock, Note, Spinner,
} from "@/components/ui";
import { Stamp, type StampKind } from "@/components/stamps";
import { DocumentActions, KindChip } from "@/components/voucher-bits";
import { VoucherSheet } from "@/components/voucher-sheet";
import { SignaturePad } from "@/components/signature-pad";
import type { Voucher } from "@/lib/types";

type Action = "sign" | "submit_signed" | "approve" | "reject" | "request_changes" | "submit" | "cancel" | "pay";

export default function VoucherDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { t, locale, user, company, toast, reportError, refreshUnread } = useApp();
  const search = useSearchParams();

  const [voucher, setVoucher] = useState<Voucher | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<Action | null>(null);
  const [busy, setBusy] = useState(false);

  const [signature, setSignature] = useState<string | null>(null);
  const [savedSignature, setSavedSignature] = useState<string | null>(null);
  const [saveSignature, setSaveSignature] = useState(true);
  const [statement, setStatement] = useState(false);
  const [comment, setComment] = useState("");
  const [newComment, setNewComment] = useState("");
  const [payReference, setPayReference] = useState("");
  const [payMethod, setPayMethod] = useState("");
  const [receivedBy, setReceivedBy] = useState("");
  const [sheetOpen, setSheetOpen] = useState(false);

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
    setSheetOpen(true);
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

  function openDialog(action: Action) {
    setDialog(action);
    setStatement(false);
    setComment("");
    if (action === "pay") {
      setPayReference("");
      setReceivedBy(voucher?.kind === "cash" ? voucher.payee : "");
      setPayMethod(voucher?.kind === "cash" ? "Cash" : "Bank transfer");
    }
    setSignature(action === "sign" || action === "approve" ? (user?.has_signature ? savedSignature : null) : null);
  }

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

      const messages: Record<Action, [string, string]> = {
        sign: ["Voucher signed", `${res.data.number} carries your signature. Submit it onward when ready.`],
        submit_signed: ["Signed voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        approve: ["Voucher approved", `${res.data.number} is ${res.data.status_label.toLowerCase()}.`],
        reject: ["Voucher rejected", `${res.data.number} was returned to ${res.data.requester?.name ?? "the requester"}.`],
        request_changes: ["Changes requested", `${res.data.requester?.name ?? "The requester"} has been notified.`],
        submit: ["Voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        cancel: ["Voucher cancelled", res.data.number],
        pay: ["Payment recorded", `${res.data.number} — ${res.data.amount_text} released · reference ${res.data.payment_reference}.`],
      };
      const [title, bodyText] = messages[action];
      toast(title, bodyText, action === "reject" ? "bad" : action === "request_changes" ? "warn" : "ok");
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
    try {
      await api.delete(`/vouchers/${voucher.id}`);
      toast("Draft deleted", voucher.number, "warn");
      router.push("/vouchers");
    } catch (err) {
      reportError(err, "Could not delete the draft");
    }
  }

  if (error) {
    return (
      <div style={{ maxWidth: 620 }}>
        <EmptyState icon="ph-lock-key" title={t("notAuthorised")} body={error}
          action={<Link className="btn btn-secondary" href="/vouchers">{t("register")}</Link>} />
      </div>
    );
  }
  if (!voucher) return <LoadingBlock rows={6} />;

  const a = voucher.actions;
  const step = voucher.current_step;
  const printing = search.get("print") === "1";
  const canAct = a && (a.sign || a.submit_signed || a.approve || a.reject || a.request_changes || a.pay);
  const signValid = statement && !!signature;

  /* The same marks the printed document carries, so the screen and the paper
     never disagree about who has put their name to this. */
  const rows = voucher.timeline ?? [];
  const marks: { caption: string; name: string | null; when: string | null; stamp: StampKind }[] = [
    {
      caption: t("signedByName"),
      ...pick(rows.find((r) => r.capabilities?.sign && !r.capabilities?.approve && r.when)),
      stamp: "signed",
    },
    {
      caption: t("approvedByName"),
      ...pick(rows.find((r) => r.capabilities?.approve && r.when)),
      stamp: voucher.status === "rejected" ? "rejected" : "approved",
    },
    {
      caption: t("paidBy"),
      ...pick(rows.find((r) => r.capabilities?.pay && r.when)),
      stamp: "paid",
    },
  ];

  return (
    <div style={{ maxWidth: 1200 }}>
      {/* ── header ── */}
      <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--space-4)", flexWrap: "wrap", borderBottom: "1px solid var(--color-divider)", paddingBottom: "var(--space-4)", marginBottom: "var(--space-6)" }}>
        <div style={{ minWidth: 0, flex: "1 1 300px" }}>
          <Link className="btn btn-ghost btn-sm no-print" href="/vouchers" style={{ padding: "2px 6px", marginBottom: 6 }}>
            <Icon name="ph-arrow-left" size={14} /> {t("register")}
          </Link>
          <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-3)", flexWrap: "wrap" }}>
            <h1 style={{ fontSize: "clamp(24px,3.4vw,34px)", letterSpacing: "-.015em", margin: 0, fontVariantNumeric: "tabular-nums" }}>{voucher.number}</h1>
            <KindChip kind={voucher.kind} size={12} />
            <span className={`tag ${voucher.status_tag}`} style={{ fontSize: 13.5 }}>{voucher.status_label}</span>
          </div>
          <div style={{ color: "var(--color-neutral-700)", marginTop: 6 }}>
            {voucher.voucher_type?.label} · {voucher.department?.name ?? "—"} · {formatDate(voucher.voucher_date, locale)}
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 29, fontVariantNumeric: "tabular-nums" }}>{voucher.amount_text}</div>
          <div className="no-print" style={{ display: "flex", gap: 6, marginTop: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
            <DocumentActions voucher={voucher} />
            {a?.edit && <button className="btn btn-secondary" onClick={() => router.push(`/vouchers/${voucher.id}/edit`)}><Icon name="ph-pencil-simple" size={15} /> {t("edit")}</button>}
            {a?.delete && <button className="btn btn-secondary btn-danger" onClick={removeVoucher}><Icon name="ph-trash" size={15} /> {t("delete")}</button>}
          </div>
        </div>
      </div>

      {/* The document is the page. Everything secondary folds away beneath it,
          so what is on screen is what will print. */}
      <div className="vf-split">
        <div style={{ minWidth: 0 }}>
          <div className="vf-document-frame">
            <VoucherSheet voucher={voucher} company={company} />
          </div>

          {/* ── secondary, folded away ── */}
          <div className="no-print" style={{ display: "grid", gap: "var(--space-3)", marginTop: "var(--space-4)" }}>
            <Disclosure
              title={t("attachments")}
              count={voucher.attachments?.length ?? 0}
              icon="ph-paperclip"
            >
              {voucher.attachments && voucher.attachments.length > 0 ? (
                <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-2)" }}>
                  {voucher.attachments.map((file) => (
                    <button key={file.id}
                      onClick={async () => {
                        try {
                          const blob = await download(`/vouchers/${voucher.id}/attachments/${file.id}`);
                          window.open(URL.createObjectURL(blob), "_blank");
                        } catch (err) { reportError(err, "Could not open the attachment"); }
                      }}
                      style={{
                        display: "flex", alignItems: "center", gap: 9,
                        border: "1px solid var(--vf-line)", background: "var(--vf-elev-2)",
                        borderRadius: 10, padding: "9px var(--space-3)", fontSize: 14,
                        cursor: "pointer", fontFamily: "var(--font-body)", color: "var(--color-text)",
                      }}>
                      <Icon name={file.icon} size={19} color="var(--color-accent-600)" />
                      <span>{file.name}</span>
                      <span style={{ color: "var(--color-neutral-600)", fontSize: 12.5 }}>{file.size}</span>
                      <Icon name="ph-arrow-square-out" size={13} style={{ opacity: .5 }} />
                    </button>
                  ))}
                </div>
              ) : (
                <p style={{ color: "var(--color-neutral-600)", fontSize: 14, margin: 0 }}>{t("noneAttached")}</p>
              )}

              {a?.edit && (
                <label className="btn btn-secondary btn-sm" style={{ marginTop: "var(--space-3)" }}>
                  <Icon name="ph-paperclip" size={14} /> {t("add")}
                  <input type="file" multiple accept="application/pdf,image/*" style={{ display: "none" }}
                    onChange={async (e) => {
                      const files = Array.from(e.target.files ?? []);
                      if (!files.length) return;
                      const form = new FormData();
                      files.forEach((f) => form.append("files[]", f));
                      try {
                        await request(`/vouchers/${voucher.id}/attachments`, { method: "POST", form });
                        toast("Attached", `${files.length} file(s) added.`, "ok");
                        load();
                      } catch (err) { reportError(err, "Upload failed"); }
                    }} />
                </label>
              )}
            </Disclosure>

            <Disclosure title={t("comments")} count={voucher.comments?.length ?? 0} icon="ph-chat-teardrop-text">
              {voucher.comments?.map((c) => (
                <div key={c.id} style={{
                  display: "flex", gap: "var(--space-3)", paddingBottom: "var(--space-3)",
                  marginBottom: "var(--space-3)", borderBottom: "1px solid var(--vf-line)",
                }}>
                  <div style={{
                    width: 30, height: 30, borderRadius: "50%", flex: "none",
                    background: "color-mix(in srgb, var(--color-accent-500) 18%, transparent)",
                    border: "1px solid var(--vf-line)", color: "var(--color-accent-600)",
                    display: "grid", placeItems: "center", fontSize: 12, fontWeight: 600,
                  }}>{c.user?.initials}</div>
                  <div>
                    <div style={{ fontSize: 14 }}>
                      <strong style={{ fontWeight: 600 }}>{c.user?.name}</strong>{" "}
                      <span style={{ color: "var(--color-neutral-600)" }}>
                        · {c.user?.department ?? c.user?.role_label} · {formatDateTime(c.created_at, locale)}
                      </span>
                    </div>
                    <div style={{ fontSize: 15, marginTop: 2 }}>{c.body}</div>
                  </div>
                </div>
              ))}
              <div style={{ display: "flex", gap: "var(--space-2)" }}>
                <input className="input" placeholder={t("addComment")} value={newComment}
                  onChange={(e) => setNewComment(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); postComment(); } }} />
                <button className="btn btn-secondary" onClick={postComment} disabled={!newComment.trim()}>{t("post")}</button>
              </div>
            </Disclosure>

            <Disclosure title={t("approvalTimeline")} count={voucher.timeline?.length ?? 0} icon="ph-list-checks">
              <div className="vf-timeline">
                {voucher.timeline?.map((row, index) => {
                  const last = index === (voucher.timeline?.length ?? 0) - 1;
                  const tone = row.state === "rejected" ? "var(--vf-bad)"
                    : row.state === "done" ? "var(--vf-ok)"
                    : row.state === "current" ? "var(--vf-warn)" : "var(--color-neutral-500)";
                  const lit = row.state !== "pending";

                  return (
                    <div key={index} className="vf-tl-row">
                      <div className="vf-tl-rail">
                        <span className={`vf-tl-dot${row.state === "current" ? " vf-tl-live" : ""}`}
                          style={{
                            color: tone,
                            borderColor: lit ? `color-mix(in srgb, ${tone} 40%, transparent)` : "var(--vf-line)",
                            background: lit ? `color-mix(in srgb, ${tone} 13%, transparent)` : "var(--vf-elev-2)",
                          }}>
                          <Icon name={row.icon} size={13} color={tone} />
                        </span>
                        {!last && (
                          <span className="vf-tl-line" style={{
                            background: row.state === "done"
                              ? "color-mix(in srgb, var(--vf-ok) 42%, transparent)" : "var(--vf-line)",
                          }} />
                        )}
                      </div>
                      <div className="vf-tl-body" style={{ color: lit ? "var(--color-text)" : "var(--color-neutral-600)" }}>
                        <div style={{ fontSize: 11, letterSpacing: ".08em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
                          {locale === "sw" ? row.sub_sw : row.sub}
                        </div>
                        <div style={{ fontSize: 15, fontWeight: 600 }}>
                          {locale === "sw" && row.name_sw ? row.name_sw : row.name}
                        </div>
                        <div style={{ fontSize: 14, color: "var(--color-neutral-700)" }}>{row.person}</div>
                        <div style={{ fontSize: 14, color: tone, fontWeight: 500 }}>
                          {locale === "sw" ? row.act_sw : row.act}
                          {row.when ? <span style={{ color: "var(--color-neutral-600)", fontWeight: 400 }}> · {formatDateTime(row.when, locale)}</span> : null}
                        </div>
                        {row.comment && (
                          <div style={{
                            fontSize: 13.5, color: "var(--color-neutral-700)", marginTop: 6,
                            borderLeft: "2px solid var(--vf-line-strong)", paddingLeft: 10, fontStyle: "italic",
                          }}>{row.comment}</div>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </Disclosure>

            <Disclosure title={t("auditTrail")} icon="ph-scroll">
              <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)", lineHeight: 1.75, fontVariantNumeric: "tabular-nums" }}>
                <div>Created {formatDateTime(voucher.created_at, locale)}</div>
                {voucher.submitted_at && <div>Submitted {formatDateTime(voucher.submitted_at, locale)}</div>}
                {voucher.approved_at && <div>Approved {formatDateTime(voucher.approved_at, locale)}</div>}
                {voucher.rejected_at && <div>Rejected {formatDateTime(voucher.rejected_at, locale)}</div>}
                {voucher.paid_at && <div>Paid {formatDateTime(voucher.paid_at, locale)} · {voucher.paid_by}</div>}
                {voucher.payment_reference && <div>{t("paymentRef")} {voucher.payment_reference}</div>}
                {voucher.verification_code && <div>{t("verificationCode")} {voucher.verification_code}</div>}
              </div>
            </Disclosure>
          </div>
        </div>

        {/* ── what to do now ── */}
        <div className="vf-sticky no-print">
          {(canAct || a?.submit) ? (
            <div className="vf-panel" style={{ borderColor: "var(--color-accent-500)", padding: "var(--space-4)" }}>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 18, marginBottom: 2 }}>
                {step?.name ?? t("yourDecision")}
              </div>
              {step && (
                <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)", marginBottom: "var(--space-3)" }}>
                  {t("thisStepMay")}: {Object.entries(step.capabilities).filter(([, on]) => on).map(([k]) => k.replace(/_/g, " ")).join(" · ") || t("viewOnly")}.
                </div>
              )}

              {a?.submit && (
                <button className="btn btn-primary btn-block" onClick={() => openDialog("submit")}>
                  <Icon name="ph-paper-plane-tilt" size={15} /> {t("submitApproval")}
                </button>
              )}

              {a?.sign && (
                <>
                  <button className="btn btn-primary btn-block" onClick={() => openDialog("sign")}>
                    <Icon name="ph-signature" size={15} /> {t("signVoucher")}
                  </button>
                  {!step?.capabilities.approve && (
                    <div style={{ fontSize: 13, color: "var(--color-neutral-600)", marginTop: 6 }}>{t("signNoApprove")}</div>
                  )}
                </>
              )}

              {a?.submit_signed && (
                <>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: "var(--space-3)" }}>
                    <Stamp kind="signed" scale={.8} tilt={-3} />
                    <span style={{ fontSize: 13.5, color: "var(--color-neutral-700)" }}>{t("signedByYou")}</span>
                  </div>
                  <button className="btn btn-primary btn-block" onClick={() => openDialog("submit_signed")}>
                    <Icon name="ph-paper-plane-tilt" size={15} /> {t("submitSigned")}
                  </button>
                </>
              )}

              {a?.approve && (
                <button className="btn btn-primary btn-block" onClick={() => openDialog("approve")}>
                  <Icon name="ph-seal-check" size={15} /> {t("approveVoucher")}
                </button>
              )}

              {a?.pay && (
                <>
                  <button className="btn btn-primary btn-block" onClick={() => openDialog("pay")}>
                    <Icon name="ph-wallet" size={15} /> {voucher.kind === "cash" ? t("releaseFunds") : t("recordPayment")}
                  </button>
                  <div style={{ fontSize: 13, color: "var(--color-neutral-600)", marginTop: 6 }}>{t("payNote")}</div>
                </>
              )}

              {(a?.request_changes || a?.reject) && (
                <div style={{ display: "flex", gap: "var(--space-2)", marginTop: "var(--space-2)" }}>
                  {a?.request_changes && <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => openDialog("request_changes")}>{t("requestChanges")}</button>}
                  {a?.reject && <button className="btn btn-secondary btn-danger" style={{ flex: 1 }} onClick={() => openDialog("reject")}>{t("reject")}</button>}
                </div>
              )}

              <div style={{ marginTop: "var(--space-3)", paddingTop: "var(--space-3)", borderTop: "1px solid var(--vf-line)" }}>
                <Note>{t("clearedNote")}</Note>
              </div>
            </div>
          ) : (
            <div className="vf-panel" style={{ padding: "var(--space-4)" }}>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 17 }}>
                {voucher.status_label}
              </div>
              <p style={{ fontSize: 13.5, color: "var(--color-neutral-700)", margin: "6px 0 0" }}>
                {voucher.is_terminal ? t("historyInReports") : t("nothingOnYou")}
              </p>
            </div>
          )}

          {/* Who has put their name to it, at a glance. */}
          <div className="vf-panel" style={{ padding: "var(--space-4)", marginTop: "var(--space-3)" }}>
            <div style={{ fontSize: 11.5, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
              {t("authorisation")}
            </div>
            <div style={{ display: "grid", gap: "var(--space-3)" }}>
              <MarkRow caption={t("preparedBy")} name={voucher.requester?.name ?? "—"} />
              {marks.map((m) => (
                <MarkRow key={m.caption} caption={m.caption} name={m.name} when={m.when} stamp={m.stamp} />
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* ── dialogs ── */}
      <Dialog
        open={dialog === "sign" || dialog === "approve"}
        title={dialog === "approve" ? t("approveVoucher") : t("signVoucher")}
        onClose={() => setDialog(null)}
        wide
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(null)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary"
              disabled={busy || (dialog === "sign" ? !signValid : !statement)}
              onClick={() => run(dialog as Action)}>
              {busy ? <Spinner /> : dialog === "approve" ? t("approveVoucher") : t("signVoucher")}
            </button>
          </>
        }
      >
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <div style={{ fontSize: 14.5 }}>
            {voucher.number} · {voucher.amount_text} · {voucher.payee}
          </div>

          {(dialog === "sign" || step?.capabilities.sign) && (
            <SignaturePad
              value={signature}
              onChange={setSignature}
              hasSaved={!!user?.has_signature}
              savedSignature={savedSignature}
            />
          )}

          {dialog === "sign" && (
            <label className="radio">
              <input type="checkbox" checked={saveSignature} onChange={(e) => setSaveSignature(e.target.checked)} />
              <span className="dot" />
              Save this signature for next time
            </label>
          )}

          <Field label={dialog === "approve" ? t("approvalNote") : t("commentOptional")} htmlFor="act-comment">
            <textarea id="act-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 70 }} />
          </Field>

          <label className="radio" style={{ alignItems: "flex-start" }}>
            <input type="checkbox" checked={statement} onChange={(e) => setStatement(e.target.checked)} />
            <span className="dot" style={{ marginTop: 3 }} />
            <span style={{ fontSize: 14 }}>{dialog === "approve" ? t("approveStatement") : t("signStatement")}</span>
          </label>

          {dialog === "sign" && !step?.capabilities.approve && (
            <div style={{ fontSize: 13.5, color: "var(--color-neutral-700)", borderLeft: "2px solid var(--color-accent-300)", paddingLeft: 10 }}>
              {t("signNoApprove")}
            </div>
          )}
        </div>
      </Dialog>

      <Dialog
        open={dialog === "reject" || dialog === "request_changes"}
        title={dialog === "reject" ? t("reject") : t("requestChanges")}
        onClose={() => setDialog(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(null)} disabled={busy}>{t("cancel")}</button>
            <button className={`btn ${dialog === "reject" ? "btn-secondary btn-danger" : "btn-primary"}`}
              disabled={busy || comment.trim().length < 3} onClick={() => run(dialog as Action)}>
              {busy ? <Spinner /> : dialog === "reject" ? t("reject") : t("requestChanges")}
            </button>
          </>
        }
      >
        <Field label={dialog === "reject" ? t("rejectReason") : t("changesNeeded")} htmlFor="reason" required>
          <textarea id="reason" className="input" value={comment} onChange={(e) => setComment(e.target.value)}
            style={{ minHeight: 96 }} autoFocus
            placeholder={dialog === "reject" ? "Explain why this cannot be approved." : "Tell the requester exactly what to change."} />
        </Field>
        <div style={{ fontSize: 13.5, color: "var(--color-neutral-600)" }}>
          {voucher.requester?.name} will be notified, and this note goes on the permanent record.
        </div>
      </Dialog>

      <Dialog
        open={dialog === "submit" || dialog === "submit_signed"}
        title={dialog === "submit_signed" ? t("submitSigned") : t("submitApproval")}
        onClose={() => setDialog(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(null)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={() => run(dialog as Action)} disabled={busy}>
              {busy ? <Spinner /> : t("confirm")}
            </button>
          </>
        }
      >
        <p style={{ marginTop: 0 }}>
          {dialog === "submit_signed"
            ? "Your signature is captured. Submitting hands the voucher to the next step in your company's workflow."
            : `${voucher.number} will enter the approval workflow and can no longer be edited.`}
        </p>
        <Field label={t("commentOptional")} htmlFor="submit-comment">
          <textarea id="submit-comment" className="input" value={comment} onChange={(e) => setComment(e.target.value)} style={{ minHeight: 66 }} />
        </Field>
      </Dialog>

      <Dialog
        open={dialog === "pay"}
        title={voucher.kind === "cash" ? t("releaseFunds") : t("recordPayment")}
        onClose={() => setDialog(null)}
        actions={
          <>
            <button className="btn btn-secondary" onClick={() => setDialog(null)} disabled={busy}>{t("cancel")}</button>
            <button className="btn btn-primary" onClick={() => run("pay")}
              disabled={busy || (voucher.kind === "cash" ? !receivedBy.trim() : !payReference.trim())}>
              {busy ? <Spinner /> : t("markPaid")}
            </button>
          </>
        }
      >
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          <div style={{
            display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12,
            padding: "12px 14px", borderRadius: 12, background: "var(--vf-elev-2)", border: "1px solid var(--vf-line)",
          }}>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 13, color: "var(--color-neutral-600)" }}>{voucher.number} · {voucher.payee}</div>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 22, letterSpacing: "-.03em" }}>
                {voucher.amount_text}
              </div>
            </div>
            <KindChip kind={voucher.kind} size={12} />
          </div>

          <Field label={t("payFrom")} htmlFor="pay-method">
            <select id="pay-method" className="input" value={payMethod} onChange={(e) => setPayMethod(e.target.value)}>
              {(voucher.kind === "cash"
                ? ["Cash — office float", "Cash — branch float"]
                : ["Bank transfer", "Cheque", "Mobile money"]
              ).map((option) => <option key={option} value={option}>{option}</option>)}
            </select>
          </Field>

          {voucher.kind !== "cash" && (
            <Field
              label={/cheque/i.test(payMethod) ? t("chequeNo") : t("paymentRef")}
              htmlFor="pay-ref"
              required
              hint={/cheque/i.test(payMethod) ? "e.g. 004471" : "e.g. CRDB-TRX-8841207"}
            >
              <input id="pay-ref" className="input" value={payReference} autoFocus
                onChange={(e) => setPayReference(e.target.value)} />
            </Field>
          )}

          {voucher.kind === "cash" && (
            <Field label={t("receivedBy")} htmlFor="pay-received" required
              hint="Printed on the voucher as the acknowledgement of receipt">
              <input id="pay-received" className="input" value={receivedBy}
                onChange={(e) => setReceivedBy(e.target.value)} />
            </Field>
          )}

          <Field label={t("commentOptional")} htmlFor="pay-comment">
            <textarea id="pay-comment" className="input" value={comment}
              onChange={(e) => setComment(e.target.value)} style={{ minHeight: 62 }} />
          </Field>

          <Note>{t("payNote")}</Note>
        </div>
      </Dialog>

    </div>
  );
}

function Detail({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <div style={{ fontSize: 11.5, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>{label}</div>
      <div style={{ fontSize: 16, fontVariantNumeric: mono ? "tabular-nums" : undefined, overflowWrap: "anywhere" }}>{value}</div>
    </div>
  );
}

/** Pulls the acting name and moment out of a timeline row, if it happened. */
function pick(row?: { person?: string; when?: string | null }) {
  return { name: row?.when ? row.person ?? null : null, when: row?.when ?? null };
}

/** One line of the authorisation panel: caption, mark, name and moment. */
function MarkRow({ caption, name, when, stamp }: {
  caption: string; name: string | null; when?: string | null; stamp?: StampKind;
}) {
  const { locale } = useApp();
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ minWidth: 0, flex: 1 }}>
        <div style={{ fontSize: 11, letterSpacing: ".08em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
          {caption}
        </div>
        <div style={{ fontSize: 14.5, fontWeight: 600, color: name ? "var(--color-text)" : "var(--color-neutral-600)" }}>
          {name ?? "—"}
        </div>
        {when && (
          <div style={{ fontSize: 12, color: "var(--color-neutral-600)", fontVariantNumeric: "tabular-nums" }}>
            {formatDateTime(when, locale)}
          </div>
        )}
      </div>
      {name && stamp && (
        <span className="vf-mark-chip"><Stamp kind={stamp} scale={.62} tilt={-3} /></span>
      )}
    </div>
  );
}
