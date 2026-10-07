"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDateTime } from "@/lib/format";
import { Dialog, Icon, Panel, Spinner } from "@/components/ui";
import { DocumentFrame, TemplateGallery, TemplatePreviewDialog, templateName } from "@/components/voucher-templates";
import type { VoucherTemplateChange, VoucherTemplateState } from "@/lib/types";

/**
 * A company's voucher design, and what may be done about it.
 *
 * `company` mode is the tenant's own Branding page: the administrator may
 * change the design as many times as the platform allows (one), then asks the
 * platform. `platform` mode is the super admin's company page: any design, any
 * time, with a reason, and the full history. The server enforces all of it —
 * this only reflects what the server says is possible.
 */

type Mode = "company" | "platform";

const COPY = {
  title: ["Voucher design", "Muundo wa vocha"],
  sub: ["The design every voucher this company issues is printed in. Data and approvals never change — only the layout.", "Muundo ambao kila vocha ya kampuni hii inachapishwa nao. Taarifa na idhini hazibadiliki — mpangilio pekee."],
  current: ["Current design", "Muundo unaotumika"],
  remaining: ["Template changes remaining", "Mabadiliko ya kiolezo yaliyobaki"],
  used: ["Template changes", "Mabadiliko ya kiolezo"],
  usedSuffix: ["used", "yametumika"],
  change: ["Change template", "Badilisha kiolezo"],
  view: ["View full size", "Tazama kwa ukubwa kamili"],
  lockedTitle: ["Template changes remaining: 0", "Mabadiliko ya kiolezo yaliyobaki: 0"],
  locked: ["Your voucher template can no longer be changed from company settings. Contact VouchFlow support (support@vouchflow.co.tz) or your platform administrator if you need another change.", "Kiolezo cha vocha yenu hakiwezi tena kubadilishwa kupitia mipangilio ya kampuni. Wasiliana na msaada wa VouchFlow (support@vouchflow.co.tz) au msimamizi wa jukwaa kama mnahitaji badiliko jingine."],
  request: ["Request a change", "Omba badiliko"],
  requestTitle: ["Request a template change", "Omba kubadilisha kiolezo"],
  requestSub: ["The VouchFlow platform team is notified and can switch your design for you.", "Timu ya jukwaa la VouchFlow itaarifiwa na inaweza kubadilisha muundo wenu."],
  wanted: ["Template you would like", "Kiolezo mnachotaka"],
  reason: ["Reason", "Sababu"],
  reasonHint: ["A sentence is enough — it helps the platform team decide.", "Sentensi moja inatosha — inasaidia timu ya jukwaa kuamua."],
  send: ["Send request", "Tuma ombi"],
  sent: ["Request sent", "Ombi limetumwa"],
  chooseTitle: ["Choose a new voucher template", "Chagua kiolezo kipya cha vocha"],
  chooseSubCompany: ["This uses your one template change. Preview any design before you commit.", "Hii inatumia badiliko lenu moja la kiolezo. Hakiki muundo wowote kabla ya kuamua."],
  chooseSubPlatform: ["Platform override — the company's own allowance is not affected.", "Mamlaka ya jukwaa — kiasi cha kampuni hakiathiriwi."],
  changeTo: ["Change to this template", "Badilisha kwenda kiolezo hiki"],
  confirmTitle: ["Change the voucher template?", "Badilisha kiolezo cha vocha?"],
  confirmCompany: ["This uses your only template change. Afterwards the template can be changed only by the VouchFlow platform team.", "Hii inatumia badiliko lenu pekee la kiolezo. Baada ya hapo kiolezo kinaweza kubadilishwa na timu ya jukwaa la VouchFlow pekee."],
  confirmPlatform: ["New vouchers will use the new design. Documents already approved, paid or rejected keep the design they were issued in.", "Vocha mpya zitatumia muundo mpya. Nyaraka zilizokwisha kuidhinishwa, kulipwa au kukataliwa zinabaki na muundo zilizotolewa nao."],
  historyNote: ["Documents already approved, paid or rejected keep the design they were issued in.", "Nyaraka zilizokwisha kuidhinishwa, kulipwa au kukataliwa zinabaki na muundo zilizotolewa nao."],
  from: ["From", "Kutoka"], to: ["To", "Kwenda"],
  confirm: ["Change template", "Badilisha kiolezo"],
  cancel: ["Cancel", "Ghairi"],
  changed: ["Voucher template changed", "Kiolezo cha vocha kimebadilishwa"],
  history: ["Template history", "Historia ya kiolezo"],
  previous: ["Previous", "Kilichotangulia"], next: ["New", "Kipya"],
  by: ["Changed by", "Kimebadilishwa na"], role: ["Role", "Wadhifa"], date: ["Date", "Tarehe"],
  source: ["Source", "Chanzo"], reasonCol: ["Reason", "Sababu"],
  noHistory: ["No changes recorded yet.", "Hakuna mabadiliko yaliyorekodiwa bado."],
  optional: ["Reason (optional)", "Sababu (si lazima)"],
  unavailable: ["Voucher designs are rendered by the VouchFlow server and are not available right now (the offline demo cannot show them).", "Miundo ya vocha hutengenezwa na seva ya VouchFlow na haipatikani kwa sasa (onyesho la nje ya mtandao haliwezi kuionyesha)."],
  adminOnly: ["Only the company administrator can change the template.", "Msimamizi wa kampuni pekee anaweza kubadilisha kiolezo."],
} as const;

