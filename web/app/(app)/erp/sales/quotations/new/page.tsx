"use client";

import { ErpGate } from "@/components/erp-ui";
import { SalesDocForm } from "@/components/sales-ui";

export default function NewQuotationPage() {
  return <ErpGate module="sales" permission="sales.quote"><SalesDocForm kind="quotation" /></ErpGate>;
}
