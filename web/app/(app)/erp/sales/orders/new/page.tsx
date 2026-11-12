"use client";

import { ErpGate } from "@/components/erp-ui";
import { SalesDocForm } from "@/components/sales-ui";

export default function NewOrderPage() {
  return <ErpGate module="sales" permission="sales.order"><SalesDocForm kind="order" /></ErpGate>;
}
