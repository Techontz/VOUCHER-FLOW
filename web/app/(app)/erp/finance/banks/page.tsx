"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp, useQueryValue } from "@/lib/erp";
import type { BankAccount } from "@/lib/finance-api";
import { Badge, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, BANK_TYPE_ICON, BANK_TYPE_LABEL, FinanceTabs } from "@/components/finance-ui";
import { BankAccountDialog } from "@/components/finance-bank-form";

export default function BanksPage() {
  return <ErpGate module="accounting" permission="finance.view"><Banks /></ErpGate>;
}

function Banks() {
  const { t } = useApp();
  const { can } = useErp();
  const wantsNew = useQueryValue("new");
  const [rows, setRows] = useState<BankAccount[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState<boolean | null>(null);

  const load = useCallback(() => {
    api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!rows) return <LoadingBlock rows={5} />;

  const active = rows.filter((r) => r.is_active);
  const total = active.reduce((s, r) => s + Number(r.balance ?? 0), 0);

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabBanks")} subtitle={t("finBanksSub")}
        actions={can("finance.bank") && <button className="btn btn-primary" onClick={() => setAdding(true)}><Icon name="ph-plus" size={18} /> {t("finAddBank")}</button>} />
      <FinanceTabs />

      <StatPills items={[
        { label: t("finCashPosition"), value: amount(total), icon: "ph-wallet" },
        { label: t("finTypeBank"), value: amount(active.filter((r) => r.type === "bank").reduce((s, r) => s + Number(r.balance ?? 0), 0)), icon: "ph-bank" },
        { label: t("finTypeMobile"), value: amount(active.filter((r) => r.type === "mobile_money").reduce((s, r) => s + Number(r.balance ?? 0), 0)), icon: "ph-device-mobile" },
        { label: t("finTypeCash"), value: amount(active.filter((r) => r.type === "cash").reduce((s, r) => s + Number(r.balance ?? 0), 0)), icon: "ph-money" },
      ]} />

      {rows.length === 0 ? <EmptyState icon="ph-bank" title={t("finNoBanks")} body={t("finAddBankHint")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("erpName")}</th><th>{t("erpType")}</th><th>{t("finAccountNumber")}</th><th>{t("finLedgerCode")}</th><th className="num">{t("erpBalance")}</th></tr></thead>
            <tbody>
              {rows.map((b) => (
                <tr key={b.id}>
                  <td><Link className="erp-cell-link" href={`/erp/finance/banks/${b.id}`}><span className="erp-cell-title">{b.name}</span><span className="erp-cell-sub">{[b.bank_name, b.branch].filter(Boolean).join(", ")}</span></Link></td>
                  <td><span className="erp-inline-icon"><Icon name={BANK_TYPE_ICON[b.type]} size={16} /> {t(BANK_TYPE_LABEL[b.type])}</span> {!b.is_active && <Badge>{t("erpInactive")}</Badge>}</td>
                  <td className="tnum">{b.account_number ?? "-"}</td>
                  <td className="tnum">{b.account?.code}</td>
                  <td className="num"><Amount value={b.balance} strong /> <span className="erp-muted">{b.currency}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {(adding ?? (!!wantsNew && can("finance.bank"))) && <BankAccountDialog bank={null} onClose={() => setAdding(false)} onSaved={() => { setAdding(false); load(); }} />}
    </div>
  );
}
