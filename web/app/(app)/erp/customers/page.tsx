"use client";

import { ErpGate } from "@/components/erp-ui";
import { PartyRegister } from "@/components/erp-parties";

export default function CustomersPage() {
  return <ErpGate module="sales" permission="customers.view"><PartyRegister kind="customers" /></ErpGate>;
}