const SOURCES: Record<VoucherTemplateChange["source"], [string, string]> = {
  registration: ["Registration", "Usajili"],
  company_admin: ["Company settings", "Mipangilio ya kampuni"],
  super_admin: ["Platform override", "Mamlaka ya jukwaa"],
  platform_create: ["Created by platform", "Imeundwa na jukwaa"],
};

const ROLES: Record<string, [string, string]> = {
  company_admin: ["Company admin", "Msimamizi wa kampuni"],
  super_admin: ["Super admin", "Msimamizi mkuu"],
};

export function VoucherTemplatePanel({
  mode, companyId, previews, previewsLoading, onChanged, canManage = true,
}: {
  mode: Mode;
  companyId?: number;
  /** Sample documents keyed by template, in this company's letterhead. */
  previews: Record<string, string>;
  previewsLoading?: boolean;
  onChanged?: (state: VoucherTemplateState) => void;
  /** Company mode: whether the viewer is the company administrator. */
  canManage?: boolean;
}) {
  const { locale, toast, reportError } = useApp();
  const c = (key: keyof typeof COPY) => COPY[key][locale === "sw" ? 1 : 0];
  const base = mode === "platform" ? `/platform/companies/${companyId}/voucher-template` : "/company/voucher-template";

  const [state, setState] = useState<VoucherTemplateState | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [choosing, setChoosing] = useState(false);
  const [previewing, setPreviewing] = useState<string | null>(null);
  const [pending, setPending] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [requesting, setRequesting] = useState(false);
  const [requestTemplate, setRequestTemplate] = useState("");

  const load = useCallback(() => {
    api.get<VoucherTemplateState>(base)
      // Only a real template state is trusted; anything else (the offline
      // mock, an old server) is treated as "designs unavailable".
      .then((r) => {
        if (r && Array.isArray(r.templates) && Array.isArray(r.history)) { setState(r); setLoadError(false); }
        else setLoadError(true);
      })
      .catch(() => setLoadError(true));
  }, [base]);

  useEffect(load, [load]);

  if (loadError) {
    return (
      <Panel title={c("title")} sub={c("sub")}>
        <div className="vt-locked" role="status">
          <Icon name="ph-info" size={17} />
          <span>{c("unavailable")}</span>
        </div>
      </Panel>
    );
  }
  if (!state) {
    return <Panel title={c("title")}><Spinner /></Panel>;
  }

  const templates = state.templates;
  const current = templates.find((t) => t.key === state.template);
  const nameOf = (key: string | null) => templateName(templates.find((t) => t.key === key), locale);
  const spent = state.changes_remaining <= 0;
  const mayChange = mode === "platform" || (canManage && !spent);

  async function apply() {
    if (!pending) return;
    setBusy(true);
    try {
      const next = await api.put<VoucherTemplateState>(base, { template: pending, reason: reason.trim() || null });
      setState(next);
      onChanged?.(next);
      toast(c("changed"), nameOf(pending), "ok");
      setPending(null);
      setChoosing(false);
      setPreviewing(null);
      setReason("");
    } catch (err) {
      reportError(err);
      load();
    } finally {
      setBusy(false);
    }
  }

  async function sendRequest() {
    setBusy(true);
    try {
      await api.post("/company/voucher-template/request", { template: requestTemplate, reason: reason.trim() });
      toast(c("sent"), nameOf(requestTemplate), "ok");
      setRequesting(false);
      setReason("");
    } catch (err) {
      reportError(err);
    } finally {
      setBusy(false);
    }
  }

  const choose = (key: string) => { setPreviewing(null); setReason(""); setPending(key); };

  return (
    <Panel title={c("title")} sub={c("sub")}>
      <div className="vt-current-wrap">
      <div className="vt-current">
        <button type="button" className="vt-current-thumb" onClick={() => setPreviewing(state.template)} aria-label={`${c("view")}: ${nameOf(state.template)}`}>
          {previews[state.template]
            ? <DocumentFrame html={previews[state.template]} fit="page" title={nameOf(state.template)} />
            : <span className="vt-thumb-skeleton" aria-hidden="true" />}
        </button>

        <div className="vt-current-body">
          <div>
            <div className="vt-num">{c("current")}</div>
            <div className="vt-current-name">
              <strong>{nameOf(state.template)}</strong>
              {current && <span className="vt-num tnum">{String(current.number).padStart(2, "0")}</span>}
            </div>
            {current && <p style={{ margin: "2px 0 0", fontSize: 13, color: "var(--color-neutral-600)" }}>{locale === "sw" ? current.description_sw : current.description}</p>}
          </div>

          {mode === "company" ? (
            <span className="vt-meter" data-spent={spent || undefined}>
              <Icon name={spent ? "ph-lock-simple" : "ph-arrows-clockwise"} size={15} />
              {c("remaining")}: <b>{state.changes_remaining}</b>
            </span>
          ) : (
            <span className="vt-meter" data-spent={spent || undefined}>
              <Icon name="ph-arrows-clockwise" size={15} />
              {c("used")}: <b>{state.changes_used} / {state.changes_allowed}</b> {c("usedSuffix")}
            </span>
          )}

          {mode === "company" && spent && (
            <div className="vt-locked" role="status">
              <Icon name="ph-lock-simple" size={17} />
              <span>{c("locked")}</span>
            </div>
          )}
          {mode === "company" && !canManage && !spent && (
            <div className="vt-locked"><Icon name="ph-info" size={17} /><span>{c("adminOnly")}</span></div>
          )}

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => setPreviewing(state.template)}>
              <Icon name="ph-eye" size={14} /> {c("view")}
            </button>
            {mayChange && (
              <button type="button" className="btn btn-primary btn-sm" onClick={() => setChoosing(true)}>
                <Icon name="ph-layout" size={14} /> {c("change")}
              </button>
            )}
            {mode === "company" && canManage && spent && (
              <button type="button" className="btn btn-primary btn-sm" onClick={() => { setReason(""); setRequestTemplate(templates.find((t) => t.key !== state.template)?.key ?? ""); setRequesting(true); }}>
                <Icon name="ph-paper-plane-tilt" size={14} /> {c("request")}
              </button>
            )}
          </div>
        </div>
      </div>

      </div>

      {(mode === "platform" || state.history.length > 0) && (
        <div style={{ marginTop: "var(--space-5, 20px)" }}>
          <div className="vt-num" style={{ marginBottom: 6 }}>{c("history")}</div>
          {state.history.length === 0 ? (
            <p style={{ margin: 0, fontSize: 13, color: "var(--color-neutral-600)" }}>{c("noHistory")}</p>
          ) : (
            <div className="vt-history-wrap">
              <table className="vt-history">
                <thead>
                  <tr>
                    <th>{c("previous")}</th><th>{c("next")}</th><th>{c("by")}</th><th>{c("role")}</th><th>{c("date")}</th><th>{c("source")}</th><th>{c("reasonCol")}</th>
                  </tr>
                </thead>
                <tbody>
                  {state.history.map((row) => (
                    <tr key={row.id}>
                      <td>{row.previous_template ? nameOf(row.previous_template) : "—"}</td>
                      <td><strong>{nameOf(row.new_template)}</strong></td>
                      <td>{row.changed_by_name ?? "—"}</td>
                      <td>{row.changed_by_role ? (ROLES[row.changed_by_role]?.[locale === "sw" ? 1 : 0] ?? row.changed_by_role) : "—"}</td>
                      <td className="tnum" style={{ whiteSpace: "nowrap" }}>{formatDateTime(row.created_at, locale)}</td>
                      <td>{SOURCES[row.source]?.[locale === "sw" ? 1 : 0] ?? row.source}</td>
                      <td style={{ color: "var(--color-neutral-600)" }}>{row.reason ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p style={{ margin: "8px 0 0", fontSize: 12.5, color: "var(--color-neutral-600)" }}>{c("historyNote")}</p>
        </div>
      )}

      {/* ── choosing a new design ── */}
      {choosing && previewing === null && pending === null && (
        <div className="vt-modal" role="dialog" aria-modal="true" aria-label={c("chooseTitle")} onMouseDown={(e) => { if (e.target === e.currentTarget) setChoosing(false); }}>
          <div className="vt-modal-card">
            <header className="vt-modal-head">
              <div className="vt-modal-title">
                <h2>{c("chooseTitle")}</h2>
                <p>{mode === "company" ? c("chooseSubCompany") : c("chooseSubPlatform")}</p>
              </div>
              <button type="button" className="btn btn-ghost btn-sm vt-modal-close" onClick={() => setChoosing(false)} aria-label={c("cancel")}>
                <Icon name="ph-x" size={18} />
              </button>
            </header>
            <div className="vt-modal-body" style={{ padding: 20 }}>
              <TemplateGallery
                templates={templates}
                previews={previews}
                selected={null}
                current={state.template}
                onSelect={(key) => { if (key !== state.template) choose(key); }}
                onPreview={setPreviewing}
                loading={previewsLoading}
              />
            </div>
          </div>
        </div>
      )}

      <TemplatePreviewDialog
        open={previewing !== null}
        templates={templates}
        previews={previews}
        active={previewing}
        selected={state.template}
        onNavigate={setPreviewing}
        onClose={() => setPreviewing(null)}
        onUse={mayChange ? choose : undefined}
        actionLabel={c("changeTo")}
        footerNote={mode === "company" && mayChange ? c("chooseSubCompany") : mode === "platform" ? c("chooseSubPlatform") : undefined}
      />

      <Dialog
        open={pending !== null}
        title={c("confirmTitle")}
        sub={mode === "company" ? c("confirmCompany") : c("confirmPlatform")}
        icon="ph-layout"
        tone={mode === "company" ? "warn" : "info"}
        busy={busy}
        onClose={() => setPending(null)}
        summary={[
          { label: c("from"), value: nameOf(state.template) },
          { label: c("to"), value: nameOf(pending) },
          ...(mode === "company" ? [{ label: c("remaining"), value: `${state.changes_remaining} → ${Math.max(0, state.changes_remaining - 1)}` }] : []),
        ]}
        actions={
          <>
            <button type="button" className="btn btn-secondary" onClick={() => setPending(null)} disabled={busy}>{c("cancel")}</button>
            <button type="button" className="btn btn-primary" onClick={() => void apply()} disabled={busy}>
              {busy ? <Spinner /> : <><Icon name="ph-check" size={16} /> {c("confirm")}</>}
            </button>
          </>
        }
      >
        <div className="field">
          <label htmlFor="vt-reason">{c("optional")}</label>
          <textarea id="vt-reason" className="input" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} style={{ minHeight: 64 }} />
        </div>
      </Dialog>

      <Dialog
        open={requesting}
        title={c("requestTitle")}
        sub={c("requestSub")}
        icon="ph-paper-plane-tilt"
        busy={busy}
        onClose={() => setRequesting(false)}
        actions={
          <>
            <button type="button" className="btn btn-secondary" onClick={() => setRequesting(false)} disabled={busy}>{c("cancel")}</button>
            <button type="button" className="btn btn-primary" onClick={() => void sendRequest()} disabled={busy || !requestTemplate || reason.trim().length < 5}>
              {busy ? <Spinner /> : <><Icon name="ph-paper-plane-tilt" size={16} /> {c("send")}</>}
            </button>
          </>
        }
      >
        <div style={{ display: "grid", gap: 12 }}>
          <div className="field">
            <label htmlFor="vt-wanted">{c("wanted")}</label>
            <select id="vt-wanted" className="input" value={requestTemplate} onChange={(e) => setRequestTemplate(e.target.value)}>
              {templates.filter((t) => t.key !== state.template).map((t) => (
                <option key={t.key} value={t.key}>{String(t.number).padStart(2, "0")} · {templateName(t, locale)}</option>
              ))}
            </select>
          </div>
          <div className="field">
            <label htmlFor="vt-request-reason">{c("reason")}</label>
            <textarea id="vt-request-reason" className="input" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} style={{ minHeight: 72 }} />
            <div className="field-hint">{c("reasonHint")}</div>
          </div>
        </div>
      </Dialog>
    </Panel>
  );
}
