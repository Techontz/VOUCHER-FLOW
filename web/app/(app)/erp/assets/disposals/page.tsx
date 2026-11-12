"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated } from "@/lib/erp";
import type { FixedAsset } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, LoadingBlock, PageHeader, Pagination, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, AssetTabs } from "@/components/finance-ui";

export default function DisposalsPage() {
  return <ErpGate module="assets" permission="assets.view"><Disposals /></ErpGate>;
}

function Disposals() {
  const { t, locale } = useApp();
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<FixedAsset> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { api.get<Paginated<FixedAsset>>("/erp/assets/register", { status: "disposed", page }).then(setRows).catch((e) => setError(e.message)); }, [page]);

  const proceeds = rows?.data.reduce((s, a) => s + Number(a.disposal_proceeds ?? 0), 0) ?? 0;
  const result = rows?.data.reduce((s, a) => s + Number(a.disposal_gain_loss ?? 0), 0) ?? 0;

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabDisposals")} subtitle={t("finDisposalsSub")} />
      <AssetTabs />
      {rows && rows.data.length > 0 && <StatPills items={[
        { label: t("finProceeds"), value: amount(proceeds), icon: "ph-coins", hint: t("finThisPage") },
        { label: t("finGainLoss"), value: amount(result), icon: "ph-scales", tone: result < 0 ? "bad" : "ok", hint: t("finThisPage") },
      ]} />}
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-recycle" title={t("finNoDisposals")} body={t("finDisposalsSub")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("finAssetTag")}</th><th>{t("finDisposedOn")}</th><th className="num">{t("finCost")}</th><th className="num">{t("finAccumulated")}</th><th className="num">{t("finProceeds")}</th><th className="num">{t("finGainLoss")}</th><th>{t("erpReason")}</th></tr></thead>
              <tbody>
                {rows.data.map((a) => (
                  <tr key={a.id}>
                    <td><Link className="erp-cell-link" href={`/erp/assets/register/${a.id}`}><span className="erp-cell-title">{a.name}</span><span className="erp-cell-sub tnum">{a.tag}</span></Link></td>
                    <td className="tnum">{formatDate(a.disposal_date, locale)}</td>
                    <td className="num">{amount(a.cost)}</td><td className="num">{amount(a.accumulated_depreciation)}</td>
                    <td className="num">{amount(a.disposal_proceeds)}</td><td className="num"><Amount value={a.disposal_gain_loss} /></td>
                    <td>{a.disposal_reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}
