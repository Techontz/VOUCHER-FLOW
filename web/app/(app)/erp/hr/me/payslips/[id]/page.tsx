"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { HrGate, PayslipPage } from "@/components/hr-ui";

export default function MyPayslipRoute() {
  return <HrGate anyOf={["hr.self"]}><Slip /></HrGate>;
}

function Slip() {
  const { t } = useApp();
  const { id } = useParams<{ id: string }>();
  return <PayslipPage endpoint={`/erp/hr/me/payslips/${id}`} back={<Link href="/erp/hr/me" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("hrMyHr")}</Link>} />;
}
