"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { api, ApiError, request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Dialog, Icon, LanguageToggle, Spinner, ThemeToggle } from "@/components/ui";
import { VouchFlowMark } from "@/components/login-brand";
import { pick, type L } from "@/components/landing/copy";
import { money } from "@/lib/format";
import type { Company, Plan, User } from "@/lib/types";

/**
 * Setting a company up on VouchFlow.
 *
 * Five short steps instead of one long form, and nothing is sent until the
 * last one. Then, in order:
 *
 *   1. POST /auth/register  — company, administrator and plan, exactly as
 *                             before. This is the only call that can fail the
 *                             registration.
 *   2. PUT  /company        — trading name, TIN, contact details and colours,
 *                             through the same endpoint Settings uses.
 *   3. POST /company/logo   — the logo, through the same validated upload.
 *
 * Steps 2 and 3 run as the new administrator. If either is refused, the
 * company still exists and the person is told precisely what to finish in
 * Settings — never asked to register a second time.
 */

type StepKey = "company" | "contact" | "branding" | "admin" | "review";

const STEPS: { key: StepKey; label: L; title: L; sub: L }[] = [
  { key: "company", label: ["Company", "Kampuni"], title: ["Tell us about your company", "Tueleze kuhusu kampuni yako"], sub: ["The legal details that appear on every voucher you issue.", "Taarifa rasmi zitakazoonekana kwenye kila vocha mtakayotoa."] },
  { key: "contact", label: ["Contact", "Mawasiliano"], title: ["How can we reach you?", "Tunawezaje kuwasiliana nanyi?"], sub: ["Who to contact about the account, and where the company is based.", "Mtu wa kuwasiliana kuhusu akaunti, na mahali kampuni ilipo."] },
  { key: "branding", label: ["Branding", "Chapa"], title: ["Make it yours", "Ifanye iwe yako"], sub: ["Your logo and colours on screen and on the printed voucher. You can change these later.", "Nembo na rangi zenu kwenye skrini na kwenye vocha iliyochapishwa. Mnaweza kubadilisha baadaye."] },
  { key: "admin", label: ["Admin", "Msimamizi"], title: ["Create the administrator", "Unda msimamizi"], sub: ["This person sets up departments, people and approval routes.", "Mtu huyu ataweka idara, watu na njia za idhini."] },
  { key: "review", label: ["Review", "Hakiki"], title: ["Review and create", "Hakiki na uunde"], sub: ["Check the details, choose a plan, and create your company.", "Hakiki taarifa, chagua mpango, na uunde kampuni yako."] },
];

