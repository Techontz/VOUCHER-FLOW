import type { MessageKey } from "./i18n";

/*
 * Shapes the /api/erp/crm and /api/erp/files endpoints return, and the label
 * keys for their fixed vocabularies.
 */

export type LeadStatus = "new" | "contacted" | "qualified" | "lost" | "converted";
export type Stage = "prospecting" | "proposal" | "negotiation" | "won" | "lost";
export type ActivityType = "call" | "meeting" | "visit" | "task";

export interface Person { id: number; name: string; role?: string }

export interface Lead {
  id: number; number: string; contact_name: string; company_name: string | null;
  phone: string | null; email: string | null; region: string | null; source: string; status: LeadStatus;
  estimated_value: string; notes: string | null; lost_reason: string | null;
  owner_id: number | null; owner?: Person | null;
  customer_id: number | null; customer?: { id: number; code: string; name: string } | null;
  opportunity_id: number | null; opportunity?: { id: number; number: string; title: string; stage: Stage; value: string } | null;
  converted_at: string | null; created_at: string;
  activities?: Activity[];
}

export interface Opportunity {
  id: number; number: string; title: string; stage: Stage; value: string; probability: number;
  expected_close_date: string | null; owner_id: number | null; owner?: Person | null;
  customer_id: number | null; customer?: { id: number; code: string; name: string; phone?: string | null; email?: string | null } | null;
  lead_id: number | null; lead?: { id: number; number: string; contact_name: string } | null;
  close_reason: string | null; close_note: string | null; closed_at: string | null; stage_changed_at: string | null;
  notes: string | null; created_at: string;
  activities?: Activity[];
  history?: { id: number; action: string; actor_name: string; description: string; change_summary: string | null; created_at: string }[];
}

export interface Activity {
  id: number; type: ActivityType; subject: string; notes: string | null; due_at: string | null;
  completed_at: string | null; outcome: string | null;
  owner_id: number | null; owner?: Person | null;
  lead_id: number | null; lead?: { id: number; number: string; contact_name: string } | null;
  opportunity_id: number | null; opportunity?: { id: number; number: string; title: string } | null;
  customer_id: number | null; customer?: { id: number; code: string; name: string } | null;
}

export interface StageTotal { stage: Stage; count: number; value: number; weighted: number }

export interface CrmOverview {
  stages: StageTotal[]; open_value: number; weighted_value: number;
  won_this_month: { count: number; value: number }; lost_this_month: { count: number; value: number };
  leads: Record<LeadStatus, number>;
  due_today: Activity[]; overdue: Activity[]; overdue_count: number; due_today_count: number;
}

export interface BoardColumn extends StageTotal { items: Opportunity[] }

export interface Bucket { count: number; value: number; weighted: number }
export interface Forecast { months: (Bucket & { month: string; won: number })[]; past_due: Bucket; later: Bucket; undated: Bucket; total: Bucket }
export interface WinLoss {
  won: { reason: string; count: number; value: number }[]; lost: { reason: string; count: number; value: number }[];
  win_rate: number | null; reasons: { won: string[]; lost: string[] };
}

export const STAGES: Stage[] = ["prospecting", "proposal", "negotiation", "won", "lost"];
export const OPEN_STAGES: Stage[] = ["prospecting", "proposal", "negotiation"];
export const LEAD_STATUSES: LeadStatus[] = ["new", "contacted", "qualified", "lost"];
export const SOURCES = ["referral", "walk_in", "phone", "website", "social_media", "trade_show", "field_visit", "other"] as const;
export const ACTIVITY_TYPES: ActivityType[] = ["call", "meeting", "visit", "task"];
export const WIN_REASONS = ["price", "quality", "relationship", "delivery", "credit_terms", "other"] as const;
export const LOSS_REASONS = ["price", "competitor", "no_budget", "no_decision", "timing", "stock", "other"] as const;

export const STAGE_LABEL: Record<Stage, MessageKey> = {
  prospecting: "crmStageProspecting", proposal: "crmStageProposal", negotiation: "crmStageNegotiation", won: "crmStageWon", lost: "crmStageLost",
};
export const LEAD_STATUS_LABEL: Record<LeadStatus, MessageKey> = {
  new: "crmLeadNew", contacted: "crmLeadContacted", qualified: "crmLeadQualified", lost: "crmLeadLost", converted: "crmLeadConverted",
};
export const SOURCE_LABEL: Record<string, MessageKey> = {
  referral: "crmSrcReferral", walk_in: "crmSrcWalkIn", phone: "crmSrcPhone", website: "crmSrcWebsite",
  social_media: "crmSrcSocial", trade_show: "crmSrcTradeShow", field_visit: "crmSrcFieldVisit", other: "crmSrcOther",
};
export const ACTIVITY_LABEL: Record<ActivityType, MessageKey> = {
  call: "crmActCall", meeting: "crmActMeeting", visit: "crmActVisit", task: "crmActTask",
};
export const ACTIVITY_ICON: Record<ActivityType, string> = {
  call: "ph-phone", meeting: "ph-users-three", visit: "ph-map-pin", task: "ph-check-square",
};
export const REASON_LABEL: Record<string, MessageKey> = {
  price: "crmReasonPrice", quality: "crmReasonQuality", relationship: "crmReasonRelationship", delivery: "crmReasonDelivery",
  credit_terms: "crmReasonCreditTerms", competitor: "crmReasonCompetitor", no_budget: "crmReasonNoBudget",
  no_decision: "crmReasonNoDecision", timing: "crmReasonTiming", stock: "crmReasonStock", other: "crmReasonOther",
  unspecified: "crmReasonUnspecified",
};

