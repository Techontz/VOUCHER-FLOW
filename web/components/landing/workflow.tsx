"use client";

import { useEffect, useState } from "react";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { WORKFLOW, pick } from "@/components/landing/copy";

const STEP_MS = 5200;

/**
 * "How a voucher moves": the stages as a list of rows, one open at a time
 * with its full story, beside a voucher that travels through those stages as
 * you read. It advances on its own until someone picks a stage.
 */
export function WorkflowShowcase() {
  const { locale } = useApp();
  const l = (entry: readonly [string, string]) => pick(entry as [string, string], locale);
  const [active, setActive] = useState(0);
  const [held, setHeld] = useState(false);
  const stages = WORKFLOW.stages;

  useEffect(() => {
    if (held || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
    const timer = window.setInterval(() => setActive((i) => (i + 1) % stages.length), STEP_MS);
    return () => window.clearInterval(timer);
  }, [held, stages.length]);

  const choose = (i: number) => { setHeld(true); setActive(i); };

  return (
    <div className="wf">
      <div className="wf-copy">
        <ol className="wf-dots" aria-hidden="true">
          {stages.map((s, i) => (
            <li key={s.title[0]} data-state={i < active ? "done" : i === active ? "current" : "next"}>
              <span className="tnum">{i + 1}</span>
            </li>
          ))}
        </ol>

        <ul className="wf-steps">
          {stages.map((s, i) => {
            const open = i === active;
            return (
              <li key={s.title[0]} className="wf-step" data-open={open || undefined}>
                <button type="button" className="wf-pill" aria-expanded={open} onClick={() => choose(open ? (i + 1) % stages.length : i)}>
                  <span className="wf-num tnum">{i + 1}</span>
                  <span className="wf-pill-text"><span className="wf-accent">{l(s.title)}</span> {l(s.rest)}</span>
                  <span className="wf-role">{l(s.role)}</span>
                  <Icon name={open ? "ph-x" : "ph-plus"} size={15} />
                  {open && !held && <span className="wf-timer" style={{ animationDuration: `${STEP_MS}ms` }} aria-hidden="true" />}
                </button>
                {open && (
                  <div className="wf-body">
                    <h3><span className="wf-accent">{l(s.title)}</span> {l(s.rest)}</h3>
                    <p>{l(s.body)}</p>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>

      {/* The voucher itself, at the stage being read. */}
      <div className="wf-visual" aria-hidden="true">
        <div className="wf-card" key={active}>
          <div className="wf-card-top">
            <span className="wf-card-num tnum">PV-2026-000041</span>
            <span className="wf-card-status" data-stage={active}>
              <Icon name={stages[active].icon} size={14} /> {l(stages[active].status)}
            </span>
          </div>
          <div className="wf-card-payee">Highland Freight Services</div>
          <div className="wf-card-purpose">Freight to Mwanza: September consignment</div>
          <div className="wf-card-amount tnum">TZS 4,850,000</div>
          <ol className="wf-track">
            {stages.map((s, i) => (
              <li key={s.title[0]} data-state={i < active ? "done" : i === active ? "current" : "next"}>
                <span className="wf-track-dot">{i < active ? <Icon name="ph-check" size={12} weight="bold" /> : <Icon name={s.icon} size={13} />}</span>
                <span className="wf-track-text">
                  <strong>{l(s.title)}</strong>
                  <span>{l(s.role)}</span>
                </span>
              </li>
            ))}
          </ol>
        </div>
        <div className="wf-glow" />
      </div>
    </div>
  );
}
