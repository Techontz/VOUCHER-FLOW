// Strings for the profile screens (English and Swahili), merged into
// VfTranslations. Keys are prefixed with 'profile.' to stay out of each
// other's way; wording follows the web client's lib/i18n.ts.
//
// profile.title / signature / language / changePassword / currentPassword /
// newPassword / confirmPassword are in translations.dart and reused.
const Map<String, String> profileEn = {
  // — tabs —
  'profile.tab.details': 'Personal details',
  'profile.tab.signature': 'Signature',
  'profile.tab.security': 'Change password',
  'profile.tab.appearance': 'Appearance & language',

  // — personal details —
  'profile.details.title': 'Personal details',
  'profile.details.body':
      'How colleagues see you on vouchers, comments and the approval trail.',
  'profile.fullName': 'Full name',
  'profile.email': 'Email',
  'profile.emailHint': 'Contact your administrator to change your address',
  'profile.phone': 'Phone',
  'profile.jobTitle': 'Job title',
  'profile.photo': 'Photo',
  'profile.choosePhoto': 'Choose photo',
  'profile.noPhoto': 'No file chosen',
  'profile.photoTooLarge': 'The photo must be 2 MB or smaller.',
  'profile.saveChanges': 'Save changes',
  'profile.updated': 'Profile updated',
  'profile.updateFailed': 'Could not update your profile',
  'profile.required': 'This is required.',

  // — signature —
  'profile.signatureBody':
      'Your saved signature is offered whenever you sign a voucher, and is printed on the PDF.',
  'profile.sig.draw': 'Draw',
  'profile.sig.upload': 'Upload',
  'profile.sig.saved': 'Saved signature',
  'profile.sig.clear': 'Clear',
  'profile.sig.finger': 'Sign with your finger',
  'profile.sig.choose': 'Choose an image',
  'profile.sig.formats': 'PNG, JPEG or WebP.',
  'profile.sig.none':
      'No saved signature yet — draw one and tick “save for next time”.',
  'profile.sig.lastUpdated': 'Last updated @date',
  'profile.sig.savedToast': 'Signature saved',
  'profile.sig.savedBody': 'It will be offered whenever you sign a voucher.',
  'profile.sig.saveFailed': 'Could not save the signature',
  'profile.sig.removed': 'Signature removed',
  'profile.sig.removeFailed': 'Could not remove the signature',
  'profile.remove': 'Remove',
  'profile.save': 'Save',

  // — password & sessions —
  'profile.passwordBody':
      'Use at least 8 characters. Other devices stay signed in until you sign them out below.',
  'profile.passwordShort': 'Use at least 8 characters.',
  'profile.passwordMismatch': 'The passwords do not match.',
  'profile.passwordUpdated': 'Password updated',
  'profile.passwordFailed': 'Could not change your password',
  'profile.activeSessions': 'Active sessions',
  'profile.signOutEverywhere': 'Sign out everywhere',
  'profile.signedOutEverywhere': 'Signed out everywhere',
  'profile.thisDevice': 'This device',
  'profile.revoke': 'Revoke',
  'profile.sessionRevoked': 'Session revoked',
  'profile.noSessions': 'No other sessions.',

  // — appearance & language —
  'profile.appearance': 'Appearance',
  'profile.appearanceBody':
      'Your choice is saved to your profile and follows you to every device.',
  'profile.light': 'Light',
  'profile.dark': 'Dark',
  'profile.languageBody': 'The language of the interface.',
};

const Map<String, String> profileSw = {
  // — tabs —
  'profile.tab.details': 'Taarifa binafsi',
  'profile.tab.signature': 'Sahihi',
  'profile.tab.security': 'Badilisha nenosiri',
  'profile.tab.appearance': 'Mwonekano na lugha',

  // — personal details —
  'profile.details.title': 'Taarifa binafsi',
  'profile.details.body':
      'Jinsi wenzako wanavyokuona kwenye vocha, maoni na mfuatano wa idhini.',
  'profile.fullName': 'Jina kamili',
  'profile.email': 'Barua pepe',
  'profile.emailHint': 'Wasiliana na msimamizi wako kubadilisha anwani yako',
  'profile.phone': 'Simu',
  'profile.jobTitle': 'Cheo',
  'profile.photo': 'Picha',
  'profile.choosePhoto': 'Chagua picha',
  'profile.noPhoto': 'Hakuna faili iliyochaguliwa',
  'profile.photoTooLarge': 'Picha isizidi MB 2.',
  'profile.saveChanges': 'Hifadhi mabadiliko',
  'profile.updated': 'Wasifu umesasishwa',
  'profile.updateFailed': 'Imeshindwa kusasisha wasifu wako',
  'profile.required': 'Hili linahitajika.',

  // — signature —
  'profile.signatureBody':
      'Sahihi yako iliyohifadhiwa hutolewa kila unaposaini vocha, na huchapishwa kwenye PDF.',
  'profile.sig.draw': 'Chora',
  'profile.sig.upload': 'Pakia',
  'profile.sig.saved': 'Sahihi iliyohifadhiwa',
  'profile.sig.clear': 'Futa',
  'profile.sig.finger': 'Saini kwa kidole chako',
  'profile.sig.choose': 'Chagua picha',
  'profile.sig.formats': 'PNG, JPEG au WebP.',
  'profile.sig.none':
      'Bado hakuna sahihi iliyohifadhiwa — chora moja na uweke alama “hifadhi kwa ajili ya wakati ujao”.',
  'profile.sig.lastUpdated': 'Ilisasishwa mwisho @date',
  'profile.sig.savedToast': 'Sahihi imehifadhiwa',
  'profile.sig.savedBody': 'Itatolewa kila unaposaini vocha.',
  'profile.sig.saveFailed': 'Imeshindwa kuhifadhi sahihi',
  'profile.sig.removed': 'Sahihi imeondolewa',
  'profile.sig.removeFailed': 'Imeshindwa kuondoa sahihi',
  'profile.remove': 'Ondoa',
  'profile.save': 'Hifadhi',

  // — password & sessions —
  'profile.passwordBody':
      'Tumia angalau herufi 8. Vifaa vingine vinabaki vimeingia hadi uvitoe hapa chini.',
  'profile.passwordShort': 'Tumia angalau herufi 8.',
  'profile.passwordMismatch': 'Manenosiri hayalingani.',
  'profile.passwordUpdated': 'Nenosiri limesasishwa',
  'profile.passwordFailed': 'Imeshindwa kubadilisha nenosiri lako',
  'profile.activeSessions': 'Vipindi vinavyoendelea',
  'profile.signOutEverywhere': 'Toka kila mahali',
  'profile.signedOutEverywhere': 'Umetoka kila mahali',
  'profile.thisDevice': 'Kifaa hiki',
  'profile.revoke': 'Ondoa ruhusa',
  'profile.sessionRevoked': 'Kipindi kimeondolewa',
  'profile.noSessions': 'Hakuna vipindi vingine.',

  // — appearance & language —
  'profile.appearance': 'Mwonekano',
  'profile.appearanceBody': 'Chaguo lako linahifadhiwa kwenye wasifu wako.',
  'profile.light': 'Mwanga',
  'profile.dark': 'Giza',
  'profile.languageBody': 'Lugha ya kiolesura.',
};
