"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Invoice } from "@/lib/procurement-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { InvoiceForm } from "@/components/procurement-invoice-form";

export default function EditInvoicePage() {
  return <ErpGate module="procurement" permission="procurement.invoice"><EditInvoice /></ErpGate>;
}

function EditInvoice() {
  const { id } = useParams<{ id: string }>();
  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Invoice }>(`/erp/procurement/invoices/${id}`).then((r) => setInvoice(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!invoice) return <LoadingBlock rows={5} />;
  return <InvoiceForm existing={invoice} />;
}
