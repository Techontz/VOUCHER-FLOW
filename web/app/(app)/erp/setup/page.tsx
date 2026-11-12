"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type BusinessTemplate, type ErpConfig, type ModuleInfo, type ModuleKey, type ProductField, useErp } from "@/lib/erp";
import { Banner, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, fill } from "@/components/erp-ui";

type Step = 0 | 1 | 2 | 3;

interface SetupResult { created: { units: number; categories: number; warehouses: number; accounts: number } }

/**
 * The business setup wizard. Four short steps, what you are, what you run,
 * your policies, a last look, and one call that prepares everything. It can
 * be run again: only what is missing is added.
 */
export default function ErpSetupPage() {
  const { t, user } = useApp();
  const { config, loading, can } = useErp();
  const [templates, setTemplates] = useState<{ data: BusinessTemplate[]; modules: ModuleInfo[] } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: BusinessTemplate[]; modules: ModuleInfo[] }>("/erp/templates").then(setTemplates).catch((e) => setError(e.message));
  }, []);

  if (error) return <ErrorState message={error} />;
  if (loading || !templates || !config) return <LoadingBlock rows={6} />;
  if (!can("erp.configure") && user?.role !== "company_admin") return <EmptyState icon="ph-lock-simple" title={t("erpNoAccess")} />;

  return <Wizard config={config} templates={templates.data} modules={templates.modules} />;
}

