"use client";

import { useApp } from "@/lib/app-context";

/* Option lists HR forms share, in the reader's language. */

export const CONTRACT_TYPES = ["permanent", "fixed_term", "probation", "casual"] as const;
export const CONTRACT_KEY = { permanent: "hrTypePermanent", fixed_term: "hrTypeFixedTerm", probation: "hrTypeProbation", casual: "hrTypeCasual" } as const;

export function useEmploymentTypes() {
  const { t } = useApp();
  return [
    { value: "permanent", label: t("hrTypePermanent") },
    { value: "fixed_term", label: t("hrTypeFixedTerm") },
    { value: "casual", label: t("hrTypeCasual") },
    { value: "intern", label: t("hrTypeIntern") },
  ];
}

export const MOVEMENT_TYPES = ["transfer", "promotion", "demotion", "redesignation"] as const;
export const MOVEMENT_KEY = { transfer: "hrMoveTransfer", promotion: "hrMovePromotion", demotion: "hrMoveDemotion", redesignation: "hrMoveRedesignation" } as const;
