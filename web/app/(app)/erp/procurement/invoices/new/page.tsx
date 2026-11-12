"use client";

import { useQueryValue } from "@/lib/erp";
import { LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { InvoiceForm } from "@/components/procurement-invoice-form";

export default function NewInvoicePage() {
  return <ErpGate module="procurement" permission="procurement.invoice"><NewInvoice /></ErpGate>;
}

function NewInvoice() {
  const order = useQueryValue("order");
  if (order === undefined) return <LoadingBlock rows={5} />;
  return <InvoiceForm orderId={order} />;
}
