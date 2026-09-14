/**
 * Words for the public site, in English and Swahili.
 *
 * Kept beside the landing page rather than in the app dictionary: this is
 * marketing prose, long and section-shaped, and none of it is reused inside
 * the product. Every entry is [English, Swahili].
 */

export type L = readonly [string, string];

export const pick = (entry: L, locale: "en" | "sw") => (locale === "sw" ? entry[1] : entry[0]);

export const NAV: { href: string; label: L }[] = [
  { href: "#workflow", label: ["Workflow", "Mtiririko"] },
  { href: "#vouchers", label: ["Vouchers", "Vocha"] },
  { href: "#controls", label: ["Controls", "Udhibiti"] },
  { href: "#audit", label: ["Audit", "Ukaguzi"] },
  { href: "#reports", label: ["Reports", "Ripoti"] },
  { href: "#pricing", label: ["Pricing", "Bei"] },
];

export const HERO = {
  eyebrow: ["Corporate voucher management & approval", "Usimamizi na idhini ya vocha za kampuni"] as L,
  line1: ["From request to payment,", "Kutoka ombi hadi malipo,"] as L,
  line2: ["without the paperwork.", "bila makaratasi."] as L,
  sub: [
    "Create, review, sign, approve and pay company vouchers in one controlled workflow — with complete visibility and an audit trail at every step.",
    "Andaa, kagua, saini, idhinisha na lipa vocha za kampuni katika mtiririko mmoja wenye udhibiti — ukiona kila hatua, na kumbukumbu kamili ya ukaguzi.",
  ] as L,
  getStarted: ["Get started", "Anza sasa"] as L,
  signIn: ["Sign in", "Ingia"] as L,
  proof: [
    ["Bank & cash vouchers", "Vocha za benki na taslimu"],
    ["Digital signatures", "Saini za kidijitali"],
    ["Audit trail on every step", "Kumbukumbu kila hatua"],
  ] as L[],
};

export const MOCK = {
  paymentVoucher: ["Payment voucher", "Vocha ya malipo"] as L,
  awaitingCeo: ["Awaiting CEO approval", "Inasubiri idhini ya Mkurugenzi"] as L,
  payee: ["Payee", "Mlipwaji"] as L,
  purpose: ["Purpose", "Madhumuni"] as L,
  requestedBy: ["Requested by", "Imeombwa na"] as L,
  prepared: ["Prepared", "Imeandaliwa"] as L,
  hodSigned: ["HOD signed", "HOD amesaini"] as L,
  ceoApproval: ["CEO approval", "Idhini ya Mkurugenzi"] as L,
  financePayment: ["Finance payment", "Malipo — Fedha"] as L,
  waiting: ["Waiting", "Inasubiri"] as L,
  next: ["Next", "Ifuatayo"] as L,
  approvalRequired: ["Approval required", "Idhini inahitajika"] as L,
  waitingForYou: ["is waiting for your decision", "inasubiri uamuzi wako"] as L,
  approve: ["Approve", "Idhinisha"] as L,
  review: ["Review", "Kagua"] as L,
  signed: ["Signed", "Imesainiwa"] as L,
  illustration: ["Illustration of a voucher awaiting approval in VouchFlow", "Mfano wa vocha inayosubiri idhini kwenye VouchFlow"] as L,
};

export const STATEMENT = {
  lines: [["Every voucher.", "Kila vocha."], ["Every approval.", "Kila idhini."], ["Every payment.", "Kila malipo."]] as L[],
  closing: ["One controlled workflow.", "Mtiririko mmoja wenye udhibiti."] as L,
  pillars: [
    {
      icon: "ph-arrows-down-up",
      title: ["Nothing moves on a handshake", "Hakuna kinachosonga kwa mdomo"],
      body: [
        "A voucher reaches the next person only when the step before it is complete — signed, approved, or sent back with a reason.",
        "Vocha humfikia anayefuata pale tu hatua iliyotangulia imekamilika — imesainiwa, imeidhinishwa, au imerudishwa na sababu.",
      ],
    },
    {
      icon: "ph-user-focus",
      title: ["The right person, every time", "Mtu sahihi, kila mara"],
      body: [
        "Every step belongs to a role your company chose, so each voucher reaches HOD, CEO or Finance in the order you set.",
        "Kila hatua ni ya jukumu ambalo kampuni yako imechagua, hivyo vocha humfikia HOD, Mkurugenzi au Fedha kwa mpangilio uliouweka.",
      ],
    },
    {
      icon: "ph-seal-check",
      title: ["Proof, not promises", "Ushahidi, si ahadi"],
      body: [
        "Signatures, documents and timestamps stay with the voucher, from the first draft to the payment reference.",
        "Saini, nyaraka na nyakati hubaki na vocha, kuanzia rasimu ya kwanza hadi kumbukumbu ya malipo.",
      ],
    },
  ] as { icon: string; title: L; body: L }[],
};

