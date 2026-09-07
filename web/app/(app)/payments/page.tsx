"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, Note, PageHeader, StatBlock, StatGrid } from "@/components/ui";
import { VoucherCard, VoucherTable } from "@/components/voucher-bits";
import type { Paginated, Voucher } from "@/lib/types";

/**
 * The cashier's payment queue.
 *
 * Everything here has already cleared the approval workflow — the cashier
 * releases the funds and records the reference; no approval decision is made
 * on this screen.
 */
export default function PaymentsPage() {
  const { t, company } = useApp();
  const [due, setDue] = useState<Voucher[] | null>(null);
  const [paid, setPaid] = useState<Voucher[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    Promise.all([
      api.get<Paginated<Voucher>>("/vouchers", { status: "approved", per_page: 50 }),
      api.get<Paginated<Voucher>>("/vouchers", { status: "paid", per_page: 12 }),
    ])
      .then(([queue, settled]) => { setDue(queue.data); setPaid(settled.data); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!due) return <LoadingBlock rows={5} />;

  const cash = due.filter((v) => v.kind === "cash");
  const bank = due.filter((v) => v.kind === "bank");
  const total = (rows: Voucher[]) => rows.reduce((sum, v) => sum + v.amount, 0);

  return (
    <div style={{ maxWidth: 1120 }}>
      <PageHeader
        kicker={t("paymentQueue")}
        title={`${due.length} ${due.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingPayment").toLowerCase()}`}
        sub={t("payNote")}
        actions={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>}
      />

      <div style={{ marginBottom: "var(--space-8)" }}>
        <StatGrid>
          <StatBlock label={t("dueToday")} value={String(due.length)} sub={compactMoney(total(due), company?.currency)} icon="ph-hourglass-medium" />
          <StatBlock label={t("cashOnHand")} value={compactMoney(total(cash), company?.currency)} sub={`${cash.length} ${t("cashVoucher").toLowerCase()}`} icon="ph-money" />
          <StatBlock label={t("bankTransfers")} value={compactMoney(total(bank), company?.currency)} sub={`${bank.length} ${t("bankVoucher").toLowerCase()}`} icon="ph-bank" />
          <StatBlock label={t("paidAct")} value={String(paid.length)} sub={compactMoney(total(paid), company?.currency)} icon="ph-check-circle" />
        </StatGrid>
      </div>

      {due.length > 0 ? (
        <section style={{ marginBottom: "var(--space-8)" }}>
          <div style={{ display: "grid", gap: "var(--space-3)" }}>
            {due.map((voucher) => <VoucherCard key={voucher.id} voucher={voucher} />)}
          </div>
          <div style={{ marginTop: "var(--space-4)", maxWidth: "72ch" }}>
            <Note>{t("approveNextNote")}</Note>
          </div>
        </section>
      ) : (
        <EmptyState icon="ph-check-square-offset" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
          action={<Link className="btn btn-secondary" href="/vouchers">{t("voucherRegister")}</Link>} />
      )}

      {paid.length > 0 && (
        <section>
          <h2 style={{ fontSize: 20, margin: "0 0 var(--space-3)" }}>{t("paymentHistoryH")}</h2>
          <VoucherTable vouchers={paid} />
        </section>
      )}
    </div>
  );
}
