"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { HrGate, PayslipPage } from "@/components/hr-ui";

export default function PayslipRoute() {
  return <HrGate anyOf={["hr.payroll.prepare", "hr.payroll.authorise", "hr.payroll.post"]}><Slip /></HrGate>;
}

function Slip() {
  const { t } = useApp();
  const { id } = useParams<{ id: string }>();
  return <PayslipPage endpoint={`/erp/hr/payslips/${id}`} back={<Link href="/erp/hr/payroll" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("hrPayroll")}</Link>} />;
}