export const WORKFLOW = {
  eyebrow: ["Workflow", "Mtiririko"] as L,
  title: ["How a voucher moves", "Jinsi vocha inavyosonga"] as L,
  sub: [
    "Six clear stages. Your company decides who acts at each one, and VouchFlow makes sure it happens in that order.",
    "Hatua sita zilizo wazi. Kampuni yako inaamua nani anatenda katika kila moja, na VouchFlow inahakikisha zinafuata mpangilio huo.",
  ] as L,
  stages: [
    { icon: "ph-note-pencil", title: ["Create", "Andaa"], role: ["Employee", "Mfanyakazi"], body: ["Raises the voucher with the payee, amount and supporting documents.", "Anaandaa vocha na mlipwaji, kiasi na nyaraka za kuthibitisha."] },
    { icon: "ph-magnifying-glass", title: ["Review", "Kagua"], role: ["Head of department", "Mkuu wa idara"], body: ["Checks the request against what the department actually needs.", "Anakagua ombi dhidi ya mahitaji halisi ya idara."] },
    { icon: "ph-signature", title: ["Sign", "Saini"], role: ["HOD", "HOD"], body: ["Signs digitally to vouch for the request before it goes up.", "Anasaini kidijitali kuthibitisha ombi kabla halijapanda juu."] },
    { icon: "ph-seal-check", title: ["Approve", "Idhinisha"], role: ["CEO / Manager", "Mkurugenzi / Meneja"], body: ["Decides: approve, reject, or send back for changes.", "Anaamua: kuidhinisha, kukataa, au kurudisha kwa marekebisho."] },
    { icon: "ph-hand-coins", title: ["Pay", "Lipa"], role: ["Finance / Cashier", "Fedha / Mhazini"], body: ["Releases the funds and records the payment reference.", "Anatoa fedha na kurekodi kumbukumbu ya malipo."] },
    { icon: "ph-check-circle", title: ["Complete", "Kamilika"], role: ["On record", "Kwenye kumbukumbu"], body: ["Paid, filed, and printable as a signed A4 voucher.", "Imelipwa, imehifadhiwa, na inachapishwa kama vocha ya A4 iliyosainiwa."] },
  ] as { icon: string; title: L; role: L; body: L }[],
};

export type VoucherTab = "payment" | "cash" | "bank" | "attachments" | "signatures";

