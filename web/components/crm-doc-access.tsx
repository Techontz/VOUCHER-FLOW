"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { AccessScope, Person } from "@/lib/crm-types";
import { Field } from "@/components/ui";

export interface AccessValue { access_scope: AccessScope; access_roles: string[]; access_users: number[] }

interface Directory { roles: { key: string; label: string }[]; people: Person[] }

let directory: Promise<Directory> | null = null;

/** Who a folder or document is shared with: everyone, chosen roles or chosen people. */
export function AccessEditor({ value, onChange, allowInherit, label }: {
  value: AccessValue; onChange: (v: AccessValue) => void; allowInherit?: boolean; label: string;
}) {
  const { t } = useApp();
  const [dir, setDir] = useState<Directory | null>(null);

  useEffect(() => {
    directory ??= api.get<Directory>("/erp/files/people");
    directory.then(setDir).catch(() => { directory = null; });
  }, []);

  const scopes: AccessScope[] = allowInherit ? ["inherit", "company", "roles", "users"] : ["company", "roles", "users"];
  const label_ = { inherit: t("docAccessInherit"), company: t("docAccessCompany"), roles: t("docAccessRoles"), users: t("docAccessUsers") } as const;
  const toggle = <T,>(list: T[], item: T) => (list.includes(item) ? list.filter((x) => x !== item) : [...list, item]);

  return (
    <>
      <Field label={label} htmlFor="acc-scope">
        <select id="acc-scope" className="input" value={value.access_scope} onChange={(e) => onChange({ ...value, access_scope: e.target.value as AccessScope })}>
          {scopes.map((s) => <option key={s} value={s}>{label_[s]}</option>)}
        </select>
      </Field>
      {value.access_scope === "roles" && (
        <fieldset className="field" style={{ border: 0, padding: 0, margin: 0 }}>
          <legend>{t("docRoles")}</legend>
          <div className="doc-picks">
            {(dir?.roles ?? []).map((r) => (
              <label key={r.key}><input type="checkbox" checked={value.access_roles.includes(r.key)} onChange={() => onChange({ ...value, access_roles: toggle(value.access_roles, r.key) })} /> {r.label}</label>
            ))}
          </div>
        </fieldset>
      )}
      {value.access_scope === "users" && (
        <fieldset className="field" style={{ border: 0, padding: 0, margin: 0 }}>
          <legend>{t("docPeople")}</legend>
          <div className="doc-picks">
            {(dir?.people ?? []).map((p) => (
              <label key={p.id}><input type="checkbox" checked={value.access_users.includes(p.id)} onChange={() => onChange({ ...value, access_users: toggle(value.access_users, p.id) })} /> {p.name}</label>
            ))}
          </div>
        </fieldset>
      )}
    </>
  );
}
