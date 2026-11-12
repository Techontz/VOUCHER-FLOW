"use client";

import { useQueryValue } from "@/lib/erp";
import { LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { BomForm } from "@/components/production-bom-form";

export default function NewBomPage() {
  return <ErpGate module="production" permission="production.manage"><NewBom /></ErpGate>;
}

function NewBom() {
  const product = useQueryValue("product");
  if (product === undefined) return <LoadingBlock rows={5} />;
  return <BomForm presetProduct={product} />;
}