export const VOUCHERS = {
  eyebrow: ["Voucher management", "Usimamizi wa vocha"] as L,
  title: ["Every kind of voucher, properly documented.", "Kila aina ya vocha, ikiwa na nyaraka kamili."] as L,
  sub: [
    "Raise the voucher your payment needs, attach the evidence, and sign it — all in one place, in the format your auditors expect.",
    "Andaa vocha inayohitajika kwa malipo yako, ambatisha ushahidi, na uisaini — yote mahali pamoja, katika muundo wanaoutarajia wakaguzi.",
  ] as L,
  tabs: [
    { key: "payment", icon: "ph-receipt", title: ["Payment vouchers", "Vocha za malipo"], body: ["The standard request to pay a supplier, a contractor or a member of staff — numbered automatically for each company.", "Ombi la kawaida la kumlipa msambazaji, mkandarasi au mfanyakazi — lenye namba inayotolewa kiotomatiki kwa kila kampuni."] },
    { key: "cash", icon: "ph-money", title: ["Cash vouchers", "Vocha za taslimu"], body: ["Notes released from a petty cash float, with the float named and the receipt recorded when the cash is handed over.", "Fedha taslimu kutoka akiba ndogo, ikitajwa akiba husika na risiti ikirekodiwa fedha zinapokabidhiwa."] },
    { key: "bank", icon: "ph-bank", title: ["Bank vouchers", "Vocha za benki"], body: ["Transfers and cheques with the payee's bank, account and branch on the voucher, and your company's account it is drawn on.", "Uhamisho na hundi zenye benki, akaunti na tawi la mlipwaji kwenye vocha, pamoja na akaunti ya kampuni inayolipa."] },
    { key: "attachments", icon: "ph-paperclip", title: ["Attachments", "Viambatisho"], body: ["Invoices, quotations and receipts travel with the voucher, stored privately for your company alone.", "Ankara, nukuu na risiti huambatana na vocha, zikihifadhiwa kwa faragha kwa ajili ya kampuni yako pekee."] },
    { key: "signatures", icon: "ph-signature", title: ["Digital signatures", "Saini za kidijitali"], body: ["Draw or upload a signature once, confirm it at each step, and see it printed on the A4 voucher.", "Chora au pakia saini mara moja, ithibitishe katika kila hatua, na uione ikichapishwa kwenye vocha ya A4."] },
  ] as { key: VoucherTab; icon: string; title: L; body: L }[],
};

export const CONTROLS = {
  eyebrow: ["Approval controls", "Udhibiti wa idhini"] as L,
  title: ["Your approval rules, enforced on every voucher.", "Kanuni zako za idhini, zikitekelezwa kwenye kila vocha."] as L,
  sub: [
    "Build the route once. Decide who signs, who approves and who pays — and when a larger amount needs one more decision.",
    "Jenga njia mara moja. Amua nani anasaini, nani anaidhinisha na nani analipa — na lini kiasi kikubwa kinahitaji uamuzi mmoja zaidi.",
  ] as L,
  items: [
    { icon: "ph-flow-arrow", title: ["Configurable workflows", "Mitiririko inayobadilika"], body: ["Add, remove and reorder steps without calling a developer.", "Ongeza, ondoa na panga hatua bila kumwita msanidi."] },
    { icon: "ph-user-gear", title: ["Role permissions", "Ruhusa kwa majukumu"], body: ["Each step says exactly what that role may do: sign, approve, reject, pay.", "Kila hatua inaeleza jukumu linaweza kufanya nini: kusaini, kuidhinisha, kukataa, kulipa."] },
    { icon: "ph-signature", title: ["HOD signatures", "Saini za HOD"], body: ["Heads of department vouch for requests before they go up.", "Wakuu wa idara huthibitisha maombi kabla hayajapanda."] },
    { icon: "ph-seal-check", title: ["CEO & manager approvals", "Idhini za Mkurugenzi na meneja"], body: ["The final decision sits with the people accountable for it.", "Uamuzi wa mwisho uko kwa wanaowajibika nao."] },
    { icon: "ph-hand-coins", title: ["Finance payment", "Malipo kupitia Fedha"], body: ["Only an approved voucher reaches the payment queue.", "Vocha iliyoidhinishwa pekee ndiyo hufika kwenye foleni ya malipo."] },
    { icon: "ph-scales", title: ["Amount-based rules", "Kanuni kwa kiasi"], body: ["Steps can apply only above or below the amounts you choose.", "Hatua zinaweza kutumika juu au chini ya kiasi unachochagua."] },
  ] as { icon: string; title: L; body: L }[],
};

export const AUDIT = {
  eyebrow: ["Audit & visibility", "Ukaguzi na uwazi"] as L,
  title: ["A complete record of who did what, and when.", "Kumbukumbu kamili ya nani alifanya nini, na lini."] as L,
  sub: [
    "Every voucher carries its own history. When an auditor asks, the answer is already written down.",
    "Kila vocha hubeba historia yake. Mkaguzi anapouliza, jibu tayari limeandikwa.",
  ] as L,
  items: [
    ["Who prepared it", "Nani aliiandaa"], ["Who signed it", "Nani aliisaini"], ["Who approved it", "Nani aliidhinisha"],
    ["Who paid it", "Nani alilipa"], ["The exact date and time", "Tarehe na saa kamili"], ["Every attachment", "Kila kiambatisho"],
    ["Full status history", "Historia kamili ya hali"],
  ] as L[],
};