/** The steps themselves, seeded once from what the company already has. */
function Wizard({ config, templates, modules }: { config: ErpConfig; templates: BusinessTemplate[]; modules: ModuleInfo[] }) {
  const { t, locale, toast } = useApp();
  const router = useRouter();
  const { refresh } = useErp();
  const again = config.is_set_up;
  const [step, setStep] = useState<Step>(0);
  const [type, setType] = useState<string>(again ? config.business_type : "");
  const [chosen, setChosen] = useState<ModuleKey[]>(again ? config.modules : []);
  const [negative, setNegative] = useState(config.settings.allow_negative_stock);
  const [currency, setCurrency] = useState(config.settings.base_currency);
  const [tax, setTax] = useState(String(config.settings.default_tax_rate));
  const [expiryDays, setExpiryDays] = useState(String(config.settings.expiry_alert_days));
  const [fields, setFields] = useState<ProductField[]>(again ? config.settings.product_fields : []);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const template = useMemo(() => templates.find((x) => x.key === type) ?? null, [templates, type]);

  // Apps outside the subscription are shown, locked, so the company knows
  // they exist, but are never sent: the API would refuse them.
  const licensed = (key: ModuleKey) => !config.licensed_modules || config.licensed_modules.includes(key);

  function pick(next: BusinessTemplate) {
    setType(next.key);
    setChosen(next.modules.filter(licensed));
    if (!again || !config.settings.product_fields.length) setFields(next.product_fields);
    setStep(1);
  }

  async function apply() {
    setBusy(true); setFormError(null);
    try {
      const result = await api.post<SetupResult>("/erp/setup", {
        business_type: type,
        modules: chosen,
        settings: {
          allow_negative_stock: negative,
          base_currency: currency.toUpperCase(),
          default_tax_rate: Number(tax),
          expiry_alert_days: Number(expiryDays),
          product_fields: fields.filter((f) => f.label.trim()).map((f) => ({ ...f, key: f.key || slug(f.label) })),
        },
      });
      await refresh();
      toast(t("erpSetupDone"), fill(t("erpSetupDoneBody"), result.created), "ok");
      router.push("/erp");
    } catch (e) {
      setFormError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const steps = [t("erpStepType"), t("erpStepModules"), t("erpStepSettings"), t("erpStepReview")];

  return (
    <div className="erp-page">
      <PageHeader title={t("erpSetup")} subtitle={t("erpSetupSub")} />

      {again && (
        <Banner icon="ph-check-circle" title={fill(t("erpAlreadySetUp"), { type: config.business_label ?? config.business_type })}>
          {t("erpAlreadySetUpBody")}
        </Banner>
      )}

      <ol className="erp-steps" aria-label={t("erpSetup")}>
        {steps.map((label, i) => (
          <li key={label} data-state={i < step ? "done" : i === step ? "current" : "todo"}>
            <button type="button" disabled={i > 0 && !type} onClick={() => setStep(i as Step)}>
              <span className="erp-step-num">{i < step ? <Icon name="ph-check" size={14} weight="bold" /> : i + 1}</span>
              <span>{label}</span>
            </button>
          </li>
        ))}
      </ol>

      {step === 0 && (
        <div className="erp-templates">
          {templates.map((tpl) => (
            <button key={tpl.key} type="button" className="erp-template" aria-pressed={type === tpl.key} onClick={() => pick(tpl)}>
              <span className="erp-template-icon"><Icon name={tpl.icon} size={24} /></span>
              <span className="erp-template-name">{locale === "sw" ? tpl.label_sw : tpl.label}</span>
              <span className="erp-template-desc">{tpl.description}</span>
              <span className="erp-template-meta">
                {fill(t("erpUnitsCount"), { n: tpl.units.length })} · {fill(t("erpCategoriesCount"), { n: tpl.categories.length })}
                {tpl.product_fields.length > 0 && <> · {fill(t("erpFieldsCount"), { n: tpl.product_fields.length })}</>}
              </span>
            </button>
          ))}
        </div>
      )}

      {step === 1 && (
        <GlassCard title={t("erpStepModules")} subtitle={template ? (locale === "sw" ? template.label_sw : template.label) : undefined}>
          <div className="erp-module-pick">
            {modules.map((m) => {
              const unlicensed = !licensed(m.key);
              const locked = m.key === "vouchflow" || unlicensed;
              const on = chosen.includes(m.key) && !unlicensed;
              return (
                <label key={m.key} className="erp-module-option" data-on={on ? "" : undefined} data-live={m.live ? "" : undefined}
                  data-unlicensed={unlicensed ? "" : undefined} style={unlicensed ? { opacity: 0.55 } : undefined}>
                  <input type="checkbox" checked={on} disabled={locked}
                    onChange={(e) => setChosen((all) => (e.target.checked ? [...all, m.key] : all.filter((k) => k !== m.key)))} />
                  <span className="erp-module-option-main">
                    <span className="erp-module-name">{m.label}</span>
                    <span className="erp-module-state">
                      {unlicensed
                        ? <><Icon name="ph-lock-simple" size={12} /> {t("erpNotInSubscription")}</>
                        : m.live ? t("erpLive") : fill(t("erpComingPhase"), { n: m.phase })}
                    </span>
                  </span>
                </label>
              );
            })}
          </div>
          <StepNav onBack={() => setStep(0)} onNext={() => setStep(2)} />
        </GlassCard>
      )}

      {step === 2 && (
        <GlassCard title={t("erpStepSettings")}>
          <div className="erp-form-grid">
            <Field label={t("erpCurrency")} htmlFor="erp-currency">
              <input id="erp-currency" className="input" maxLength={3} value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} />
            </Field>
            <Field label={t("erpTaxRate")} htmlFor="erp-tax">
              <input id="erp-tax" className="input tnum" type="number" min={0} max={100} value={tax} onChange={(e) => setTax(e.target.value)} />
            </Field>
            <Field label={t("erpExpiryWindow")} htmlFor="erp-expiry">
              <input id="erp-expiry" className="input tnum" type="number" min={0} max={730} value={expiryDays} onChange={(e) => setExpiryDays(e.target.value)} />
            </Field>
          </div>
          <Check label={t("erpNegativeStock")} hint={t("erpNegativeStockHint")} checked={negative} onChange={setNegative} />

          <h3 className="erp-subhead">{t("erpProductFields")}</h3>
          <p className="erp-muted">{t("erpProductFieldsHint")}</p>
          <div className="erp-fields">
            {fields.map((f, i) => (
              <div key={i} className="erp-field-row">
                <input className="input" aria-label={t("erpFieldLabel")} placeholder={t("erpFieldLabel")} value={f.label}
                  onChange={(e) => setFields((all) => all.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))} />
                <select className="input" aria-label={t("erpType")} value={f.type}
                  onChange={(e) => setFields((all) => all.map((x, j) => (j === i ? { ...x, type: e.target.value as ProductField["type"] } : x)))}>
                  <option value="text">Text</option><option value="number">Number</option>
                  <option value="date">Date</option><option value="boolean">Yes / no</option>
                </select>
                <button type="button" className="btn btn-icon" aria-label={t("erpRemove")} onClick={() => setFields((all) => all.filter((_, j) => j !== i))}>
                  <Icon name="ph-trash" size={18} />
                </button>
              </div>
            ))}
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => setFields((all) => [...all, { key: "", label: "", type: "text" }])}>
              <Icon name="ph-plus" size={16} /> {t("erpAddField")}
            </button>
          </div>
          <StepNav onBack={() => setStep(1)} onNext={() => setStep(3)} />
        </GlassCard>
      )}

      {step === 3 && template && (
        <GlassCard title={t("erpStepReview")} subtitle={locale === "sw" ? template.label_sw : template.label}>
          <dl className="erp-review">
            <dt>{t("erpStepModules")}</dt>
            <dd>{modules.filter((m) => chosen.includes(m.key)).map((m) => m.label).join(" · ")}</dd>
            <dt>{t("erpTemplatePrepares")}</dt>
            <dd>
              {template.units.map((u) => u.name).join(", ")}
              <br />{template.categories.join(", ")}
            </dd>
            <dt>{t("erpStepSettings")}</dt>
            <dd className="tnum">{currency} · {tax}% · {expiryDays}d · {negative ? t("erpNegativeStock") : "-"}</dd>
            {fields.length > 0 && <><dt>{t("erpProductFields")}</dt><dd>{fields.map((f) => f.label).filter(Boolean).join(", ")}</dd></>}
          </dl>
          {formError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {formError}</div>}
          <div className="erp-stepnav">
            <button type="button" className="btn btn-secondary" onClick={() => setStep(2)}>{t("erpBack")}</button>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={apply}>
              <Icon name="ph-sparkle" size={18} /> {again ? t("erpReapply") : t("erpApply")}
            </button>
          </div>
        </GlassCard>
      )}
    </div>
  );
}

function StepNav({ onBack, onNext }: { onBack: () => void; onNext: () => void }) {
  const { t } = useApp();
  return (
    <div className="erp-stepnav">
      <button type="button" className="btn btn-secondary" onClick={onBack}>{t("erpBack")}</button>
      <button type="button" className="btn btn-primary" onClick={onNext}>{t("erpNext")} <Icon name="ph-arrow-right" size={16} /></button>
    </div>
  );
}

function slug(label: string): string {
  const s = label.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return /^[a-z]/.test(s) ? s.slice(0, 40) : `f_${s}`.slice(0, 40);
}
