"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, download, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, formatDateTime } from "@/lib/format";
import {
  Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, Spinner,
} from "@/components/ui";
import { DocumentActions } from "@/components/voucher-bits";
import { SignaturePad } from "@/components/signature-pad";
import type { Voucher } from "@/lib/types";

type Action = "sign" | "submit_signed" | "approve" | "reject" | "request_changes" | "submit" | "cancel";

export default function VoucherDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { t, locale, user, toast, reportError, refreshUnread } = useApp();

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

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher }>(`/vouchers/${params.id}`)
      .then((r) => setVoucher(r.data))
      .catch((err) => setError(err.message));
  }, [params.id]);

  useEffect(load, [load, locale]);

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
    setSignature(action === "sign" || action === "approve" ? (user?.has_signature ? savedSignature : null) : null);
  }

  async function run(action: Action) {
    if (!voucher) return;
    setBusy(true);
    try {
      const endpoint: Record<Action, string> = {
        sign: "sign", submit_signed: "submit-signed", approve: "approve",
        reject: "reject", request_changes: "request-changes", submit: "submit", cancel: "cancel",
      };

      const body: Record<string, unknown> = { comment: comment || undefined };
      if (action === "sign") {
        body.signature = signature;
        body.save_signature = saveSignature && !!signature;
      }
      if (action === "approve" && signature) body.signature = signature;

      const res = await api.post<{ data: Voucher }>(`/vouchers/${voucher.id}/${endpoint[action]}`, body);
      setVoucher(res.data);
      setDialog(null);
      void refreshUnread();

      const messages: Record<Action, [string, string]> = {
        sign: ["Voucher signed", `${res.data.number} carries your signature. Submit it onward when ready.`],
        submit_signed: ["Signed voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        approve: ["Voucher approved", `${res.data.number} is ${res.data.status === "approved" ? "completed and ready to print" : res.data.status_label.toLowerCase()}.`],
        reject: ["Voucher rejected", `${res.data.number} was returned to ${res.data.requester?.name ?? "the requester"}.`],
        request_changes: ["Changes requested", `${res.data.requester?.name ?? "The requester"} has been notified.`],
        submit: ["Voucher submitted", `${res.data.number} — ${res.data.status_label}`],
        cancel: ["Voucher cancelled", res.data.number],
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
  const canAct = a && (a.sign || a.submit_signed || a.approve || a.reject || a.request_changes);
  const signValid = statement && !!signature;

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

      <div className="vf-split">
        {/* ── body ── */}
        <div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-4) var(--space-6)", paddingBottom: "var(--space-4)", borderBottom: "1px solid var(--color-divider)" }}>
            <Detail label={t("payee")} value={voucher.payee} />
            <Detail label={t("requester")} value={voucher.requester?.name ?? "—"} />
            <Detail label={t("paymentMethod")} value={voucher.payment_method ?? "—"} />
            <Detail label={t("category")} value={voucher.category ?? "—"} />
            <Detail label={t("reference")} value={voucher.account_ref ?? "—"} mono />
            <Detail label={t("costCentre")} value={voucher.cost_centre ?? "—"} mono />
          </div>

          <h2 style={{ fontSize: 21, margin: "var(--space-6) 0 8px" }}>{voucher.purpose}</h2>
          {voucher.description && <p style={{ fontSize: 16.5, lineHeight: 1.6, color: "var(--color-neutral-800)", maxWidth: "62ch", margin: 0 }}>{voucher.description}</p>}
          {voucher.amount_in_words && (
            <p style={{ fontStyle: "italic", color: "var(--color-neutral-700)", marginTop: "var(--space-2)" }}>{voucher.amount_in_words}</p>
          )}

          {/* attachments */}
          <h3 style={{ fontSize: 18, margin: "var(--space-6) 0 10px" }}>{t("attachments")}</h3>
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
                    display: "flex", alignItems: "center", gap: 9, border: "1px solid var(--color-divider)",
                    borderRadius: "var(--radius-md)", padding: "9px var(--space-3)", fontSize: 14.5,
                    cursor: "pointer", background: "transparent", fontFamily: "var(--font-body)", color: "var(--color-text)",
                  }}>
                  <Icon name={file.icon} size={20} color="var(--color-accent-700)" />
                  <span>{file.name}</span>
                  <span style={{ color: "var(--color-neutral-600)", fontSize: 12.5 }}>{file.size}</span>
                  <Icon name="ph-arrow-square-out" size={14} style={{ opacity: .5 }} />
                </button>
              ))}
            </div>
          ) : (
            <p style={{ color: "var(--color-neutral-600)", fontSize: 14.5 }}>No documents attached.</p>
          )}

          {a?.edit && (
            <label className="btn btn-secondary btn-sm no-print" style={{ marginTop: "var(--space-3)" }}>
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

          {/* comments */}
          <h3 style={{ fontSize: 18, margin: "var(--space-8) 0 10px" }}>{t("comments")}</h3>
          {voucher.comments?.map((c) => (
            <div key={c.id} style={{ display: "flex", gap: "var(--space-3)", paddingBottom: "var(--space-3)", marginBottom: "var(--space-3)", borderBottom: "1px solid var(--color-divider)" }}>
              <div style={{ width: 30, height: 30, borderRadius: "50%", background: "var(--color-accent-200)", color: "var(--color-accent-800)", display: "grid", placeItems: "center", fontSize: 12, fontWeight: 600, flex: "none" }}>
                {c.user?.initials}
              </div>
              <div>
                <div style={{ fontSize: 14.5 }}>
                  <strong style={{ fontWeight: 600 }}>{c.user?.name}</strong>{" "}
                  <span style={{ color: "var(--color-neutral-600)" }}>
                    · {c.user?.department ?? c.user?.role_label} · {formatDateTime(c.created_at, locale)}
                  </span>
                </div>
                <div style={{ fontSize: 15.5, marginTop: 2 }}>{c.body}</div>
              </div>
            </div>
          ))}
          <div className="no-print" style={{ display: "flex", gap: "var(--space-2)" }}>
            <input className="input" placeholder={t("addComment")} value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); postComment(); } }} />
            <button className="btn btn-secondary" onClick={postComment} disabled={!newComment.trim()}>{t("post")}</button>
          </div>
        </div>

        {/* ── timeline & actions ── */}
        <div>
          <div style={{ border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: "var(--space-4)", background: "var(--color-neutral-100)" }}>
            <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-3)" }}>
              {t("approvalTimeline")}
            </div>
            {voucher.timeline?.map((row, index) => {
              const colour = row.state === "rejected" ? "var(--color-accent-2-500)"
                : row.state === "done" ? "var(--color-accent-500)"
                : row.state === "current" ? "var(--color-process-yellow)" : "var(--color-neutral-300)";
              const last = index === (voucher.timeline?.length ?? 0) - 1;

              return (
                <div key={index} style={{ display: "grid", gridTemplateColumns: "20px minmax(0,1fr)", gap: "var(--space-3)", paddingBottom: last ? 0 : "var(--space-4)" }}>
                  <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
                    <Icon name={row.icon} size={19} color={colour} />
                    {!last && <div style={{ flex: 1, width: 1, background: "var(--color-neutral-300)" }} />}
                  </div>
                  <div style={{ color: row.state === "pending" ? "var(--color-neutral-600)" : "var(--color-text)" }}>
                    <div style={{ fontSize: 11.5, letterSpacing: ".08em", textTransform: "uppercase", color: "var(--color-neutral-600)" }}>
                      {locale === "sw" ? row.sub_sw : row.sub}
                    </div>
                    <div style={{ fontSize: 16, fontWeight: 600 }}>{locale === "sw" && row.name_sw ? row.name_sw : row.name}</div>
                    <div style={{ fontSize: 14.5 }}>{row.person}</div>
                    <div style={{ fontSize: 14.5 }}>
                      {locale === "sw" ? row.act_sw : row.act}{row.when ? ` · ${formatDateTime(row.when, locale)}` : ""}
                    </div>
                    <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)", marginTop: 2 }}>
                      {t("permittedHere")}: {row.capability_text}
                    </div>
                    {row.signature && (
                      <img src={row.signature} alt="Signature" style={{ maxHeight: 46, marginTop: 6, background: "#fff", border: "1px solid var(--color-divider)", borderRadius: 2, padding: 2 }} />
                    )}
                    {row.comment && (
                      <div style={{ fontSize: 14.5, fontStyle: "italic", color: "var(--color-neutral-700)", borderLeft: "2px solid var(--color-accent-300)", paddingLeft: 10, marginTop: 6 }}>
                        {row.comment}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>

          {/* action panel */}
          {(canAct || a?.submit) && (
            <div className="no-print" style={{ border: "1px solid var(--color-accent-500)", borderRadius: "var(--radius-md)", padding: "var(--space-4)", marginTop: "var(--space-4)" }}>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 19, marginBottom: 2 }}>
                {step?.name ?? t("yourDecision")}
              </div>
              {step && (
                <div style={{ fontSize: 14.5, color: "var(--color-neutral-700)", marginBottom: "var(--space-3)" }}>
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
                  <div style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14.5, color: "var(--color-accent-700)", marginBottom: "var(--space-2)" }}>
                    <Icon name="ph-check-circle" size={19} /> Signed by you
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

              {(a?.request_changes || a?.reject) && (
                <div style={{ display: "flex", gap: "var(--space-2)", marginTop: "var(--space-2)" }}>
                  {a?.request_changes && <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => openDialog("request_changes")}>{t("requestChanges")}</button>}
                  {a?.reject && <button className="btn btn-secondary btn-danger" style={{ flex: 1 }} onClick={() => openDialog("reject")}>{t("reject")}</button>}
                </div>
              )}
            </div>
          )}

          {/* audit trail */}
          <div style={{ marginTop: "var(--space-4)", fontSize: 13.5, color: "var(--color-neutral-600)", lineHeight: 1.6 }}>
            <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", marginBottom: 8 }}>{t("auditTrail")}</div>
            <div>Created {formatDateTime(voucher.created_at, locale)}</div>
            {voucher.submitted_at && <div>Submitted {formatDateTime(voucher.submitted_at, locale)}</div>}
            {voucher.approved_at && <div>Approved {formatDateTime(voucher.approved_at, locale)}</div>}
            {voucher.rejected_at && <div>Rejected {formatDateTime(voucher.rejected_at, locale)}</div>}
            {voucher.verification_code && <div>{t("verificationCode")} {voucher.verification_code}</div>}
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