export const COMPANIES = {
  eyebrow: ["Company management", "Usimamizi wa kampuni"] as L,
  title: ["One platform. Every company kept apart.", "Jukwaa moja. Kila kampuni ikiwa peke yake."] as L,
  sub: [
    "Run each company with its own people, departments, branding and approval routes — and nothing ever crosses between them.",
    "Endesha kila kampuni na watu wake, idara, chapa na njia zake za idhini — na hakuna kinachovuka kati yao.",
  ] as L,
  items: [
    { icon: "ph-buildings", title: ["Multi-company", "Kampuni nyingi"], body: ["Each company is its own workspace with its own numbering.", "Kila kampuni ina eneo lake na mfuatano wake wa namba."] },
    { icon: "ph-tree-structure", title: ["Departments", "Idara"], body: ["Heads, managers and cost centres for every department.", "Wakuu, mameneja na vituo vya gharama kwa kila idara."] },
    { icon: "ph-users-three", title: ["Users", "Watumiaji"], body: ["Invite the team and give each person the role they need.", "Alika timu na mpe kila mtu jukumu analohitaji."] },
    { icon: "ph-palette", title: ["Company branding", "Chapa ya kampuni"], body: ["Your logo and colours on screen and on the printed voucher.", "Nembo na rangi zako kwenye skrini na kwenye vocha iliyochapishwa."] },
    { icon: "ph-flow-arrow", title: ["Company-specific workflows", "Mitiririko ya kila kampuni"], body: ["Each company approves the way its own policy says.", "Kila kampuni huidhinisha kwa mujibu wa sera yake."] },
    { icon: "ph-lock-key", title: ["Tenant isolation", "Utenganisho kamili"], body: ["One company can never see another's vouchers or files.", "Kampuni moja haiwezi kuona vocha au faili za nyingine."] },
  ] as { icon: string; title: L; body: L }[],
};

export const REPORTS = {
  eyebrow: ["Reports", "Ripoti"] as L,
  title: ["Know where the money is going.", "Jua fedha zinakokwenda."] as L,
  sub: [
    "See what is waiting, what was approved and what was paid — by department, by period, by status — and take it with you.",
    "Ona kinachosubiri, kilichoidhinishwa na kilicholipwa — kwa idara, kipindi na hali — na uondoke nacho.",
  ] as L,
  items: [
    { icon: "ph-receipt", title: ["Voucher reports", "Ripoti za vocha"] },
    { icon: "ph-money", title: ["Payment reports", "Ripoti za malipo"] },
    { icon: "ph-seal-check", title: ["Approval reports", "Ripoti za idhini"] },
    { icon: "ph-clock-counter-clockwise", title: ["Audit logs", "Kumbukumbu za ukaguzi"] },
    { icon: "ph-export", title: ["Export & print", "Hamisha na chapisha"] },
  ] as { icon: string; title: L }[],
};

export const FINAL = {
  title: ["Bring every financial request into one clear workflow.", "Leta kila ombi la fedha katika mtiririko mmoja ulio wazi."] as L,
  sub: [
    "Set up your company, invite your team, and send your first voucher for approval.",
    "Sajili kampuni yako, alika timu yako, na tuma vocha yako ya kwanza kwa idhini.",
  ] as L,
};

export const FOOTER = {
  tagline: ["Corporate voucher management and approval.", "Usimamizi na idhini ya vocha za kampuni."] as L,
  product: ["Product", "Bidhaa"] as L,
  account: ["Account", "Akaunti"] as L,
  register: ["Register your company", "Sajili kampuni yako"] as L,
  rights: ["Vouchers, signatures and payments — on the record.", "Vocha, saini na malipo — kwenye kumbukumbu."] as L,
};
