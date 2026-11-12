"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Requisition } from "@/lib/procurement-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { RequisitionForm } from "@/components/procurement-requisition-form";

export default function EditRequisitionPage() {
  return <ErpGate module="procurement" permission="procurement.request"><EditRequisition /></ErpGate>;
}

function EditRequisition() {
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<Requisition | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Requisition }>(`/erp/procurement/requisitions/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={5} />;
  return <RequisitionForm existing={doc} />;
}
