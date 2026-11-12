"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { compactMoney, formatDate } from "@/lib/format";
import { type BoardColumn, type Opportunity, type Stage, STAGE_LABEL, STAGES } from "@/lib/crm-types";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { CloseDealDialog, CrmTabs } from "@/components/crm-ui";
import { DealDialog } from "@/components/crm-deal-form";

export default function PipelinePage() {
  return <ErpGate module="crm" permission="crm.view"><Pipeline /></ErpGate>;
}

/**
 * The Kanban board. Dragging a card to another column asks the API to move
 * the deal (which locks it and writes the audit entry); won and lost first ask
 * why. On a phone, where dragging is awkward, each card has a stage menu.
 */
function Pipeline() {
  const { t, locale, toast } = useApp();
  const { can, config } = useErp();
  const currency = config?.settings.base_currency ?? "TZS";
  const manage = can("crm.manage");
  const [columns, setColumns] = useState<BoardColumn[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState<Opportunity | null>(null);
  const [over, setOver] = useState<Stage | null>(null);
  const [closing, setClosing] = useState<{ deal: Opportunity; stage: "won" | "lost" } | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    api.get<{ data: BoardColumn[] }>("/erp/crm/opportunities/board").then((r) => setColumns(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  async function move(deal: Opportunity, stage: Stage) {
    if (deal.stage === stage) return;
    if (stage === "won" || stage === "lost") { setClosing({ deal, stage }); return; }

    // Show the move at once; the reload puts the board back if the API refuses.
    setColumns((cols) => cols && cols.map((c) => ({
      ...c,
      items: c.stage === stage ? [{ ...deal, stage }, ...c.items] : c.items.filter((i) => i.id !== deal.id),
    })));
    try {
      await api.post(`/erp/crm/opportunities/${deal.id}/stage`, { stage });
      toast(fill(t("crmMoved"), { number: deal.number, stage: t(STAGE_LABEL[stage]) }), undefined, "ok");
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e), undefined, "bad");
    } finally {
      load();
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!columns) return <LoadingBlock rows={6} />;

  return (
    <div className="erp-page">
      <PageHeader title={t("crmNavPipeline")} subtitle={t("crmPipelineSub")}
        actions={manage && <button className="btn btn-primary" onClick={() => setCreating(true)}><Icon name="ph-plus" size={18} /> {t("crmNewOpportunity")}</button>} />
      <CrmTabs />

      <div className="crm-board">
        {columns.map((col) => (
          <section key={col.stage} className="crm-column" aria-label={t(STAGE_LABEL[col.stage])}
            data-over={over === col.stage ? "" : undefined}
            onDragOver={manage ? (e) => { e.preventDefault(); setOver(col.stage); } : undefined}
            onDragLeave={() => setOver((s) => (s === col.stage ? null : s))}
            onDrop={manage ? (e) => { e.preventDefault(); setOver(null); if (dragging) move(dragging, col.stage); setDragging(null); } : undefined}>
            <header className="crm-column-head">
              <h2>{t(STAGE_LABEL[col.stage])} <span className="erp-muted tnum">({col.items.length})</span></h2>
              <span className="crm-column-sum tnum">{compactMoney(col.items.reduce((s, i) => s + Number(i.value), 0), currency)}</span>
            </header>
            {(col.stage === "won" || col.stage === "lost") && <span className="crm-column-sum">{t("crmRecentClosed")}</span>}
            {col.items.length === 0 ? <EmptyState icon="ph-tray" title={t("crmEmptyStage")} /> : col.items.map((deal) => (
              <article key={deal.id} className="crm-card" draggable={manage}
                data-dragging={dragging?.id === deal.id ? "" : undefined}
                onDragStart={(e) => { e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", String(deal.id)); setDragging(deal); }}
                onDragEnd={() => { setDragging(null); setOver(null); }}>
                <Link href={`/erp/crm/opportunities/${deal.id}`} className="crm-card-title">{deal.title}</Link>
                <span className="crm-card-meta"><span>{deal.customer?.name ?? deal.number}</span><span className="tnum">{deal.probability}%</span></span>
                <span className="crm-card-meta">
                  <span className="tnum">{compactMoney(Number(deal.value), currency)}</span>
                  <span>{deal.expected_close_date ? formatDate(deal.expected_close_date, locale) : ""}</span>
                </span>
                {deal.owner && <span className="crm-card-meta"><span>{deal.owner.name}</span></span>}
                {manage && (
                  <select className="input" aria-label={t("crmMoveTo")} value={deal.stage} onChange={(e) => move(deal, e.target.value as Stage)}>
                    {STAGES.map((s) => <option key={s} value={s}>{t(STAGE_LABEL[s])}</option>)}
                  </select>
                )}
              </article>
            ))}
          </section>
        ))}
      </div>

      <CloseDealDialog deal={closing?.deal ?? null} stage={closing?.stage ?? "won"} onClose={() => setClosing(null)}
        onDone={(d) => { setClosing(null); toast(fill(t("crmMoved"), { number: d.number, stage: t(STAGE_LABEL[d.stage]) }), undefined, "ok"); load(); }} />
      {creating && <DealDialog onClose={() => setCreating(false)} onSaved={() => { setCreating(false); load(); }} />}
    </div>
  );
}
