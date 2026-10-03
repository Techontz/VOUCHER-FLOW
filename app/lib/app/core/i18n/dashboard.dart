// Strings for the dashboard screens (English and Swahili), merged into
// VfTranslations. Keys are prefixed with 'dashboard.' to stay out of each
// other's way; wording follows the web client's lib/i18n.ts.
//
// The API's own stable keys (dash.stat.*, dash.banner.*, dash.panel.* …) live
// in translations.dart; these are the page's own words, plus the inbox.
const Map<String, String> dashboardEn = {
  // — page —
  'dashboard.loading': 'Loading',
  'dashboard.payNow': 'Pay now',
  'dashboard.changePlan': 'Change plan',
  'dashboard.trialEnds': 'Trial ends',
  'dashboard.expired': 'Subscription expired',
  'dashboard.expiredBody':
      'Renew your subscription to continue creating and approving vouchers. Your data stays exactly where it is.',
  'dashboard.createVoucher': 'Create voucher',
  'dashboard.needsYourAction': 'Needs your action',
  'dashboard.approveSelected': 'Approve selected…',
  'dashboard.total': 'Total',
  'dashboard.stalledNote': 'These have not moved in three days or more.',
  'dashboard.clearedNote':
      'Acting on a voucher moves it to whoever is next — it will leave this list.',
  'dashboard.companiesNeedingAttention': 'Companies needing attention',
  'dashboard.all': 'All',
  'dashboard.recentPayments': 'Recent payments',
  'dashboard.recentCompanies': 'Recent companies',
  'dashboard.byStage': 'Where the work is sitting',
  'dashboard.users': 'users',
  'dashboard.vouchers': 'vouchers',
  'dashboard.invoice': 'Invoice',
  'dashboard.voucherValue': 'Voucher value',
  'dashboard.last7Months': 'Last 7 months',
  'dashboard.bank': 'Bank',
  'dashboard.cash': 'Cash',

  // — home: hero and quick actions —
  'dashboard.hero.waiting': 'Waiting for you',
  'dashboard.hero.clear': 'All clear',
  'dashboard.hero.review': 'Review',
  'dashboard.quick.alerts': 'Alerts',
  'dashboard.quick.me': 'Profile',
  'dashboard.stalled': 'Stalled',
  'dashboard.manage': 'Manage',

  // — the one next step on a queued voucher —
  'dashboard.cta.recordPayment': 'Record payment',
  'dashboard.cta.reviewApprove': 'Review & approve',
  'dashboard.cta.reviewSign': 'Review & sign',
  'dashboard.cta.submitSigned': 'Submit signed voucher',
  'dashboard.cta.reviseVoucher': 'Revise voucher',
  'dashboard.cta.continueDraft': 'Continue draft',

  // — relative time ("2 hours ago") —
  'dashboard.time.now': 'now',
  'dashboard.time.minute': '1 minute ago',
  'dashboard.time.minutes': '@n minutes ago',
  'dashboard.time.hour': '1 hour ago',
  'dashboard.time.hours': '@n hours ago',
  'dashboard.time.yesterday': 'yesterday',
  'dashboard.time.days': '@n days ago',
  'dashboard.time.lastWeek': 'last week',
  'dashboard.time.weeks': '@n weeks ago',
  'dashboard.time.lastMonth': 'last month',
  'dashboard.time.months': '@n months ago',

  // — notifications —
  'dashboard.inbox.title': 'Notifications',
  'dashboard.inbox.unread': '@count unread',
  'dashboard.inbox.empty': 'You are all caught up',
  'dashboard.inbox.emptyBody':
      'New approvals, decisions and billing events appear here.',
  'dashboard.inbox.markAllRead': 'Mark all read',
  'dashboard.inbox.today': 'Today',
  'dashboard.inbox.yesterday': 'Yesterday',
  'dashboard.inbox.earlier': 'Earlier',
  'dashboard.inbox.unreadMark': 'Unread',
  'dashboard.inbox.caughtUp': 'All caught up',
  'dashboard.inbox.markedRead': '@count notifications marked as read.',
  'dashboard.inbox.updateFailed': 'Could not update notifications',
};

