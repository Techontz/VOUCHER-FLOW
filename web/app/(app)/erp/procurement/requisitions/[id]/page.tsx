"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { Requisition } from "@/lib/procurement-api";
import { ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { type ActionSpec, ActionDialog, ApprovalTrail, BackLink, Facts, ProcStatus, useMoney } from "@/components/procurement-ui";

export default function RequisitionPage() {
  return <ErpGate module="procurement" permission="procurement.view"><RequisitionDetail /></ErpGate>;
}

function RequisitionDetail() {
  const { t, locale, toast, user } = useApp();
  const { can } = useErp();
  const money = useMoney();
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<Requisition | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionSpec | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Requisition }>(`/erp/procurement/requisitions/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={6} />;

  const base = `/erp/procurement/requisitions/${doc.id}`;
  const mine = doc.requested_by === user?.id || user?.role === "company_admin";
  const actions: ActionSpec[] = [];
  if (doc.status === "draft" && mine && can("procurement.request")) {
    actions.push({ key: "submit", label: t("prcSubmit"), title: fill(t("prcSubmitQ"), { number: doc.number }), sub: t("prcSubmitSub"), icon: "ph-paper-plane-right", path: `${base}/submit` });
  }
  if (doc.status === "submitted" && can("procurement.approve") && !mine) {
    actions.push({ key: "approve", label: t("prcApprove"), title: fill(t("prcApproveQ"), { number: doc.number }), icon: "ph-check-circle", tone: "ok", path: `${base}/approve`, comment: "optional" });
    actions.push({ key: "reject", label: t("prcReject"), title: fill(t("prcRejectQ"), { number: doc.number }), icon: "ph-x-circle", tone: "bad", path: `${base}/reject`, comment: "required", danger: true });
  }
  if (["draft", "submitted", "approved"].includes(doc.status) && mine && can("procurement.request")) {
    actions.push({ key: "cancel", label: t("prcCancelDoc"), title: fill(t("prcCancelQ"), { number: doc.number }), icon: "ph-x-circle", tone: "warn", path: `${base}/cancel`, danger: true });
  }

  return (
    <div className="erp-page">
      <PageHeader
        back={<BackLink href="/erp/procurement/requisitions" label={t("prcRequisitions")} />}
        kicker={t("prcRequisition")}
        title={<span className="tnum">{doc.number}</span>}
        subtitle={<>{doc.department?.name ?? "-"} · {doc.requester?.name} · {formatDate(doc.created_at, locale)}</>}
        actions={<>
          <ProcStatus status={doc.status} />
          {doc.status === "draft" && mine && can("procurement.request") && <Link className="btn btn-secondary" href={`${base}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {doc.status === "approved" && can("procurement.quote") && <Link className="btn btn-secondary" href={`/erp/procurement/rfqs/new?requisition=${doc.id}`}><Icon name="ph-paper-plane-tilt" size={17} /> {t("prcRequestQuotes")}</Link>}
          {doc.status === "approved" && can("procurement.order") && <Link className="btn btn-primary" href={`/erp/procurement/orders/new?requisition=${doc.id}`}><Icon name="ph-shopping-cart" size={17} /> {t("prcRaiseOrder")}</Link>}
          {actions.map((a) => (
            <button key={a.key} className={a.key === "approve" || a.key === "submit" ? "btn btn-primary" : "btn btn-secondary"} onClick={() => setAction(a)}>
              <Icon name={a.icon} size={17} /> {a.label}
            </button>
          ))}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prcItem")}</th><th>{t("prcLineType")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("prcEstimatedPrice")}</th><th className="num">{t("prcAmount")}</th></tr></thead>
              <tbody>
                {doc.lines?.map((l) => (
                  <tr key={l.id}>
                    <td><span className="erp-cell-title">{l.description}</span>{l.product && <span className="erp-cell-sub tnum">{l.product.sku}</span>}{l.expense_account && <span className="erp-cell-sub">{l.expense_account.code} · {l.expense_account.name}</span>}</td>
                    <td>{t(l.line_type === "service" ? "prcServiceLine" : "prcStockLine")}</td>
                    <td className="num">{qty(l.quantity)} <span className="erp-muted">{l.product?.unit?.code}</span></td>
                    <td className="num">{money(l.estimated_unit_price)}</td>
                    <td className="num">{money(l.amount)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot><tr><th colSpan={4}>{t("erpTotal")}</th><th className="num">{money(doc.total)}</th></tr></tfoot>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("erpStatus")}>
          <Facts rows={[
            [t("prcJustification"), doc.justification],
            [t("prcNeededBy"), doc.needed_by ? formatDate(doc.needed_by, locale) : null],
            [t("prcApprovalsRequired"), String(doc.approvals_required)],
            [t("prcSubmittedAt"), doc.submitted_at ? formatDateTime(doc.submitted_at, locale) : null],
            [t("prcApprovedAt"), doc.approved_at ? formatDateTime(doc.approved_at, locale) : null],
            [t("prcOrders"), doc.orders?.length ? <>{doc.orders.map((o) => <Link key={o.id} className="tnum" href={`/erp/procurement/orders/${o.id}`} style={{ marginRight: 8 }}>{o.number}</Link>)}</> : null],
          ]} />
        </GlassCard>

        <GlassCard className="erp-span-3" title={t("prcApprovals")}>
          <ApprovalTrail approvals={doc.approvals} required={doc.approvals_required} />
        </GlassCard>
      </div>

      <ActionDialog action={action} onClose={() => setAction(null)} onDone={(m) => { toast(m, undefined, "ok"); setAction(null); load(); }}
        summary={[{ label: t("prcEstimate"), value: money(doc.total) }, { label: t("prcRequester"), value: doc.requester?.name ?? "-" }]} />
    </div>
  );
}
