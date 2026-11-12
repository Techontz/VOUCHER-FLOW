"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { OPEN_STAGES, type Opportunity, REASON_LABEL, type Stage, STAGE_LABEL } from "@/lib/crm-types";
import { Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { ActivityDialog, ActivityList, CloseDealDialog, StageBadge, useMoney, usePeople } from "@/components/crm-ui";
import { DealDialog } from "@/components/crm-deal-form";
import { RecordFiles } from "@/components/crm-attachments";

export default function OpportunityPage() {
  return <ErpGate module="crm" permission="crm.view"><OpportunityDetail /></ErpGate>;
}

function OpportunityDetail() {
  const { t, locale, toast } = useApp();
  const { can, has } = useErp();
  const money = useMoney();
  const people = usePeople();
  const { id } = useParams<{ id: string }>();
  const [deal, setDeal] = useState<Opportunity | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [closing, setClosing] = useState<"won" | "lost" | null>(null);
  const [scheduling, setScheduling] = useState(false);
  const [assigning, setAssigning] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Opportunity }>(`/erp/crm/opportunities/${id}`).then((r) => setDeal(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function move(stage: Stage) {
    if (!deal) return;
    try {
      await api.post(`/erp/crm/opportunities/${deal.id}/stage`, { stage });
      toast(fill(t("crmMoved"), { number: deal.number, stage: t(STAGE_LABEL[stage]) }), undefined, "ok");
      load();
    } catch (e) { toast(e instanceof Error ? e.message : String(e), undefined, "bad"); }
  }

  async function assign() {
    if (!deal || !assigning) return;
    setBusy(true); setActionError(null);
    try { await api.post(`/erp/crm/opportunities/${deal.id}/assign`, { owner_id: Number(assigning) }); setAssigning(null); load(); }
    catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} />;
  if (!deal) return <LoadingBlock rows={6} />;

  const manage = can("crm.manage");
  const open = OPEN_STAGES.includes(deal.stage);

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/crm/pipeline" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("crmNavPipeline")}</Link>}
        kicker={deal.number}
        title={deal.title}
        subtitle={[deal.customer?.name, money(deal.value), `${deal.probability}%`].filter(Boolean).join(" · ")}
        actions={<>
          <StageBadge stage={deal.stage} />
          {manage && <button className="btn btn-secondary" onClick={() => setEditing(true)}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {can("crm.assign") && <button className="btn btn-secondary" onClick={() => { setActionError(null); setAssigning(String(deal.owner_id ?? "")); }}><Icon name="ph-user-switch" size={17} /> {t("crmAssign")}</button>}
          {manage && open && <button className="btn btn-secondary" onClick={() => setClosing("lost")}>{t("crmCloseLost")}</button>}
          {manage && open && <button className="btn btn-primary" onClick={() => setClosing("won")}><Icon name="ph-trophy" size={17} /> {t("crmCloseWon")}</button>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard title={t("crmDetails")}>
          <dl className="erp-review">
            <dt>{t("crmStage")}</dt>
            <dd>{manage ? (
              <select className="input" aria-label={t("crmMoveTo")} value={deal.stage} onChange={(e) => {
                const next = e.target.value as Stage;
                if (next === "won" || next === "lost") setClosing(next); else move(next);
              }}>
                {(["prospecting", "proposal", "negotiation", "won", "lost"] as Stage[]).map((s) => <option key={s} value={s}>{t(STAGE_LABEL[s])}</option>)}
              </select>
            ) : <StageBadge stage={deal.stage} />}</dd>
            <dt>{t("crmValue")}</dt><dd className="tnum">{money(deal.value)}</dd>
            <dt>{t("crmProbability")}</dt><dd className="tnum">{deal.probability}%</dd>
            <dt>{t("crmCloseDate")}</dt><dd>{deal.expected_close_date ? formatDate(deal.expected_close_date, locale) : "-"}</dd>
            <dt>{t("crmOwner")}</dt><dd>{deal.owner?.name ?? "-"}</dd>
            {deal.customer && <><dt>{t("crmCustomer")}</dt><dd>{deal.customer.name} <span className="erp-muted tnum">{deal.customer.code}</span></dd></>}
            {deal.lead && <><dt>{t("crmFromLead")}</dt><dd><Link href={`/erp/crm/leads/${deal.lead.id}`}>{deal.lead.number} · {deal.lead.contact_name}</Link></dd></>}
            {deal.closed_at && <><dt>{t("crmClosed")}</dt><dd>{formatDate(deal.closed_at, locale)}{deal.close_reason ? ` · ${t(REASON_LABEL[deal.close_reason] ?? "crmReasonOther")}` : ""}{deal.close_note ? ` · ${deal.close_note}` : ""}</dd></>}
            {deal.notes && <><dt>{t("crmNotes")}</dt><dd style={{ whiteSpace: "pre-wrap" }}>{deal.notes}</dd></>}
          </dl>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("crmActivities")} pad={false}
          action={manage && <button className="btn btn-secondary btn-sm" onClick={() => setScheduling(true)}><Icon name="ph-plus" size={15} /> {t("crmNewActivity")}</button>}>
          <ActivityList rows={deal.activities ?? []} onChanged={load} manage={manage} empty={t("crmNoActivities")} />
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("crmHistory")} pad={false}>
          <ul className="erp-list">
            {(deal.history ?? []).map((h) => (
              <li key={h.id} className="crm-activity">
                <span className="erp-list-icon"><Icon name="ph-clock-counter-clockwise" size={16} /></span>
                <span className="erp-list-main">
                  <span className="erp-list-title">{h.description}</span>
                  <span className="erp-list-sub">{h.actor_name} · {formatDateTime(h.created_at, locale)}{h.change_summary ? ` · ${h.change_summary}` : ""}</span>
                </span>
              </li>
            ))}
          </ul>
        </GlassCard>

        {has("documents") && can("documents.view") && <div><RecordFiles type="opportunity" id={deal.id} /></div>}
      </div>

      {editing && <DealDialog deal={deal} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load(); }} />}
      <ActivityDialog open={scheduling} onClose={() => setScheduling(false)} onSaved={load} link={{ opportunity_id: deal.id, customer_id: deal.customer_id }} />
      <CloseDealDialog deal={closing ? deal : null} stage={closing ?? "won"} onClose={() => setClosing(null)}
        onDone={(d) => { setClosing(null); toast(fill(t("crmMoved"), { number: d.number, stage: t(STAGE_LABEL[d.stage]) }), undefined, "ok"); load(); }} />

      <Dialog open={assigning !== null} title={t("crmAssign")} onClose={() => setAssigning(null)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setAssigning(null)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" disabled={busy || !assigning} onClick={assign}>{t("crmAssign")}</button>
        </>}>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
        <Field label={t("crmAssignTo")} htmlFor="oa-owner">
          <select id="oa-owner" className="input" value={assigning ?? ""} onChange={(e) => setAssigning(e.target.value)}>
            <option value="" disabled>-</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
      </Dialog>
    </div>
  );
}
