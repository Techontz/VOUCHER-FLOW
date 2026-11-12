"use client";

import { AppIcon } from "@/components/app-icon";
import { Icon } from "@/components/ui";
import { pick, type L } from "@/components/landing/copy";
import { useApp } from "@/lib/app-context";
import { AREAS, type Area } from "@/lib/areas";
import { money } from "@/lib/format";
import type { Plan } from "@/lib/types";

/*
 * Choosing the apps a company's subscription includes.
 *
 * Used at registration (the customer picks from what their plan offers) and
 * by the platform when it creates, approves or edits a company (the operator
 * may go beyond the plan; an app outside it is marked so). Every app starts
 * ticked; VouchFlow cannot be unticked, it is the product itself.
 */

/** Every app a subscription can include, in launcher order. */
export const APP_AREAS: Area[] = AREAS.filter((a) => a.module);

export const ALL_APPS: string[] = APP_AREAS.map((a) => a.module as string);

const C = {
  selectAll: ["Select all", "Chagua zote"],
  clear: ["Clear", "Ondoa zote"],
  selected: ["{n} of {total} apps selected", "Programu {n} kati ya {total} zimechaguliwa"],
  included: ["{plan} includes {n} apps", "{plan} ina programu {n}"],
  includedAll: ["{plan} includes all apps", "{plan} ina programu zote"],
  untick: ["Untick any app you do not need. You can ask for it later.", "Ondoa alama kwenye programu usiyoihitaji. Unaweza kuiomba baadaye."],
  pickHint: ["Pick the apps you need. The price follows the number of apps.", "Chagua programu unazohitaji. Bei inafuata idadi ya programu."],
  always: ["Always included", "Imejumuishwa daima"],
  outside: ["Not in the plan", "Haipo kwenye mpango"],
  base: ["Base", "Msingi"],
  perApp: ["{n} apps at {price}", "Programu {n} kwa {price}"],
  total: ["Total", "Jumla"],
  perMonth: ["/ month", "/ mwezi"],
  allApps: ["All apps", "Programu zote"],
  nApps: ["{n} apps", "Programu {n}"],
  pickApps: ["Pick your apps", "Chagua programu"],
  fromPrice: ["from {base} + {each} per app", "kuanzia {base} + {each} kwa kila programu"],
} satisfies Record<string, L>;

const fill = (s: string, vars: Record<string, string | number>) =>
  s.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));

/** The apps a plan offers; a plan that lists none offers every app. */
export function planApps(plan?: Pick<Plan, "apps" | "modules"> | null): string[] {
  if (!plan) return ALL_APPS;
  if (plan.apps?.length) return plan.apps;
  if (plan.modules?.length) return Array.from(new Set(["vouchflow", ...plan.modules]));
  return ALL_APPS;
}

/** A plan's monthly price for a set of apps: base, plus each app when the customer picks. */
export function planMonthlyPrice(plan: Plan, apps: string[]): number {
  if (!plan.allows_module_choice) return plan.price;
  const count = apps.filter((a) => a !== "vouchflow" && planApps(plan).includes(a)).length;
  return plan.price + (plan.price_per_module ?? 0) * count;
}

/** "All apps", "10 apps" or "Pick your apps from ...", for a plan card. */
export function usePlanAppsLabel() {
  const { locale } = useApp();
  const l = (e: L) => pick(e, locale);
  return (plan: Plan): string => {
    if (plan.allows_module_choice) {
      return `${l(C.pickApps)} ${fill(l(C.fromPrice), {
        base: money(plan.price, plan.currency), each: money(plan.price_per_module ?? 0, plan.currency),
      })}`;
    }
    const apps = planApps(plan);
    return plan.all_apps || apps.length >= ALL_APPS.length ? l(C.allApps) : fill(l(C.nApps), { n: apps.length });
  };
}

