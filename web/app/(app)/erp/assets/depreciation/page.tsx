"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp } from "@/lib/erp";
import { currentPeriod, type DepreciationPreview, type DepreciationRun, periodLabel } from "@/lib/finance-api";
import { formatDate, formatDateTime } from "@/lib/format";
import { Banner, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { Amount, AssetTabs } from "@/components/finance-ui";

export default function DepreciationPage() {
  return <ErpGate module="assets" permission="assets.view"><Depreciation /></ErpGate>;
}

function Depreciation() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [page, setPage] = useState(1);
  const [runs, setRuns] = useState<Paginated<DepreciationRun> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [period, setPeriod] = useState(currentPeriod(-1));
  const [preview, setPreview] = useState<DepreciationPreview | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<DepreciationRun | null>(null);
  const [version, setVersion] = useState(0);
  const may = can("assets.depreciate");

  useEffect(() => { api.get<Paginated<DepreciationRun>>("/erp/assets/depreciation", { page }).then(setRuns).catch((e) => setError(e.message)); }, [page, version]);

  const loadPreview = useCallback(() => {
    if (!may) return;
    api.get<{ data: DepreciationPreview }>("/erp/assets/depreciation-preview", { period })
      .then((r) => { setPreview(r.data); setPreviewError(null); })
      .catch((e) => { setPreview(null); setPreviewError(e.message); });
  }, [period, may]);
  useEffect(loadPreview, [loadPreview, version]);

  // A preview answers one month; while another loads, show nothing stale.
  const current = preview && preview.period === period ? preview : null;

  async function run() {
    setBusy(true); setPreviewError(null);
    try {
      const r = await api.post<{ message: string }>("/erp/assets/depreciation", { period });
      toast(r.message, undefined, "ok");
      setConfirm(false); setVersion((v) => v + 1);
    } catch (e) { setPreviewError(e instanceof ApiError ? e.message : String(e)); setConfirm(false); } finally { setBusy(false); }
  }

  async function show(r: DepreciationRun) {
    const d = await api.get<{ data: DepreciationRun }>(`/erp/assets/depreciation/${r.id}`);
    setOpen(d.data);
  }

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabDepreciation")} subtitle={t("finDepreciationSub")} />
      <AssetTabs />

      {may && (
        <GlassCard title={t("finRunDepreciation")} subtitle={t("finRunHint")}>
          <div className="fin-filters">
            <Field label={t("finPeriod")} htmlFor="d-period"><input id="d-period" type="month" className="input" max={currentPeriod(0)} value={period} onChange={(e) => setPeriod(e.target.value)} /></Field>
            <button className="btn btn-primary" disabled={!current || current.already_run || current.lines.length === 0} onClick={() => setConfirm(true)}>
              <Icon name="ph-check-circle" size={17} /> {fill(t("finPostDepreciation"), { amount: amount(current?.total ?? 0) })}
            </button>
          </div>
          {previewError && <Banner tone="danger" icon="ph-warning">{previewError}</Banner>}
          {!current ? (!previewError && <LoadingBlock rows={3} />) : current.already_run ? <Banner tone="accent" icon="ph-check-circle">{t("finAlreadyRun")}</Banner> : current.lines.length === 0 ? <EmptyState icon="ph-check-circle" title={t("finNothingDue")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("finAssetTag")}</th><th>{t("finAssetClass")}</th><th>{t("finPeriod")}</th><th className="num">{t("finOpeningValue")}</th><th className="num">{t("finDepreciation")}</th><th className="num">{t("finClosingValue")}</th></tr></thead>
                <tbody>
                  {current.lines.map((l) => (
                    <tr key={`${l.fixed_asset_id}-${l.period}`}>
                      <td><Link className="erp-cell-link" href={`/erp/assets/register/${l.fixed_asset_id}`}><span className="erp-cell-title">{l.name}</span><span className="erp-cell-sub tnum">{l.tag}</span></Link></td>
                      <td>{l.class}</td><td>{periodLabel(l.period, locale)}</td>
                      <td className="num"><Amount value={l.opening} /></td><td className="num"><Amount value={l.amount} /></td><td className="num"><Amount value={l.closing} /></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot><tr><td colSpan={4}><strong>{t("erpTotal")}</strong></td><td className="num"><Amount value={current.total} strong /></td><td /></tr></tfoot>
              </table>
            </div>
          )}
        </GlassCard>
      )}

      <GlassCard title={t("finPostedRuns")} pad={false}>
        {error ? <ErrorState message={error} /> : !runs ? <LoadingBlock /> : runs.data.length === 0 ? <EmptyState icon="ph-trend-down" title={t("finNoRuns")} /> : (
          <>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpReference")}</th><th>{t("finPeriod")}</th><th className="num">{t("finAssetsCount")}</th><th className="num">{t("finAmount")}</th><th>{t("finJournal")}</th><th>{t("erpPrepared")}</th></tr></thead>
                <tbody>
                  {runs.data.map((r) => (
                    <tr key={r.id} className="is-clickable" onClick={() => show(r)}>
                      <td><button type="button" className="erp-cell-link" onClick={() => show(r)}><span className="erp-cell-title tnum">{r.number}</span></button></td>
                      <td>{periodLabel(r.period, locale)}</td>
                      <td className="num">{r.assets_count}</td>
                      <td className="num">{amount(r.total)}</td>
                      <td className="tnum">{r.journal?.number ?? "-"}</td>
                      <td>{r.creator?.name}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination page={runs.current_page} lastPage={runs.last_page} total={runs.total} onChange={setPage} />
          </>
        )}
      </GlassCard>

      <Dialog open={confirm} onClose={() => setConfirm(false)} busy={busy} icon="ph-trend-down"
        title={fill(t("finPostDepreciation"), { amount: amount(current?.total ?? 0) })} sub={t("finPostDepreciationHint")}
        summary={current ? [{ label: t("finPeriod"), value: periodLabel(current.period, locale) }, { label: t("erpDate"), value: formatDate(current.run_date, locale) }, { label: t("finAssetsCount"), value: current.assets_count }] : undefined}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(false)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-primary" onClick={run} disabled={busy}>{t("erpPost")}</button>
        </>} />

      <Dialog open={!!open} onClose={() => setOpen(null)} wide title={open ? `${open.number} · ${periodLabel(open.period, locale)}` : ""}
        sub={open ? `${open.creator?.name ?? ""} · ${formatDateTime(open.run_date, locale)}` : undefined}>
        {open?.lines && (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("finAssetTag")}</th><th>{t("finPeriod")}</th><th className="num">{t("finDepreciation")}</th><th className="num">{t("finClosingValue")}</th></tr></thead>
              <tbody>
                {open.lines.map((l) => (
                  <tr key={l.id}>
                    <td><Link href={`/erp/assets/register/${l.asset?.id}`}>{l.asset?.name}</Link> <span className="erp-cell-sub tnum">{l.asset?.tag}</span></td>
                    <td>{periodLabel(l.period, locale)}</td>
                    <td className="num">{amount(l.amount)}</td><td className="num">{amount(l.closing_value)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Dialog>
    </div>
  );
}