export function stageTone(stage: Stage): "neutral" | "info" | "ok" | "warn" | "bad" {
  return stage === "won" ? "ok" : stage === "lost" ? "bad" : stage === "negotiation" ? "warn" : stage === "proposal" ? "info" : "neutral";
}
export function leadTone(status: LeadStatus): "neutral" | "info" | "ok" | "warn" | "bad" {
  return status === "converted" ? "ok" : status === "lost" ? "bad" : status === "qualified" ? "info" : status === "contacted" ? "warn" : "neutral";
}

/* ── documents ──────────────────────────────────────────────────────── */

export type AccessScope = "inherit" | "company" | "roles" | "users";

export interface DocVersion {
  id: number; version: number; original_name: string; mime_type: string | null; size_bytes: number;
  note: string | null; created_at: string; uploader?: Person | null;
}

export interface DocLink { id: number; attachable_type: string; attachable_id: number }

export interface FolderRow {
  id: number; parent_id: number | null; name: string; description?: string | null; access_scope: Exclude<AccessScope, "inherit">;
  access_roles?: string[] | null; access_users?: number[] | null; retention_years: number | null; documents_count?: number;
}

export interface DocumentRow {
  id: number; title: string; folder_id: number | null; folder?: FolderRow | null; document_type: string; tags: string[] | null;
  description: string | null; reference: string | null; issued_on: string | null; expires_on: string | null;
  access_scope: AccessScope; access_roles: string[] | null; access_users: number[] | null;
  retention_years: number | null; retain_until: string | null; current_version: number;
  owner?: Person | null; creator?: Person | null; created_by: number | null; created_at: string; deleted_at?: string | null;
  latest_version?: DocVersion | null; versions?: DocVersion[]; links?: DocLink[]; days_left?: number;
}

export interface DocumentDetail extends DocumentRow {
  breadcrumbs: { id: number; name: string }[];
  retained: boolean;
  access_log: { id: number; action: string; version: number | null; created_at: string; user?: Person | null }[];
  can: { upload: boolean; manage: boolean; delete: boolean };
}

export const DOC_TYPES = [
  "general", "contract", "licence", "permit", "certificate", "insurance", "policy",
  "invoice", "receipt", "report", "id_document", "vehicle", "hr", "other",
] as const;

export const DOC_TYPE_LABEL: Record<string, MessageKey> = {
  general: "docTypeGeneral", contract: "docTypeContract", licence: "docTypeLicence", permit: "docTypePermit",
  certificate: "docTypeCertificate", insurance: "docTypeInsurance", policy: "docTypePolicy", invoice: "docTypeInvoice",
  receipt: "docTypeReceipt", report: "docTypeReport", id_document: "docTypeId", vehicle: "docTypeVehicle", hr: "docTypeHr", other: "docTypeOther",
};

export const LINK_TYPES = ["customer", "supplier", "product", "vehicle", "employee", "stock_document", "voucher", "lead", "opportunity", "warehouse"] as const;

export const LINK_LABEL: Record<string, MessageKey> = {
  customer: "docLinkCustomer", supplier: "docLinkSupplier", product: "docLinkProduct", vehicle: "docLinkVehicle",
  employee: "docLinkEmployee", stock_document: "docLinkStockDocument", voucher: "docLinkVoucher", lead: "docLinkLead",
  opportunity: "docLinkOpportunity", warehouse: "docLinkWarehouse",
};

/** Where a linked record opens, for the types whose screens exist today. */
export function linkHref(type: string, id: number): string | null {
  switch (type) {
    case "lead": return `/erp/crm/leads/${id}`;
    case "opportunity": return `/erp/crm/opportunities/${id}`;
    case "stock_document": return `/erp/documents/${id}`;
    case "product": return `/erp/products/${id}`;
    case "voucher": return `/vouchers/${id}`;
    default: return null;
  }
}

/** Mirrors Document::EXTENSIONS and MAX_UPLOAD_KB on the server. */
export const DOC_EXTENSIONS = ["pdf", "jpg", "jpeg", "png", "webp", "gif", "heic", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "csv", "txt"];
export const DOC_ACCEPT = DOC_EXTENSIONS.map((e) => `.${e}`).join(",");
export const DOC_MAX_BYTES = 20 * 1024 * 1024;

export function checkFile(file: File): "type" | "size" | null {
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  if (!DOC_EXTENSIONS.includes(ext)) return "type";
  if (file.size > DOC_MAX_BYTES) return "size";
  return null;
}

export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

export function fileIcon(name: string | null | undefined): string {
  const ext = name?.split(".").pop()?.toLowerCase() ?? "";
  if (ext === "pdf") return "ph-file-pdf";
  if (["jpg", "jpeg", "png", "webp", "gif", "heic"].includes(ext)) return "ph-file-image";
  if (["xls", "xlsx", "ods", "csv"].includes(ext)) return "ph-file-xls";
  if (["doc", "docx", "odt", "rtf"].includes(ext)) return "ph-file-doc";
  if (["ppt", "pptx", "odp"].includes(ext)) return "ph-file-ppt";
  return "ph-file-text";
}
