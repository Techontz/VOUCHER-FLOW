/**
 * The body the workflow builder sends when it saves.
 *
 * Pulled out of the page and tested because this one mapping silently
 * corrupted routes twice. It omitted `can_pay`, which the API defaults to
 * false, so any save removed payment from every step. And it derived
 * `requires_signature` from `can_sign` instead of sending the stored value, so
 * any save forced a sign-and-approve step to sign before it could approve.
 *
 * The rule now is simple: every flag the backend stores goes back exactly as
 * it was loaded, unless the person editing changed it.
 */

import type { Workflow, WorkflowStep } from "./types";

export function workflowPayload(workflow: Pick<Workflow, "name" | "description" | "is_default" | "is_active">, steps: WorkflowStep[]) {
  return {
    name: workflow.name,
    description: workflow.description,
    is_default: workflow.is_default,
    is_active: workflow.is_active,
    steps: steps.map((step, index) => ({
      id: step.id,
      position: index + 1,
      name: step.name,
      name_sw: step.name_sw,
      role: step.role,
      assigned_user_id: step.assigned_user_id,
      assignee_hint: step.assignee_hint,
      can_sign: step.can_sign,
      can_approve: step.can_approve,
      can_reject: step.can_reject,
      can_request_changes: step.can_request_changes,
      can_pay: step.can_pay,
      can_print: step.can_print,
      can_download: step.can_download,
      requires_signature: step.requires_signature,
      min_amount: step.min_amount,
      max_amount: step.max_amount,
    })),
  };
}
