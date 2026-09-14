/**
 * Where a voucher is in its approval route, for list rows and dashboard cards.
 *
 * The voucher page renders the backend's own timeline, which carries names,
 * times and signatures. List payloads do not include it — building a timeline
 * for every row would cost a query per voucher — so this derives the route from
 * the company's real workflow instead: which steps exist, which apply to this
 * amount, and where the voucher currently sits.
 *
 * The step rules mirror WorkflowEngine and WorkflowStep on the server exactly.
 * Nothing about any particular company's route is assumed here: a tenant that
 * runs Employee → Supervisor → Finance gets that ladder, and one with amount
 * thresholds gets only the steps its amount actually passes through.
 */

import type { Voucher, Workflow, WorkflowStep } from "./types";

export type StepState = "done" | "current" | "pending" | "rejected";

export interface ProgressStep {
  key: string;
  label: string;
  state: StepState;
}

/** WorkflowStep::isRequestStep — the step that raises the voucher. */
export function isRequestStep(step: WorkflowStep): boolean {
  return step.position === 1 || step.role === "employee";
}

/** WorkflowStep::isPaymentStep — releasing money, not deciding on it. */
export function isPaymentStep(step: WorkflowStep): boolean {
  return step.can_pay && !step.can_approve;
}

/** WorkflowStep::appliesToAmount — amount thresholds, both ends inclusive. */
export function appliesToAmount(step: WorkflowStep, amount: number): boolean {
  if (step.min_amount !== null && step.min_amount !== undefined && amount < Number(step.min_amount)) return false;
  if (step.max_amount !== null && step.max_amount !== undefined && amount > Number(step.max_amount)) return false;
  return true;
}

/** WorkflowEngine::applicableSteps. */
export function applicableSteps(workflow: Workflow, amount: number): WorkflowStep[] {
  return [...workflow.steps]
    .sort((a, b) => a.position - b.position)
    .filter((step) => isRequestStep(step) || appliesToAmount(step, amount));
}

/** A short, role-level name for a step: "HOD", "Managing Director", "Finance". */
function stepLabel(step: WorkflowStep, locale: "en" | "sw"): string {
  if (locale === "sw" && step.name_sw) return step.name_sw;
  return step.role_label || step.name;
}

export function deriveProgress(
  voucher: Pick<Voucher, "status" | "amount" | "workflow_id" | "current_step_position">,
  workflows: Workflow[] | null | undefined,
  locale: "en" | "sw" = "en",
): ProgressStep[] {
  const workflow = workflows?.find((w) => w.id === voucher.workflow_id);
  if (!workflow || !workflow.steps?.length) return [];

  const steps = applicableSteps(workflow, Number(voucher.amount) || 0);
  const approvals = steps.filter((s) => !isRequestStep(s) && !isPaymentStep(s));
  const payment = steps.find((s) => isPaymentStep(s));

  const status = voucher.status;
  const at = voucher.current_step_position;

  const prepared: ProgressStep = {
    key: "prepared",
    label: locale === "sw" ? "Imeandaliwa" : "Prepared",
    state: status === "draft" ? "current" : "done",
  };

  const approvalSteps: ProgressStep[] = approvals.map((step) => {
    let state: StepState = "pending";

    if (status === "approved" || status === "paid") {
      state = "done";
    } else if (status === "in_review" && at !== null) {
      state = step.position < at ? "done" : step.position === at ? "current" : "pending";
    } else if (status === "rejected") {
      // The route stops where the decision was made.
      if (at !== null) state = step.position < at ? "done" : step.position === at ? "rejected" : "pending";
    }

    return { key: `step-${step.position}`, label: stepLabel(step, locale), state };
  });

  // A rejection with no recorded position still has to show where it ended.
  if (status === "rejected" && !approvalSteps.some((s) => s.state === "rejected")) {
    const last = [...approvalSteps].reverse().find((s) => s.state !== "done") ?? approvalSteps[approvalSteps.length - 1];
    if (last) last.state = "rejected";
  }

  const result = [prepared, ...approvalSteps];

  if (payment) {
    result.push({
      key: "payment",
      label: stepLabel(payment, locale),
      state: status === "paid" ? "done" : status === "approved" ? "current" : "pending",
    });
  }

  return result;
}

/**
 * WorkflowEngine::resolveWorkflow — which route a new voucher of this type
 * will take. Active only; a workflow bound to the type beats a general one,
 * and among general ones the default wins.
 */
export function resolveWorkflow(workflows: Workflow[] | null | undefined, voucherTypeId: number): Workflow | null {
  const candidates = (workflows ?? []).filter(
    (w) => w.is_active && (w.voucher_type_id === voucherTypeId || w.voucher_type_id === null),
  );

  candidates.sort((a, b) => {
    const typeA = a.voucher_type_id === null ? 1 : 0;
    const typeB = b.voucher_type_id === null ? 1 : 0;
    if (typeA !== typeB) return typeA - typeB;
    return Number(b.is_default) - Number(a.is_default);
  });

  return candidates[0] ?? null;
}

/** The steps a voucher of this amount will pass through, after it is raised. */
export function routeFor(workflow: Workflow | null, amount: number, locale: "en" | "sw" = "en"): string[] {
  if (!workflow) return [];
  return applicableSteps(workflow, amount)
    .filter((step) => !isRequestStep(step))
    .map((step) => (locale === "sw" && step.name_sw ? step.name_sw : step.role_label || step.name));
}