const C = {
  heroTitle: ["Set up your company on VouchFlow.", "Sajili kampuni yako kwenye VouchFlow."],
  heroSub: ["Vouchers, approvals and payments in one controlled workflow — ready for your team in a few minutes.", "Vocha, idhini na malipo katika mtiririko mmoja wenye udhibiti — tayari kwa timu yako ndani ya dakika chache."],
  stepOf: ["Step", "Hatua"], of: ["of", "kati ya"],
  companyName: ["Registered company name", "Jina rasmi la kampuni"], companyNamePh: ["e.g. Afiya Beverages Limited", "mf. Afiya Beverages Limited"],
  tradingName: ["Trading name", "Jina la biashara"], tradingHint: ["If different from the registered name.", "Kama ni tofauti na jina rasmi."],
  tin: ["TIN", "TIN"], tinHint: ["Taxpayer identification number.", "Namba ya utambulisho wa mlipakodi."],
  regNo: ["Registration number", "Namba ya usajili"], regHint: ["From your certificate of incorporation.", "Kutoka kwenye cheti cha usajili."],
  country: ["Country", "Nchi"], currency: ["Currency", "Sarafu"],
  contactPerson: ["Contact person", "Mtu wa kuwasiliana"], email: ["Company email", "Barua pepe ya kampuni"], emailPh: ["accounts@company.co.tz", "hesabu@kampuni.co.tz"],
  phone: ["Phone", "Simu"], address: ["Physical address", "Anwani ya mahali"], addressPh: ["Plot, street and area", "Kiwanja, mtaa na eneo"],
  city: ["City", "Mji"], region: ["Region", "Mkoa"],
  logo: ["Company logo", "Nembo ya kampuni"], logoHint: ["PNG, JPG or WEBP, up to 2 MB. A wide logo on a transparent background prints best.", "PNG, JPG au WEBP, hadi MB 2. Nembo pana isiyo na mandharinyuma huchapika vizuri."],
  chooseLogo: ["Choose a logo", "Chagua nembo"], replace: ["Replace", "Badilisha"], remove: ["Remove", "Ondoa"],
  primary: ["Primary colour", "Rangi kuu"], secondary: ["Secondary colour", "Rangi ya pili"],
  preview: ["Preview", "Mwonekano"], previewVoucher: ["Payment voucher", "Vocha ya malipo"],
  adminName: ["Full name", "Jina kamili"], adminEmail: ["Work email", "Barua pepe ya kazi"], adminEmailHint: ["You will sign in with this, and we will send a verification code to it.", "Utaingia kwa hii, na tutatuma namba ya uthibitisho kwake."],
  password: ["Password", "Nenosiri"], passwordHint: ["At least 8 characters.", "Angalau herufi 8."], confirm: ["Confirm password", "Thibitisha nenosiri"],
  show: ["Show password", "Onyesha nenosiri"], hide: ["Hide password", "Ficha nenosiri"],
  plan: ["Plan", "Mpango"], trial: ["day free trial", "siku za majaribio bure"], custom: ["Custom pricing", "Bei maalum"], perMonth: ["/ month", "/ mwezi"],
  edit: ["Edit", "Hariri"], notProvided: ["Not provided", "Haijatolewa"], none: ["None", "Hakuna"],
  back: ["Back", "Nyuma"], continue: ["Continue", "Endelea"], create: ["Create company", "Unda kampuni"],
  already: ["Already registered?", "Umeshasajili?"], signIn: ["Sign in", "Ingia"],
  required: ["This is required.", "Hili linahitajika."], badEmail: ["Enter a valid email address.", "Weka barua pepe sahihi."],
  shortPassword: ["Use at least 8 characters.", "Tumia angalau herufi 8."], mismatch: ["The passwords do not match.", "Manenosiri hayalingani."],
  badColour: ["Use a colour like #2563EB.", "Tumia rangi kama #2563EB."], badLogoType: ["The logo must be a PNG, JPG or WEBP image.", "Nembo lazima iwe picha ya PNG, JPG au WEBP."], badLogoSize: ["The logo must be 2 MB or smaller.", "Nembo lazima isizidi MB 2."],
  confirmTitle: ["Create this company?", "Unda kampuni hii?"], confirmSub: ["We will create the company and its administrator, then send a verification code to the administrator's email.", "Tutaunda kampuni na msimamizi wake, kisha tutatuma namba ya uthibitisho kwa barua pepe ya msimamizi."],
  creating: ["Creating your company…", "Tunaunda kampuni yako…"], cancel: ["Cancel", "Ghairi"],
  doneTitle: ["Your company is ready", "Kampuni yako iko tayari"], doneSub: ["One last step: confirm the administrator's email, then set up departments and your approval route.", "Hatua moja ya mwisho: thibitisha barua pepe ya msimamizi, kisha weka idara na njia ya idhini."],
  savedCompany: ["Company and administrator created", "Kampuni na msimamizi vimeundwa"], savedDetails: ["Company details and colours saved", "Taarifa na rangi za kampuni zimehifadhiwa"], savedLogo: ["Logo uploaded", "Nembo imepakiwa"],
  finishInSettings: ["Not saved — add it later in Settings → Branding", "Haijahifadhiwa — iongeze baadaye kwenye Mipangilio → Chapa"],
  verify: ["Verify email", "Thibitisha barua pepe"],
  fixErrors: ["Some details need attention", "Baadhi ya taarifa zinahitaji marekebisho"],
} satisfies Record<string, L>;

const REGIONS = ["Arusha", "Dar es Salaam", "Dodoma", "Geita", "Iringa", "Kagera", "Katavi", "Kigoma", "Kilimanjaro", "Lindi", "Manyara", "Mara", "Mbeya", "Morogoro", "Mtwara", "Mwanza", "Njombe", "Pemba North", "Pemba South", "Pwani", "Rukwa", "Ruvuma", "Shinyanga", "Simiyu", "Singida", "Songwe", "Tabora", "Tanga", "Zanzibar North", "Zanzibar South", "Zanzibar Urban West"];

const HEX = /^#[0-9a-fA-F]{6}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"];
const LOGO_MAX = 2 * 1024 * 1024;