const Map<String, String> dashboardSw = {
  // — page —
  'dashboard.loading': 'Inapakia',
  'dashboard.payNow': 'Lipa sasa',
  'dashboard.changePlan': 'Badilisha mpango',
  'dashboard.trialEnds': 'Jaribio linaisha',
  'dashboard.expired': 'Usajili umeisha',
  'dashboard.expiredBody':
      'Huisha usajili wako ili kuendelea kutengeneza na kuidhinisha vocha. Data yako inabaki ilipo.',
  'dashboard.createVoucher': 'Tengeneza vocha',
  'dashboard.needsYourAction': 'Inahitaji hatua yako',
  'dashboard.approveSelected': 'Idhinisha zilizochaguliwa…',
  'dashboard.total': 'Jumla',
  'dashboard.stalledNote': 'Hizi hazijasogea kwa siku tatu au zaidi.',
  'dashboard.clearedNote':
      'Kushughulikia vocha kunaipeleka kwa anayefuata — itaondoka kwenye orodha hii.',
  'dashboard.companiesNeedingAttention': 'Kampuni zinazohitaji umakini',
  'dashboard.all': 'Zote',
  'dashboard.recentPayments': 'Malipo ya hivi karibuni',
  'dashboard.recentCompanies': 'Kampuni za hivi karibuni',
  'dashboard.byStage': 'Kazi ilipo',
  'dashboard.users': 'watumiaji',
  'dashboard.vouchers': 'vocha',
  'dashboard.invoice': 'Ankara',
  'dashboard.voucherValue': 'Thamani ya vocha',
  'dashboard.last7Months': 'Miezi 7 iliyopita',
  'dashboard.bank': 'Benki',
  'dashboard.cash': 'Taslimu',

  // — home: hero and quick actions —
  'dashboard.hero.waiting': 'Zinakusubiri',
  'dashboard.hero.clear': 'Hakuna kinachosubiri',
  'dashboard.hero.review': 'Kagua',
  'dashboard.quick.alerts': 'Arifa',
  'dashboard.quick.me': 'Wasifu',
  'dashboard.stalled': 'Zimekwama',
  'dashboard.manage': 'Simamia',

  // — the one next step on a queued voucher —
  'dashboard.cta.recordPayment': 'Rekodi malipo',
  'dashboard.cta.reviewApprove': 'Kagua na uidhinishe',
  'dashboard.cta.reviewSign': 'Pitia na saini',
  'dashboard.cta.submitSigned': 'Tuma vocha iliyosainiwa',
  'dashboard.cta.reviseVoucher': 'Rekebisha vocha',
  'dashboard.cta.continueDraft': 'Endelea na rasimu',

  // — relative time —
  'dashboard.time.now': 'sasa hivi',
  'dashboard.time.minute': 'dakika 1 iliyopita',
  'dashboard.time.minutes': 'dakika @n zilizopita',
  'dashboard.time.hour': 'saa 1 iliyopita',
  'dashboard.time.hours': 'saa @n zilizopita',
  'dashboard.time.yesterday': 'jana',
  'dashboard.time.days': 'siku @n zilizopita',
  'dashboard.time.lastWeek': 'wiki iliyopita',
  'dashboard.time.weeks': 'wiki @n zilizopita',
  'dashboard.time.lastMonth': 'mwezi uliopita',
  'dashboard.time.months': 'miezi @n iliyopita',

  // — notifications —
  'dashboard.inbox.title': 'Taarifa',
  'dashboard.inbox.unread': '@count hazijasomwa',
  'dashboard.inbox.empty': 'Umeshughulikia yote',
  'dashboard.inbox.emptyBody':
      'Idhini mpya, maamuzi na matukio ya malipo huonekana hapa.',
  'dashboard.inbox.markAllRead': 'Weka zote kama zilizosomwa',
  'dashboard.inbox.today': 'Leo',
  'dashboard.inbox.yesterday': 'Jana',
  'dashboard.inbox.earlier': 'Awali',
  'dashboard.inbox.unreadMark': 'Haijasomwa',
  'dashboard.inbox.caughtUp': 'Umeshughulikia yote',
  'dashboard.inbox.markedRead': 'Taarifa @count zimewekwa kama zilizosomwa.',
  'dashboard.inbox.updateFailed': 'Imeshindwa kusasisha taarifa',
};
