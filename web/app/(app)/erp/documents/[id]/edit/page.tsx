"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { StockDocument } from "@/lib/erp";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { DocumentForm } from "@/components/erp-document-form";

export default function EditDocumentPage() {
  return <ErpGate module="inventory" permission="inventory.view"><EditDocument /></ErpGate>;
}

function EditDocument() {
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<StockDocument | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: StockDocument }>(`/erp/stock-documents/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={5} />;
  if (doc.status !== "draft") return <EmptyState icon="ph-lock-simple" title={`${doc.number} · ${doc.status}`} />;

  return <DocumentForm type={doc.type} existing={doc} />;
}