/** Which step owns each server-side field, so a refusal takes the person to it. */
const FIELD_STEP: Record<string, number> = {
  company_name: 0, country: 0, currency: 0, trading_name: 0, tin: 0, registration_number: 0,
  business_email: 1, phone: 1, address: 1, contact_person: 1, city: 1, region: 1,
  primary_color: 2, secondary_color: 2, logo: 2,
  name: 3, email: 3, password: 3, password_confirmation: 3,
  plan_code: 4,
};

type Outcome = { details: "ok" | "failed" | "skipped"; logo: "ok" | "failed" | "skipped"; verifyUrl: string; company: string };

export default function RegisterPage() {
  const router = useRouter();
  const { locale, applySession } = useApp();
  const l = (entry: L) => pick(entry, locale);

  const [step, setStep] = useState(0);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [planCode, setPlanCode] = useState("business");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [serverMessage, setServerMessage] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [reveal, setReveal] = useState(false);
  const headingRef = useRef<HTMLHeadingElement>(null);

  const [form, setForm] = useState({
    company_name: "", trading_name: "", tin: "", registration_number: "", country: "TZ", currency: "TZS",
    contact_person: "", business_email: "", phone: "", address: "", city: "", region: "",
    primary_color: "#2563EB", secondary_color: "#0B1D3A",
    name: "", email: "", password: "", password_confirmation: "",
  });
  const [logo, setLogo] = useState<File | null>(null);
  const logoPreview = useMemo(() => (logo ? URL.createObjectURL(logo) : null), [logo]);
  useEffect(() => () => { if (logoPreview) URL.revokeObjectURL(logoPreview); }, [logoPreview]);

  useEffect(() => {
    api.get<{ data: Plan[] }>("/plans").then((r) => setPlans(r.data.filter((p) => p.is_public))).catch(() => setPlans([]));
  }, []);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const value = e.target.value;
    setForm((f) => ({ ...f, [key]: value }));
    if (errors[key]) setErrors((all) => { const next = { ...all }; delete next[key]; return next; });
  };

  function problemsAt(index: number): Record<string, string> {
    const out: Record<string, string> = {};
    const req = (key: keyof typeof form) => { if (!form[key].trim()) out[key] = l(C.required); };
    if (index === 0) req("company_name");
    if (index === 1) {
      req("contact_person");
      if (!form.business_email.trim()) out.business_email = l(C.required);
      else if (!EMAIL.test(form.business_email.trim())) out.business_email = l(C.badEmail);
    }
    if (index === 2) {
      if (!HEX.test(form.primary_color)) out.primary_color = l(C.badColour);
      if (!HEX.test(form.secondary_color)) out.secondary_color = l(C.badColour);
    }
    if (index === 3) {
      req("name");
      if (!form.email.trim()) out.email = l(C.required);
      else if (!EMAIL.test(form.email.trim())) out.email = l(C.badEmail);
      if (form.password.length < 8) out.password = l(C.shortPassword);
      if (form.password_confirmation !== form.password) out.password_confirmation = l(C.mismatch);
    }
    return out;
  }

  function go(next: number) {
    if (next > step) {
      for (let i = step; i < next; i++) {
        const problems = problemsAt(i);
        if (Object.keys(problems).length) {
          setErrors(problems);
          setStep(i);
          focusFirstError();
          return;
        }
      }
    }
    setErrors({});
    setServerMessage(null);
    setStep(next);
    window.scrollTo({ top: 0, behavior: "smooth" });
    window.setTimeout(() => headingRef.current?.focus({ preventScroll: true }), 50);
  }

  function focusFirstError() {
    window.setTimeout(() => document.querySelector<HTMLElement>(".rg-form [aria-invalid='true']")?.focus(), 30);
  }

  function pickLogo(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    e.target.value = "";
    if (!file) return;
    if (!LOGO_TYPES.includes(file.type)) { setErrors({ logo: l(C.badLogoType) }); return; }
    if (file.size > LOGO_MAX) { setErrors({ logo: l(C.badLogoSize) }); return; }
    setErrors({});
    setLogo(file);
  }

  async function create() {
    setBusy(true);
    setServerMessage(null);

    let res: { token: string; user: User; company: Company; otp: { code: string | null; identifier: string } };
    try {
      res = await api.post("/auth/register", {
        company_name: form.company_name.trim(),
        business_email: form.business_email.trim(),
        phone: form.phone.trim() || null,
        address: form.address.trim() || null,
        country: form.country,
        currency: form.currency,
        locale,
        name: form.name.trim(),
        email: form.email.trim(),
        password: form.password,
        password_confirmation: form.password_confirmation,
        plan_code: planCode,
      });
    } catch (err) {
      setBusy(false);
      setConfirming(false);
      if (err instanceof ApiError) {
        const fieldErrors = Object.fromEntries(Object.entries(err.errors).map(([k, v]) => [k, v[0]]));
        setErrors(fieldErrors);
        setServerMessage(Object.keys(fieldErrors).length ? l(C.fixErrors) : err.message);
        const steps = Object.keys(fieldErrors).map((k) => FIELD_STEP[k]).filter((n) => n !== undefined);
        if (steps.length) { setStep(Math.min(...steps)); focusFirstError(); }
      } else {
        setServerMessage(err instanceof Error ? err.message : String(err));
      }
      return;
    }

    applySession(res.token, res.user, res.company);

    const details = Object.fromEntries(Object.entries({
      trading_name: form.trading_name, tin: form.tin, registration_number: form.registration_number,
      contact_person: form.contact_person, contact_email: form.business_email, contact_phone: form.phone,
      city: form.city, region: form.region,
      primary_color: form.primary_color.toUpperCase(), secondary_color: form.secondary_color.toUpperCase(),
    }).map(([k, v]) => [k, v.trim()]).filter(([, v]) => v !== ""));

    let detailsState: Outcome["details"] = "ok";
    try {
      await api.put("/company", details);
    } catch {
      detailsState = "failed";
    }

    let logoState: Outcome["logo"] = "skipped";
    if (logo) {
      try {
        const body = new FormData();
        body.append("logo", logo, logo.name);
        await request("/company/logo", { method: "POST", form: body });
        logoState = "ok";
      } catch {
        logoState = "failed";
      }
    }

    const code = res.otp?.code ? `&code=${res.otp.code}` : "";
    setOutcome({
      details: detailsState,
      logo: logoState,
      company: res.company.name,
      verifyUrl: `/verify?identifier=${encodeURIComponent(res.otp.identifier)}&purpose=registration&next=onboarding${code}`,
    });
    setConfirming(false);
    setBusy(false);
    window.scrollTo({ top: 0 });
  }

  const current = STEPS[step];
  const onReview = step === STEPS.length - 1;
  const selectedPlan = plans.find((p) => p.code === planCode);
  const fe = (key: string) => errors[key];

  return (
    <div className="rg">
      <aside className="rg-rail">
        <Link href="/" className="rg-brand" aria-label="VouchFlow home"><VouchFlowMark size={32} /><span>VouchFlow</span></Link>
        <div className="rg-rail-body">
          <h2 className="rg-rail-title">{l(C.heroTitle)}</h2>
          <p className="rg-rail-sub">{l(C.heroSub)}</p>
          <ol className="rg-steps" aria-label="Registration steps">
            {STEPS.map((s, index) => {
              const state = outcome ? "done" : index === step ? "current" : index < step ? "done" : "pending";
              return (
                <li key={s.key} className="rg-step" data-state={state} aria-current={state === "current" ? "step" : undefined}>
                  <span className="rg-step-num tnum">{state === "done" ? <Icon name="ph-check" size={14} /> : String(index + 1).padStart(2, "0")}</span>
                  <span className="rg-step-text"><strong>{l(s.label)}</strong><span>{l(s.title)}</span></span>
                </li>
              );
            })}
          </ol>
        </div>
        <p className="rg-rail-foot"><Icon name="ph-lock-key" size={16} /> {locale === "sw" ? "Kila kampuni imetenganishwa kikamilifu." : "Every company is fully isolated from every other."}</p>
      </aside>

      <main className="rg-main">
        <div className="rg-topbar">
          <Link href="/" className="rg-brand rg-brand-mobile" aria-label="VouchFlow home"><VouchFlowMark size={28} /><span>VouchFlow</span></Link>
          <div className="rg-tools"><LanguageToggle /><ThemeToggle /></div>
        </div>

        {outcome ? (
          <section className="rg-card rg-done" aria-live="polite">
            <span className="rg-done-mark"><Icon name="ph-check" size={30} /></span>
            <h1>{l(C.doneTitle)}</h1>
            <p className="rg-done-company">{outcome.company}</p>
            <p className="rg-lede">{l(C.doneSub)}</p>
            <ul className="rg-outcomes">
              <li data-state="ok"><Icon name="ph-check-circle" size={20} /> {l(C.savedCompany)}</li>
              <li data-state={outcome.details}>
                <Icon name={outcome.details === "ok" ? "ph-check-circle" : "ph-warning-circle"} size={20} />
                <span>{l(C.savedDetails)}{outcome.details === "failed" && <small>{l(C.finishInSettings)}</small>}</span>
              </li>
              {outcome.logo !== "skipped" && (
                <li data-state={outcome.logo}>
                  <Icon name={outcome.logo === "ok" ? "ph-check-circle" : "ph-warning-circle"} size={20} />
                  <span>{l(C.savedLogo)}{outcome.logo === "failed" && <small>{l(C.finishInSettings)}</small>}</span>
                </li>
              )}
            </ul>
            <button type="button" className="btn btn-primary btn-lg rg-primary" onClick={() => router.push(outcome.verifyUrl)}>
              {l(C.verify)} <Icon name="ph-arrow-right" size={18} />
            </button>
          </section>
        ) : (
          <>
            <div className="rg-progress" aria-hidden="true">
              <div className="rg-progress-row">
                <span>{l(C.stepOf)} {step + 1} {l(C.of)} {STEPS.length}</span>
                <strong>{l(current.label)}</strong>
              </div>
              <div className="rg-progress-bar"><span style={{ width: `${((step + 1) / STEPS.length) * 100}%` }} /></div>
            </div>

            <form className="rg-card rg-form" noValidate
              onSubmit={(e) => { e.preventDefault(); if (onReview) setConfirming(true); else go(step + 1); }}>
              <header className="rg-head" key={current.key}>
                <p className="rg-eyebrow">{l(C.stepOf)} {step + 1} {l(C.of)} {STEPS.length} · {l(current.label)}</p>
                <h1 ref={headingRef} tabIndex={-1}>{l(current.title)}</h1>
                <p className="rg-lede">{l(current.sub)}</p>
              </header>

              {serverMessage && (
                <div className="vf-alert tone-bad rg-alert" role="alert">
                  <Icon name="ph-warning-circle" size={20} style={{ flex: "none" }} />
                  <div className="vf-alert-text">{serverMessage}</div>
                </div>
              )}

              <div className="rg-fields" key={`fields-${current.key}`}>
                {current.key === "company" && (
                  <>
                    <F id="company_name" label={l(C.companyName)} error={fe("company_name")} required>
                      <input id="company_name" className="input rg-input" value={form.company_name} onChange={set("company_name")}
                        placeholder={l(C.companyNamePh)} autoComplete="organization" aria-invalid={!!fe("company_name")} />
                    </F>
                    <F id="trading_name" label={l(C.tradingName)} hint={l(C.tradingHint)} error={fe("trading_name")}>
                      <input id="trading_name" className="input rg-input" value={form.trading_name} onChange={set("trading_name")} aria-invalid={!!fe("trading_name")} />
                    </F>
                    <div className="rg-row">
                      <F id="tin" label={l(C.tin)} hint={l(C.tinHint)} error={fe("tin")}>
                        <input id="tin" className="input rg-input tnum" value={form.tin} onChange={set("tin")} inputMode="numeric" placeholder="123-456-789" aria-invalid={!!fe("tin")} />
                      </F>
                      <F id="registration_number" label={l(C.regNo)} hint={l(C.regHint)} error={fe("registration_number")}>
                        <input id="registration_number" className="input rg-input" value={form.registration_number} onChange={set("registration_number")} placeholder="BRELA 145678" aria-invalid={!!fe("registration_number")} />
                      </F>
                    </div>
                    <div className="rg-row">
                      <F id="country" label={l(C.country)}>
                        <select id="country" className="input rg-input" value={form.country} onChange={set("country")}>
                          <option value="TZ">Tanzania</option><option value="KE">Kenya</option>
                          <option value="UG">Uganda</option><option value="RW">Rwanda</option><option value="ZA">South Africa</option>
                        </select>
                      </F>
                      <F id="currency" label={l(C.currency)}>
                        <select id="currency" className="input rg-input" value={form.currency} onChange={set("currency")}>
                          <option>TZS</option><option>KES</option><option>UGX</option><option>USD</option><option>EUR</option>
                        </select>
                      </F>
                    </div>
                  </>
                )}

                {current.key === "contact" && (
                  <>
                    <F id="contact_person" label={l(C.contactPerson)} error={fe("contact_person")} required>
                      <input id="contact_person" className="input rg-input" value={form.contact_person} onChange={set("contact_person")} autoComplete="name" aria-invalid={!!fe("contact_person")} />
                    </F>
                    <div className="rg-row">
                      <F id="business_email" label={l(C.email)} error={fe("business_email")} required>
                        <input id="business_email" type="email" inputMode="email" className="input rg-input" value={form.business_email} onChange={set("business_email")}
                          placeholder={l(C.emailPh)} autoComplete="email" autoCapitalize="none" aria-invalid={!!fe("business_email")} />
                      </F>
                      <F id="phone" label={l(C.phone)} error={fe("phone")}>
                        <input id="phone" type="tel" inputMode="tel" className="input rg-input" value={form.phone} onChange={set("phone")} placeholder="+255 7xx xxx xxx" autoComplete="tel" aria-invalid={!!fe("phone")} />
                      </F>
                    </div>
                    <F id="address" label={l(C.address)} error={fe("address")}>
                      <input id="address" className="input rg-input" value={form.address} onChange={set("address")} placeholder={l(C.addressPh)} autoComplete="street-address" aria-invalid={!!fe("address")} />
                    </F>
                    <div className="rg-row">
                      <F id="city" label={l(C.city)} error={fe("city")}>
                        <input id="city" className="input rg-input" value={form.city} onChange={set("city")} autoComplete="address-level2" aria-invalid={!!fe("city")} />
                      </F>
                      <F id="region" label={l(C.region)} error={fe("region")}>
                        <input id="region" className="input rg-input" list="rg-regions" value={form.region} onChange={set("region")} autoComplete="address-level1" aria-invalid={!!fe("region")} />
                        <datalist id="rg-regions">{REGIONS.map((r) => <option key={r} value={r} />)}</datalist>
                      </F>
                    </div>
                  </>
                )}

                {current.key === "branding" && (
                  <>
                    <div className="field">
                      <span className="rg-label">{l(C.logo)}</span>
                      <div className="rg-logo" data-invalid={fe("logo") ? "true" : undefined}>
                        <span className="rg-logo-box">
                          {logoPreview
                            // eslint-disable-next-line @next/next/no-img-element
                            ? <img src={logoPreview} alt="" />
                            : <Icon name="ph-image-square" size={28} />}
                        </span>
                        <div className="rg-logo-text">
                          <strong>{logo ? logo.name : l(C.chooseLogo)}</strong>
                          <span>{l(C.logoHint)}</span>
                          <div className="rg-logo-actions">
                            <label className="btn btn-secondary btn-sm">
                              <Icon name="ph-upload-simple" size={15} /> {logo ? l(C.replace) : l(C.chooseLogo)}
                              <input type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={pickLogo} />
                            </label>
                            {logo && <button type="button" className="btn btn-ghost btn-sm" onClick={() => setLogo(null)}>{l(C.remove)}</button>}
                          </div>
                        </div>
                      </div>
                      {fe("logo") && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {fe("logo")}</div>}
                    </div>

                    <div className="rg-row">
                      <ColourField id="primary_color" label={l(C.primary)} value={form.primary_color} error={fe("primary_color")}
                        onChange={(v) => setForm((f) => ({ ...f, primary_color: v }))} />
                      <ColourField id="secondary_color" label={l(C.secondary)} value={form.secondary_color} error={fe("secondary_color")}
                        onChange={(v) => setForm((f) => ({ ...f, secondary_color: v }))} />
                    </div>

                    <div className="rg-preview" aria-label={l(C.preview)}>
                      <span className="rg-eyebrow">{l(C.preview)}</span>
                      <div className="rg-preview-sheet" style={{ borderTopColor: HEX.test(form.primary_color) ? form.primary_color : undefined }}>
                        <span className="rg-preview-logo" style={{ background: logoPreview ? "transparent" : (HEX.test(form.secondary_color) ? form.secondary_color : undefined) }}>
                          {logoPreview
                            // eslint-disable-next-line @next/next/no-img-element
                            ? <img src={logoPreview} alt="" />
                            : initials(form.trading_name || form.company_name)}
                        </span>
                        <span className="rg-preview-name">
                          <strong>{form.trading_name || form.company_name || "—"}</strong>
                          <span>{[form.city, form.region].filter(Boolean).join(", ") || l(C.previewVoucher)}</span>
                        </span>
                        <span className="rg-preview-tag" style={{ color: HEX.test(form.primary_color) ? form.primary_color : undefined }}>{l(C.previewVoucher)}</span>
                      </div>
                    </div>
                  </>
                )}

                {current.key === "admin" && (
                  <>
                    <F id="name" label={l(C.adminName)} error={fe("name")} required>
                      <input id="name" className="input rg-input" value={form.name} onChange={set("name")} autoComplete="name" aria-invalid={!!fe("name")} />
                    </F>
                    <F id="email" label={l(C.adminEmail)} hint={l(C.adminEmailHint)} error={fe("email")} required>
                      <input id="email" type="email" inputMode="email" className="input rg-input" value={form.email} onChange={set("email")} autoComplete="username" autoCapitalize="none" aria-invalid={!!fe("email")} />
                    </F>
                    <div className="rg-row">
                      <F id="password" label={l(C.password)} hint={l(C.passwordHint)} error={fe("password")} required>
                        <div className="rg-password">
                          <input id="password" type={reveal ? "text" : "password"} className="input rg-input" value={form.password} onChange={set("password")} autoComplete="new-password" aria-invalid={!!fe("password")} />
                          <button type="button" className="rg-reveal" onClick={() => setReveal((v) => !v)} aria-pressed={reveal} aria-label={reveal ? l(C.hide) : l(C.show)}>
                            <Icon name={reveal ? "ph-eye-slash" : "ph-eye"} size={18} />
                          </button>
                        </div>
                        <PasswordMeter value={form.password} />
                      </F>
                      <F id="password_confirmation" label={l(C.confirm)} error={fe("password_confirmation")} required>
                        <input id="password_confirmation" type={reveal ? "text" : "password"} className="input rg-input" value={form.password_confirmation} onChange={set("password_confirmation")} autoComplete="new-password" aria-invalid={!!fe("password_confirmation")} />
                      </F>
                    </div>
                  </>
                )}

                {current.key === "review" && (
                  <>
                    <ReviewBlock title={l(STEPS[0].label)} onEdit={() => go(0)} editLabel={l(C.edit)} rows={[
                      [l(C.companyName), form.company_name], [l(C.tradingName), form.trading_name],
                      [l(C.tin), form.tin], [l(C.regNo), form.registration_number], [`${l(C.country)} · ${l(C.currency)}`, `${form.country} · ${form.currency}`],
                    ]} empty={l(C.notProvided)} />
                    <ReviewBlock title={l(STEPS[1].label)} onEdit={() => go(1)} editLabel={l(C.edit)} rows={[
                      [l(C.contactPerson), form.contact_person], [l(C.email), form.business_email], [l(C.phone), form.phone],
                      [l(C.address), [form.address, form.city, form.region].filter(Boolean).join(", ")],
                    ]} empty={l(C.notProvided)} />
                    <ReviewBlock title={l(STEPS[2].label)} onEdit={() => go(2)} editLabel={l(C.edit)} rows={[
                      [l(C.logo), logo ? logo.name : ""],
                      [l(C.primary), <Swatch key="p" value={form.primary_color} />],
                      [l(C.secondary), <Swatch key="s" value={form.secondary_color} />],
                    ]} empty={l(C.none)} />
                    <ReviewBlock title={l(STEPS[3].label)} onEdit={() => go(3)} editLabel={l(C.edit)} rows={[
                      [l(C.adminName), form.name], [l(C.adminEmail), form.email], [l(C.password), "••••••••"],
                    ]} empty={l(C.notProvided)} />

                    {plans.length > 0 && (
                      <fieldset className="rg-plans">
                        <legend className="rg-label">{l(C.plan)}</legend>
                        {plans.map((plan) => (
                          <label key={plan.id} className="rg-plan" data-selected={planCode === plan.code || undefined}>
                            <input type="radio" name="plan" value={plan.code} checked={planCode === plan.code} onChange={() => setPlanCode(plan.code)} />
                            <span className="rg-plan-dot" aria-hidden="true" />
                            <span className="rg-plan-text">
                              <strong>{plan.label}</strong>
                              <span>{plan.blurb}</span>
                            </span>
                            <span className="rg-plan-price tnum">
                              <span>{plan.price > 0 ? <>{money(plan.price, plan.currency)} <small>{l(C.perMonth)}</small></> : l(C.custom)}</span>
                              <small>{plan.trial_days} {l(C.trial)}</small>
                            </span>
                          </label>
                        ))}
                      </fieldset>
                    )}
                  </>
                )}
              </div>

              <div className="rg-nav">
                {step > 0
                  ? <button type="button" className="btn btn-secondary btn-lg" onClick={() => go(step - 1)}><Icon name="ph-arrow-left" size={17} /> {l(C.back)}</button>
                  : <span />}
                <button type="submit" className="btn btn-primary btn-lg rg-primary">
                  {onReview ? <><Icon name="ph-buildings" size={18} /> {l(C.create)}</> : <>{l(C.continue)} <Icon name="ph-arrow-right" size={17} /></>}
                </button>
              </div>
            </form>

            <p className="rg-alt">{l(C.already)} <Link href="/login">{l(C.signIn)}</Link></p>
          </>
        )}
      </main>

      <Dialog
        open={confirming}
        title={l(C.confirmTitle)}
        sub={l(C.confirmSub)}
        icon="ph-buildings"
        tone="info"
        busy={busy}
        onClose={() => setConfirming(false)}
        summary={[
          { label: l(C.companyName), value: form.trading_name ? `${form.company_name} (${form.trading_name})` : form.company_name },
          { label: l(C.adminEmail), value: form.email },
          { label: l(C.plan), value: selectedPlan ? `${selectedPlan.label} · ${selectedPlan.trial_days} ${l(C.trial)}` : planCode },
        ]}
        actions={
          <>
            <button type="button" className="btn btn-secondary" onClick={() => setConfirming(false)} disabled={busy}>{l(C.cancel)}</button>
            <button type="button" className="btn btn-primary" onClick={() => void create()} disabled={busy}>
              {busy ? <Spinner label={l(C.creating)} /> : <><Icon name="ph-check" size={17} /> {l(C.create)}</>}
            </button>
          </>
        }
      />
    </div>
  );
}