/** A row of a few app icons, then "+N", for plan cards. */
export function AppStrip({ apps, max = 5, size = 26 }: { apps: string[]; max?: number; size?: number }) {
  const areas = APP_AREAS.filter((a) => apps.includes(a.module as string));
  const shown = areas.slice(0, max);
  return (
    <span className="app-strip" aria-hidden="true">
      {shown.map((a) => <AppIcon key={a.key} area={a} size={size} />)}
      {areas.length > shown.length && <span className="app-strip-more tnum">+{areas.length - shown.length}</span>}
    </span>
  );
}

export function AppPicker({
  value, onChange, plan, operator = false, disabled = false,
}: {
  value: string[];
  onChange: (apps: string[]) => void;
  /** The plan the apps come from: the customer sees only its apps, the operator sees which are outside it. */
  plan?: Plan | null;
  /** The platform operator: every app is offered, those outside the plan are marked. */
  operator?: boolean;
  disabled?: boolean;
}) {
  const { locale, t } = useApp();
  const l = (e: L) => pick(e, locale);
  const offered = planApps(plan);
  const choosable = operator ? ALL_APPS : offered;
  const areas = APP_AREAS.filter((a) => choosable.includes(a.module as string));
  const chosen = value.filter((v) => choosable.includes(v));
  const count = new Set(["vouchflow", ...chosen]).size;

  const toggle = (app: string) => {
    if (app === "vouchflow" || disabled) return;
    onChange(chosen.includes(app) ? chosen.filter((a) => a !== app) : [...chosen, app]);
  };

  const priced = !!plan?.allows_module_choice;
  const paidApps = chosen.filter((a) => a !== "vouchflow" && offered.includes(a)).length;

  return (
    <div className="app-pick">
      <div className="app-pick-head">
        <div>
          {plan && !operator && (
            <strong className="app-pick-title">
              {priced ? l(C.pickApps)
                : fill(l(plan.all_apps || offered.length >= ALL_APPS.length ? C.includedAll : C.included), { plan: plan.label ?? plan.name, n: offered.length })}
            </strong>
          )}
          <span className="app-pick-sub">
            {fill(l(C.selected), { n: count, total: areas.length })}
            {!operator && <> · {l(priced ? C.pickHint : C.untick)}</>}
          </span>
        </div>
        <div className="app-pick-bulk">
          <button type="button" className="app-pick-link" disabled={disabled} onClick={() => onChange(choosable)}>{l(C.selectAll)}</button>
          <button type="button" className="app-pick-link" disabled={disabled} onClick={() => onChange(["vouchflow"])}>{l(C.clear)}</button>
        </div>
      </div>

      <div className="app-pick-grid" role="group">
        {areas.map((a) => {
          const app = a.module as string;
          const locked = app === "vouchflow";
          const on = locked || chosen.includes(app);
          const outside = operator && plan && !offered.includes(app);
          return (
            <button key={a.key} type="button" className="app-pick-tile" aria-pressed={on}
              data-on={on || undefined} data-locked={locked || undefined} disabled={disabled || locked}
              onClick={() => toggle(app)}>
              <span className="app-pick-check" aria-hidden="true"><Icon name={locked ? "ph-lock-simple" : "ph-check"} size={12} weight="bold" /></span>
              <AppIcon area={a} size={48} />
              <span className="app-pick-name">{t(a.label)}</span>
              <span className="app-pick-note">{locked ? l(C.always) : outside ? l(C.outside) : t(a.blurb)}</span>
            </button>
          );
        })}
      </div>

      {priced && plan && (
        <dl className="app-pick-total tnum">
          <div><dt>{l(C.base)}</dt><dd>{money(plan.price, plan.currency)}</dd></div>
          <div><dt>{fill(l(C.perApp), { n: paidApps, price: money(plan.price_per_module ?? 0, plan.currency) })}</dt><dd>{money((plan.price_per_module ?? 0) * paidApps, plan.currency)}</dd></div>
          <div className="app-pick-sum"><dt>{l(C.total)}</dt><dd>{money(planMonthlyPrice(plan, chosen), plan.currency)} <small>{l(C.perMonth)}</small></dd></div>
        </dl>
      )}
    </div>
  );
}
