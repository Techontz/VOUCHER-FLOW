"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { SettingsLayout } from "@/components/app-ui";
import type { Role } from "@/lib/types";

/**
 * Roles & access — a read-only explanation of the fixed roles.
 *
 * Roles are defined in the backend (User::ROLES) and cannot be edited, so this
 * page explains them rather than pretending to be a permissions editor. What a
 * role may sign, approve or pay comes from workflow steps, and the page says so
 * and links there. The rules restate VoucherVisibility and WorkflowEngine.
 */

type Cell = "yes" | "no" | [string, string];

const COLUMNS: { role: Role; label: [string, string] }[] = [
  { role: "employee", label: ["Employee", "Mfanyakazi"] },
  { role: "hod", label: ["HOD", "Mkuu wa idara"] },
  { role: "manager", label: ["Manager", "Meneja"] },
  { role: "ceo", label: ["CEO", "Mkurugenzi Mtendaji"] },
  { role: "director", label: ["Director", "Mkurugenzi"] },
  { role: "finance", label: ["Finance", "Fedha"] },
  { role: "cashier", label: ["Cashier", "Mhazini"] },
  { role: "company_admin", label: ["Company admin", "Msimamizi"] },
];

const ON_STEP: Cell = ["on a step", "kwenye hatua"];
const DEPT: Cell = ["department", "idara"];
const COMPANY: Cell = ["company", "kampuni"];

const GROUPS: { title: [string, string]; rows: { label: [string, string]; cells: Cell[] }[] }[] = [
  {
    title: ["Vouchers they can see", "Vocha wanazoweza kuona"],
    rows: [
      { label: ["Their own vouchers", "Vocha zao wenyewe"], cells: ["yes", "yes", "yes", "yes", "yes", "yes", "yes", "yes"] },
      { label: ["Their department's vouchers (not drafts)", "Vocha za idara yao (si rasimu)"], cells: ["no", "yes", "yes", "no", "no", "no", "no", "yes"] },
      { label: ["Anything routed to their role, company-wide", "Chochote kinachopitia jukumu lao, kampuni nzima"], cells: ["no", "no", "no", "yes", "yes", "yes", "yes", "yes"] },
    ],
  },
  {
    title: ["What they can do", "Wanachoweza kufanya"],
    rows: [
      { label: ["Raise and submit vouchers", "Kuandaa na kuwasilisha vocha"], cells: ["yes", "yes", "yes", "yes", "yes", "yes", "no", "yes"] },
      { label: ["Sign, approve, reject, request changes", "Kusaini, kuidhinisha, kukataa, kuomba mabadiliko"], cells: ["no", ON_STEP, ON_STEP, ON_STEP, ON_STEP, ON_STEP, ON_STEP, ["any step", "hatua yoyote"]] },
      { label: ["Pay approved vouchers", "Kulipa vocha zilizoidhinishwa"], cells: ["no", "no", "no", "no", "no", ["pay step", "hatua ya malipo"], ["pay step", "hatua ya malipo"], "yes"] },
    ],
  },
  {
    title: ["Administration", "Utawala"],
    rows: [
      { label: ["Employees, departments, workflow, branding", "Wafanyakazi, idara, mtiririko, chapa"], cells: ["no", "no", "no", "no", "no", "no", "no", "yes"] },
      { label: ["Subscription and billing", "Usajili na malipo"], cells: ["no", "no", "no", "no", "no", "no", "no", "yes"] },
      { label: ["Reports", "Ripoti"], cells: ["no", DEPT, DEPT, COMPANY, COMPANY, COMPANY, COMPANY, COMPANY] },
    ],
  },
];

export default function RolesPage() {
  const { t, locale } = useApp();
  const sw = locale === "sw";
  const [counts, setCounts] = useState<Partial<Record<Role, number>> | null>(null);

  useEffect(() => {
    api.get<{ data: { role: Role }[] }>("/directory")
      .then((r) => {
        const tally: Partial<Record<Role, number>> = {};
        for (const u of r.data) tally[u.role] = (tally[u.role] ?? 0) + 1;
        setCounts(tally);
      })
      .catch(() => setCounts({}));
  }, []);

  const L = (pair: [string, string]) => pair[sw ? 1 : 0];

  return (
    <SettingsLayout
      title={t("rolesAccess")}
      sub={sw ? "Kila jukumu linaweza kuona na kufanya nini katika kampuni hii" : "What each role can see and do in this company"}
    >
      <div className="vf-alert tone-info app-roles-note">
        <Icon name="ph-flow-arrow" size={20} style={{ flex: "none" }} />
        <div className="vf-alert-text">
          {sw
            ? <>Kusaini, kuidhinisha na kulipa hutolewa na <strong>hatua za mtiririko</strong>, si jukumu pekee. Jukumu hupata uwezo huu pale tu hatua inapopewa jukumu hilo.</>
            : <>Signing, approving and paying are granted by <strong>workflow steps</strong>, not by role alone. A role gets these powers only when a step is assigned to it.</>}
        </div>
        <Link href="/settings#workflow" className="btn btn-ghost btn-sm">{sw ? "Fungua mtiririko" : "Open workflow"} <Icon name="ph-arrow-right" size={14} /></Link>
      </div>

      <section className="vf-panel app-roles">
        <div className="table-wrap">
          <table className="table app-roles-table">
            <thead>
              <tr>
                <th>{sw ? "Uwezo" : "Capability"}</th>
                {COLUMNS.map((c) => (
                  <th key={c.role} className="app-roles-col">
                    <span>{L(c.label)}</span>
                    <span className="app-roles-count tnum">{counts ? counts[c.role] ?? 0 : "·"}</span>
                  </th>
                ))}
              </tr>
            </thead>
            {GROUPS.map((group) => (
              <tbody key={group.title[0]}>
                <tr className="app-roles-group"><td colSpan={COLUMNS.length + 1}>{L(group.title)}</td></tr>
                {group.rows.map((row) => (
                  <tr key={row.label[0]}>
                    <td className="app-roles-label">{L(row.label)}</td>
                    {row.cells.map((cell, i) => (
                      <td key={COLUMNS[i].role} className="app-roles-cell">
                        {cell === "yes" ? <Icon name="ph-check" size={16} style={{ color: "var(--success)" }} />
                          : cell === "no" ? <span className="app-roles-no" aria-label={sw ? "Hapana" : "No"}>—</span>
                          : <span className="app-roles-scope">{L(cell)}</span>}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            ))}
          </table>
        </div>
      </section>
    </SettingsLayout>
  );
}
