"use client";

import { ErpGate } from "@/components/erp-ui";
import { RequisitionForm } from "@/components/procurement-requisition-form";

export default function NewRequisitionPage() {
  return <ErpGate module="procurement" permission="procurement.request"><RequisitionForm /></ErpGate>;
}
