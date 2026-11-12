"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type Opportunity, type Stage, STAGE_LABEL, STAGES } from "@/lib/crm-types";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { CrmTabs, StageBadge, useMoney } from "@/components/crm-ui";
import { DealDialog } from "@/components/crm-deal-form";

export default function OpportunitiesPage() {
  return <ErpGate module="crm" permission="crm.view"><Opportunities /></ErpGate>;
}

function Opportunities() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const money = useMoney();
  const [stage, setStage] = useState<Stage | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Opportunity> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    api.get<Paginated<Opportunity>>("/erp/crm/opportunities", { stage: stage || undefined, q: q || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [stage, q, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  return (
    <div className="erp-page">
      <PageHeader title={t("crmNavOpportunities")} subtitle={t("crmOpportunitiesSub")}
        actions={can("crm.manage") && <button className="btn btn-primary" onClick={() => setCreating(true)}><Icon name="ph-plus" size={18} /> {t("crmNewOpportunity")}</button>} />
      <CrmTabs />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("crmTitleField")}, ${t("crmCustomer")}`} />
        <FilterChips<Stage | ""> value={stage} onChange={(v) => { setStage(v); setPage(1); }} items={[
          { value: "", label: t("crmAllStages") }, ...STAGES.map((s) => ({ value: s, label: t(STAGE_LABEL[s]) })),
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-target" title={t("crmNoOpportunities")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("crmTitleField")}</th><th>{t("crmCustomer")}</th><th className="num">{t("crmValue")}</th><th className="num">%</th><th>{t("crmCloseDate")}</th><th>{t("crmOwner")}</th><th>{t("crmStage")}</th></tr></thead>
              <tbody>
                {rows.data.map((o) => (
                  <tr key={o.id} className="is-clickable" onClick={() => router.push(`/erp/crm/opportunities/${o.id}`)}>
                    <td><Link href={`/erp/crm/opportunities/${o.id}`} className="erp-cell-link" onClick={(e) => e.stopPropagation()}>
                      <span className="erp-cell-title">{o.title}</span><span className="erp-cell-sub tnum">{o.number}</span>
                    </Link></td>
                    <td>{o.customer?.name ?? "-"}</td>
                    <td className="num">{money(o.value)}</td>
                    <td className="num">{o.probability}</td>
                    <td className="tnum">{o.expected_close_date ? formatDate(o.expected_close_date, locale) : "-"}</td>
                    <td>{o.owner?.name ?? "-"}</td>
                    <td><StageBadge stage={o.stage} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {creating && <DealDialog onClose={() => setCreating(false)} onSaved={(d) => router.push(`/erp/crm/opportunities/${d.id}`)} />}
    </div>
  );
}
