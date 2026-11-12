"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp, useQueryValue } from "@/lib/erp";
import type { AssetClass, AssetStatus, FixedAsset } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { AssetStatusBadge, AssetTabs } from "@/components/finance-ui";
import { AssetDialog } from "@/components/finance-asset-form";

export default function RegisterPage() {
  return <ErpGate module="assets" permission="assets.view"><Register /></ErpGate>;
}

function Register() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const wantsNew = useQueryValue("new");
  const [status, setStatus] = useState<AssetStatus | "">("active");
  const [klass, setKlass] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<FixedAsset> | null>(null);
  const [classes, setClasses] = useState<AssetClass[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState<boolean | null>(null);

  useEffect(() => { api.get<{ data: AssetClass[] }>("/erp/assets/classes").then((r) => setClasses(r.data)).catch(() => setClasses([])); }, []);
  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<FixedAsset>>("/erp/assets/register", { status: status || undefined, asset_class_id: klass || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [status, klass, q, page]);

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabRegister")} subtitle={t("finRegisterSub")}
        actions={can("assets.manage") && <button className="btn btn-primary" onClick={() => setAdding(true)}><Icon name="ph-plus" size={18} /> {t("finRegisterAsset")}</button>} />
      <AssetTabs />

      <Toolbar end={
        <select className="input" aria-label={t("finAssetClass")} value={klass} onChange={(e) => { setKlass(e.target.value); setPage(1); }} style={{ maxWidth: 220 }}>
          <option value="">{t("finAllClasses")}</option>
          {classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      }>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("finAssetTag")}`} />
        <FilterChips<AssetStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("finAssetDraft") }, { value: "active", label: t("finAssetActive") }, { value: "disposed", label: t("finAssetDisposed") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-cube" title={t("finNoAssets")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("finAssetTag")}</th><th>{t("finAssetClass")}</th><th>{t("finLocation")}</th><th>{t("finAcquired")}</th><th className="num">{t("finCost")}</th><th className="num">{t("finBookValue")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((a) => (
                  <tr key={a.id} className="is-clickable" onClick={() => router.push(`/erp/assets/register/${a.id}`)}>
                    <td><Link className="erp-cell-link" href={`/erp/assets/register/${a.id}`}><span className="erp-cell-title">{a.name}</span><span className="erp-cell-sub tnum">{a.tag}</span></Link></td>
                    <td>{a.asset_class?.name}</td>
                    <td>{a.location ?? "-"}{a.custodian && <span className="erp-cell-sub">{a.custodian.name}</span>}</td>
                    <td className="tnum">{formatDate(a.acquisition_date, locale)}</td>
                    <td className="num">{amount(a.cost)}</td>
                    <td className="num">{a.status === "disposed" ? "-" : amount(Number(a.cost) - Number(a.accumulated_depreciation))}</td>
                    <td><AssetStatusBadge status={a.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {(adding ?? (!!wantsNew && can("assets.manage"))) && <AssetDialog asset={null} onClose={() => setAdding(false)} onSaved={(a) => router.push(`/erp/assets/register/${a.id}`)} />}
    </div>
  );
}
