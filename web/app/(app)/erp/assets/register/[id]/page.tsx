"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { amount, useErp } from "@/lib/erp";
import { type AssetLookups, type BankAccount, type FixedAssetDetail, periodLabel, today } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, AssetStatusBadge, AssetTabs, DetailRows } from "@/components/finance-ui";
import { AssetDialog, METHOD_LABEL } from "@/components/finance-asset-form";

export default function AssetPage() {
  return <ErpGate module="assets" permission="assets.view"><Asset /></ErpGate>;
}

const EVENT_LABEL: Record<string, MessageKey> = {
  registered: "finEventRegistered", capitalised: "finEventCapitalised", transferred: "finEventTransferred", disposed: "finEventDisposed",
};

const FUNDING_LABEL: Record<string, MessageKey> = { payable: "finFundingPayable", bank: "finFundingBank", opening_equity: "finFundingOpening" };

type Action = "capitalise" | "transfer" | "dispose" | "delete";

function Asset() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [asset, setAsset] = useState<FixedAssetDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [action, setAction] = useState<Action | null>(null);
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [lookups, setLookups] = useState<AssetLookups>({ users: [], suppliers: [], locations: [] });
  const [form, setForm] = useState({ funding: "bank", bank_account_id: "", location: "", custodian_user_id: "", date: today(), notes: "", disposal_date: today(), proceeds: "", reason: "" });
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: FixedAssetDetail }>(`/erp/assets/register/${id}`).then((r) => setAsset(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  function open(a: Action) {
    setActionError(null); setAction(a);
    if (asset) setForm((f) => ({ ...f, location: asset.location ?? "", custodian_user_id: String(asset.custodian_user_id ?? "") }));
    if ((a === "capitalise" || a === "dispose") && !banks.length) api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts", { active: 1 }).then((r) => setBanks(r.data)).catch(() => setBanks([]));
    if (a === "transfer" && !lookups.users.length) api.get<{ data: AssetLookups }>("/erp/assets/lookups").then((r) => setLookups(r.data)).catch(() => undefined);
  }

  async function act() {
    if (!asset || !action) return;
    setBusy(true); setActionError(null);
    try {
      const base = `/erp/assets/register/${asset.id}`;
      if (action === "delete") {
        await api.delete(base);
        router.push("/erp/assets/register");
        return;
      }
      const body = action === "capitalise"
        ? { funding: form.funding, bank_account_id: form.funding === "bank" ? Number(form.bank_account_id) || null : null }
        : action === "transfer"
          ? { location: form.location || null, custodian_user_id: form.custodian_user_id ? Number(form.custodian_user_id) : null, date: form.date, notes: form.notes || null }
          : { disposal_date: form.disposal_date, proceeds: form.proceeds || 0, bank_account_id: Number(form.proceeds) > 0 ? Number(form.bank_account_id) || null : null, reason: form.reason };
      const r = await api.post<{ message: string }>(`${base}/${action}`, body);
      toast(r.message, undefined, "ok");
      setAction(null); load();
    } catch (e) { setActionError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!asset) return <LoadingBlock rows={6} />;

  const manage = can("assets.manage");
  const gain = Number(form.proceeds || 0) - asset.book_value;
  const posted = asset.schedule.filter((r) => r.posted).length;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/assets/register" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("finTabRegister")}</Link>}
        kicker={`${asset.tag} · ${asset.asset_class?.name ?? ""}`}
        title={asset.name}
        subtitle={[asset.location, asset.custodian?.name, asset.serial_number].filter(Boolean).join(" · ")}
        actions={<>
          <AssetStatusBadge status={asset.status} />
          {manage && asset.status !== "disposed" && <button className="btn btn-secondary" onClick={() => setEditing(true)}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {manage && asset.status === "draft" && <button className="btn btn-secondary" onClick={() => open("delete")}><Icon name="ph-trash" size={17} /> {t("erpDelete")}</button>}
          {manage && asset.status !== "disposed" && <button className="btn btn-secondary" onClick={() => open("transfer")}><Icon name="ph-arrows-left-right" size={17} /> {t("finTransferAsset")}</button>}
          {can("assets.dispose") && asset.status === "active" && <button className="btn btn-secondary" onClick={() => open("dispose")}><Icon name="ph-recycle" size={17} /> {t("finDispose")}</button>}
          {manage && asset.status === "draft" && <button className="btn btn-primary" onClick={() => open("capitalise")}><Icon name="ph-check-circle" size={18} /> {t("finCapitalise")}</button>}
        </>}
      />
      <AssetTabs />

      <StatPills items={[
        { label: t("finCost"), value: amount(asset.cost), icon: "ph-coins" },
        { label: t("finAccumulated"), value: amount(asset.accumulated_depreciation), icon: "ph-trend-down", hint: `${posted} / ${asset.schedule.length}` },
        { label: t("finBookValue"), value: amount(asset.book_value), icon: "ph-scales" },
        ...(asset.status === "disposed"
          ? [{ label: t("finGainLoss"), value: amount(asset.disposal_gain_loss), icon: "ph-recycle", tone: (Number(asset.disposal_gain_loss) < 0 ? "bad" : "ok") as "bad" | "ok" }]
          : [{ label: t("finResidual"), value: amount(asset.residual_value), icon: "ph-flag-checkered" }]),
      ]} />

      <div className="erp-grid">
        <GlassCard title={t("finDetails")} pad={false}>
          <DetailRows rows={[
            { label: t("finAcquired"), value: formatDate(asset.acquisition_date, locale) },
            { label: t("finMethod"), value: `${t(METHOD_LABEL[asset.method])}${asset.method === "reducing_balance" ? `, ${Number(asset.rate)}%` : ""}` },
            { label: t("finLifeMonths"), value: asset.useful_life_months },
            { label: t("erpSuppliers"), value: asset.supplier?.name ?? "-" },
            { label: t("finFunding"), value: asset.funding ? `${t(FUNDING_LABEL[asset.funding] ?? "finNone")}${asset.funding_bank_account ? `: ${asset.funding_bank_account.name}` : ""}` : "-" },
            { label: t("finAccounts"), value: <span className="tnum">{asset.asset_class?.asset_account?.code} / {asset.asset_class?.depreciation_account?.code} / {asset.asset_class?.expense_account?.code}</span> },
            ...(asset.status === "disposed" ? [
              { label: t("finDisposedOn"), value: formatDate(asset.disposal_date, locale) },
              { label: t("finProceeds"), value: `${amount(asset.disposal_proceeds)}${asset.disposal_bank_account ? `, ${asset.disposal_bank_account.name}` : ""}` },
              { label: t("erpReason"), value: asset.disposal_reason ?? "-" },
            ] : []),
          ]} />
        </GlassCard>

        <GlassCard title={t("finHistory")} pad={false}>
          <ul className="erp-list">
            {asset.events.map((e) => (
              <li key={e.id} className="erp-list-row">
                <span className="erp-list-main">
                  <span className="erp-list-title">{t(EVENT_LABEL[e.type] ?? "finEventRegistered")} · {formatDate(e.event_date, locale)}</span>
                  <span className="erp-list-sub">
                    {e.type === "transferred" ? `${e.from_location ?? "-"} → ${e.to_location ?? "-"}${e.to_custodian ? `, ${e.to_custodian.name}` : ""}` : e.amount ? amount(e.amount) : ""}
                    {e.notes ? ` · ${e.notes}` : ""}{e.user ? ` · ${e.user.name}` : ""}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("finSchedule")} subtitle={t("finScheduleHint")} pad={false}>
          {asset.schedule.length === 0 ? <EmptyState icon="ph-calendar" title={t("finNoSchedule")} /> : (
            <div className="vf-table-wrap" style={{ maxHeight: 480, overflowY: "auto" }}>
              <table className="table vf-table">
                <thead><tr><th>{t("finPeriod")}</th><th className="num">{t("finOpeningValue")}</th><th className="num">{t("finDepreciation")}</th><th className="num">{t("finClosingValue")}</th><th>{t("erpStatus")}</th></tr></thead>
                <tbody>
                  {asset.schedule.map((r) => (
                    <tr key={r.period}>
                      <td>{periodLabel(r.period, locale)}</td>
                      <td className="num"><Amount value={r.opening} /></td>
                      <td className="num"><Amount value={r.amount} /></td>
                      <td className="num"><Amount value={r.closing} /></td>
                      <td>{r.posted ? <Badge tone="ok">{t("erpStatusPosted")}</Badge> : <Badge>{t("finScheduled")}</Badge>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      </div>

      {editing && <AssetDialog asset={asset} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load(); }} />}

      <Dialog open={!!action} onClose={() => setAction(null)} busy={busy} wide={action === "dispose"}
        tone={action === "dispose" || action === "delete" ? "warn" : "info"}
        icon={action === "capitalise" ? "ph-check-circle" : action === "transfer" ? "ph-arrows-left-right" : action === "dispose" ? "ph-recycle" : "ph-trash"}
        title={t(action === "capitalise" ? "finCapitalise" : action === "transfer" ? "finTransferAsset" : action === "dispose" ? "finDispose" : "finDeleteAssetQ")}
        sub={action === "capitalise" ? t("finCapitaliseHint") : action === "dispose" ? t("finDisposeHint") : undefined}
        summary={[{ label: t("finAssetTag"), value: asset.tag }, { label: t("finCost"), value: amount(asset.cost) }, { label: t("finBookValue"), value: amount(asset.book_value) }]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setAction(null)} disabled={busy}>{t("erpBack")}</button>
          <button className={action === "dispose" || action === "delete" ? "btn btn-danger" : "btn btn-primary"} onClick={act}
            disabled={busy || (action === "dispose" && form.reason.trim().length < 3) || (action === "capitalise" && form.funding === "bank" && !form.bank_account_id)}>
            {t(action === "delete" ? "erpDelete" : "finConfirm")}
          </button>
        </>}>
        {actionError && !Object.keys(actionError.errors).length && <div className="field-error" role="alert">{actionError.message}</div>}
        {action === "capitalise" && <div className="erp-form-grid">
          <Field label={t("finFunding")} htmlFor="ac-fund" error={actionError?.field("funding")}>
            <select id="ac-fund" className="input" value={form.funding} onChange={(e) => setForm({ ...form, funding: e.target.value })}>
              <option value="bank">{t("finFundingBank")}</option>
              <option value="payable">{t("finFundingPayable")}</option>
              <option value="opening_equity">{t("finFundingOpening")}</option>
            </select>
          </Field>
          {form.funding === "bank" && <Field label={t("finBankAccount")} htmlFor="ac-bank" required error={actionError?.field("bank_account_id")}>
            <select id="ac-bank" className="input" value={form.bank_account_id} onChange={(e) => setForm({ ...form, bank_account_id: e.target.value })}>
              <option value="">{t("finChoose")}</option>
              {banks.map((b) => <option key={b.id} value={b.id}>{b.name} ({amount(b.balance)})</option>)}
            </select>
          </Field>}
        </div>}
        {action === "transfer" && <div className="erp-form-grid">
          <Field label={t("finLocation")} htmlFor="at-loc" error={actionError?.field("location")}>
            <input id="at-loc" className="input" list="at-locations" value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} />
            <datalist id="at-locations">{lookups.locations.map((l) => <option key={l} value={l} />)}</datalist>
          </Field>
          <Field label={t("finCustodian")} htmlFor="at-cust" error={actionError?.field("custodian_user_id")}>
            <select id="at-cust" className="input" value={form.custodian_user_id} onChange={(e) => setForm({ ...form, custodian_user_id: e.target.value })}>
              <option value="">{t("finNone")}</option>
              {lookups.users.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
            </select>
          </Field>
          <Field label={t("erpDate")} htmlFor="at-date" error={actionError?.field("date")}>
            <input id="at-date" type="date" className="input" max={today()} value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} />
          </Field>
          <Field label={t("finNotes")} htmlFor="at-notes" error={actionError?.field("notes")}>
            <input id="at-notes" className="input" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
          </Field>
        </div>}
        {action === "dispose" && <>
          <div className="erp-form-grid">
            <Field label={t("finDisposedOn")} htmlFor="ad-date" required error={actionError?.field("disposal_date")}>
              <input id="ad-date" type="date" className="input" max={today()} value={form.disposal_date} onChange={(e) => setForm({ ...form, disposal_date: e.target.value })} />
            </Field>
            <Field label={t("finProceeds")} htmlFor="ad-proc" hint={t("finProceedsHint")} error={actionError?.field("proceeds")}>
              <input id="ad-proc" className="input tnum" inputMode="decimal" value={form.proceeds} onChange={(e) => setForm({ ...form, proceeds: e.target.value })} />
            </Field>
            {Number(form.proceeds) > 0 && <Field label={t("finIntoAccount")} htmlFor="ad-bank" required error={actionError?.field("bank_account_id")}>
              <select id="ad-bank" className="input" value={form.bank_account_id} onChange={(e) => setForm({ ...form, bank_account_id: e.target.value })}>
                <option value="">{t("finChoose")}</option>
                {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </Field>}
            <Field label={t("erpReason")} htmlFor="ad-reason" required error={actionError?.field("reason")}>
              <input id="ad-reason" className="input" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
            </Field>
          </div>
          <p><Badge tone={gain < 0 ? "bad" : "ok"}>{t(gain < 0 ? "finLoss" : "finGain")}: {amount(Math.abs(gain))}</Badge></p>
        </>}
      </Dialog>
    </div>
  );
}
