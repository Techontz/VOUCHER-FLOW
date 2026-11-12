"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { type Receipt, usePaged } from "@/lib/sales-api";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { type Act, ActionDialog } from "@/components/sales-ui";
import { ReceiptRows } from "@/components/sales-receipts";

export default function ReceiptsPage() {
  return <ErpGate module="sales" permission="sales.view"><Receipts /></ErpGate>;
}

function Receipts() {
  const { t } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [act, setAct] = useState<Act | null>(null);
  const { rows, error, setPage, reload } = usePaged<Receipt>("/erp/sales/receipts", { status: status || undefined }, q);

  return (
    <div className="erp-page">
      <PageHeader title={t("salReceipts")} subtitle={t("salReceiptsSub")}
        actions={can("sales.receipt") && <Link className="btn btn-primary" href="/erp/sales/receipts/new"><Icon name="ph-plus" size={18} /> {t("salRecordReceipt")}</Link>} />
      <Toolbar>
        <SearchInput value={q} onChange={setQ} placeholder={t("salSearchDocs")} />
        <FilterChips value={status} onChange={setStatus} items={[
          { value: "", label: t("erpAll") }, { value: "recorded", label: t("salStRecorded") },
          { value: "verified", label: t("salStVerified") }, { value: "rejected", label: t("salStRejected") },
        ]} />
      </Toolbar>
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-hand-coins" title={t("salNoReceipts")} /> : (
        <>
          <ReceiptRows rows={rows.data} onAct={setAct} />
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
      <ActionDialog act={act} onClose={() => setAct(null)} onDone={reload} />
    </div>
  );
}