function F({ id, label, hint, error, required, children }: { id: string; label: string; hint?: string; error?: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="field rg-field">
      <label htmlFor={id}>{label}{required && <span className="vf-required" aria-hidden="true"> *</span>}</label>
      {children}
      {error
        ? <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error}</div>
        : hint && <div className="field-hint">{hint}</div>}
    </div>
  );
}

function ColourField({ id, label, value, error, onChange }: { id: string; label: string; value: string; error?: string; onChange: (v: string) => void }) {
  return (
    <F id={id} label={label} error={error}>
      <div className="rg-colour">
        <input type="color" aria-label={label} value={HEX.test(value) ? value : "#000000"} onChange={(e) => onChange(e.target.value.toUpperCase())} />
        <input id={id} className="input rg-input tnum" value={value} maxLength={7} aria-invalid={!!error}
          onChange={(e) => { const v = e.target.value.trim(); onChange(v.startsWith("#") ? v.toUpperCase() : `#${v.toUpperCase()}`); }} />
      </div>
    </F>
  );
}

function Swatch({ value }: { value: string }) {
  return <span className="rg-swatch"><span style={{ background: value }} /> <span className="tnum">{value}</span></span>;
}

function ReviewBlock({ title, rows, onEdit, editLabel, empty }: { title: string; rows: [string, React.ReactNode][]; onEdit: () => void; editLabel: string; empty: string }) {
  return (
    <section className="rg-review">
      <div className="rg-review-head">
        <h2>{title}</h2>
        <button type="button" className="btn btn-ghost btn-sm" onClick={onEdit}><Icon name="ph-pencil-simple" size={15} /> {editLabel}</button>
      </div>
      <dl>
        {rows.map(([label, value]) => (
          <div key={label}>
            <dt>{label}</dt>
            <dd>{value === "" || value == null ? <span className="rg-empty">{empty}</span> : value}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function PasswordMeter({ value }: { value: string }) {
  const score = !value ? 0 : [value.length >= 8, value.length >= 12, /[A-Z]/.test(value) && /[a-z]/.test(value), /\d/.test(value) && /[^A-Za-z0-9]/.test(value)].filter(Boolean).length;
  return (
    <div className="rg-meter" data-score={score} aria-hidden="true">
      {[1, 2, 3, 4].map((n) => <span key={n} data-on={score >= n || undefined} />)}
    </div>
  );
}

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase()).join("") || "VF";
}
