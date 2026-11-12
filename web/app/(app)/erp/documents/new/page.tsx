"use client";

import { DOCUMENT_TYPES, type DocumentType, PREPARE_PERMISSION, useErp, useQueryValue } from "@/lib/erp";
import { useApp } from "@/lib/app-context";
import { EmptyState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { DocumentForm } from "@/components/erp-document-form";

export default function NewDocumentPage() {
  return <ErpGate module="inventory" permission="inventory.view"><NewDocument /></ErpGate>;
}

function NewDocument() {
  const { t } = useApp();
  const { can } = useErp();
  const requested = useQueryValue("type");

  if (requested === undefined) return <LoadingBlock rows={4} />;
  const type = (DOCUMENT_TYPES as string[]).includes(requested ?? "") ? (requested as DocumentType) : "grn";
  if (!can(PREPARE_PERMISSION[type])) return <EmptyState icon="ph-lock-simple" title={t("erpNoAccess")} />;

  return <DocumentForm key={type} type={type} />;
}
