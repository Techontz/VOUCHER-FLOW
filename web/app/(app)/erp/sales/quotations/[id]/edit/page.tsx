"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Quotation } from "@/lib/sales-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { SalesDocForm } from "@/components/sales-ui";

export default function EditQuotationPage() {
  return <ErpGate module="sales" permission="sales.quote"><EditQuotation /></ErpGate>;
}

function EditQuotation() {
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<Quotation | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.get<{ data: Quotation }>(`/erp/sales/quotations/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message)); }, [id]);
  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={5} />;
  return <SalesDocForm kind="quotation" existing={doc} />;
}
